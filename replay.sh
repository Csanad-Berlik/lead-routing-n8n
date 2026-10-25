#!/usr/bin/env bash
# Send nine sample leads to the n8n webhook, one by one, and print what each should do.
#
#   WEBHOOK_URL=http://localhost:5678/webhook/<path> LEAD_SECRET=<secret> bash replay.sh [tag]
#
# Before a run:
#   - Event IDs and emails are prefixed with a tag (default: the time), because Remove
#     Duplicates remembers every lead ID it has seen. Use a new tag for every run.
#   - Every run creates new contacts in HubSpot (the emails carry the tag). Delete them
#     from the test account when you are done if you want a clean list.
#   - HubSpot creates a task about a minute after the contact is saved, not at once.
#
# n8n answers 200 "Workflow was started" before the checks run, so the HTTP code only shows
# that the lead was received (or refused, for a wrong secret). Open Executions in n8n to see
# where each run stopped, and open the contacts in HubSpot to check the owner, the grade
# and the task. Compare both with the last column.

set -u
: "${WEBHOOK_URL:?Set WEBHOOK_URL to the production webhook URL}"
: "${LEAD_SECRET:?Set LEAD_SECRET to the header auth secret}"
TAG="${1:-$(date +%H%M%S)}"

failures=0

send() {  # label, id, first name, job title, domain, with_email (yes/no), secret, want_code, expected
  local label="$1" id="$2" name="$3" title="$4" domain="$5" with_email="$6" secret="$7" want="$8" expected="$9"
  local email="" body code
  if [ "$with_email" = "yes" ]; then
    email="${TAG}-$(echo "$name" | tr 'A-Z' 'a-z')@example.org"
  fi
  body=$(printf '{"lead_id":"%s-%s","email":"%s","first_name":"%s","job_title":"%s","domain":"%s","ts":"2026-10-24T09:00:00Z"}' \
    "$TAG" "$id" "$email" "$name" "$title" "$domain")
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "X-Lead-Secret: $secret" -H "Content-Type: application/json" -d "$body")
  local ok="yes"
  if [ "$code" != "$want" ]; then ok="NO"; failures=$((failures + 1)); fi
  printf '%-3s %-5s HTTP %-4s (want %s) %-4s %s\n' "$label" "$id" "$code" "$want" "$ok" "$expected"
  sleep 2
}

printf '%-3s %-5s %s\n' "#" "lead" "result, then what should happen in n8n and HubSpot"
send 1 l1 Alice "Head of Sales"     prezi.com        yes "$LEAD_SECRET" 200 "A (4 points) -> Owner 1, High task, due next business day"
send 2 l2 Bob   "Marketing Manager" hubspot.com      yes "$LEAD_SECRET" 200 "C (1 point) -> Owner 2, Low task, due in 5 business days"
send 3 l3 Cleo  "Sales Rep"         prezi.com        yes "$LEAD_SECRET" 200 "B (3 points) -> Owner 2, Medium task, due in 3 business days"
send 4 l4 Dan   "Founder"           n8n.io           yes "$LEAD_SECRET" 200 "B (3 points) -> Owner 2, Medium task, due in 3 business days"
send 5 l5 Eve   "VP Sales"          attio.com        yes "$LEAD_SECRET" 200 "A (4 points) -> Owner 1, High task, due next business day"
send 6 l6 Finn  "Engineer"          notinlist.example yes "$LEAD_SECRET" 200 "Unknown (company not in the list) -> Owner 2, Low task"
# Lead 7 reuses lead 1's ID, so it must have exactly lead 1's content.
send 7 l1 Alice "Head of Sales"     prezi.com        yes "$LEAD_SECRET" 200 "Remove Duplicates (ID already seen), no second contact or task"
send 8 l8 Gus   "Head of Sales"     prezi.com        no  "$LEAD_SECRET" 200 "Has email (no email), nothing written to HubSpot"
send 9 l9 Nina  "Head of Sales"     prezi.com        yes "wrong-secret" 403 "no run starts (403 Forbidden)"

echo
if [ "$failures" -eq 0 ]; then echo "All HTTP codes as expected. Now check Executions and HubSpot."; else echo "$failures HTTP code(s) not as expected."; fi
