#!/usr/bin/env bash
# Plan each environment and write plan-comment.md (posted on the PR by CI).
# Exits non-zero if any plan fails, so the PR check goes red.
#
# Usage: scripts/ci-plan.sh dev prod
set -uo pipefail

root=$(git rev-parse --show-toplevel)
out="$root/plan-comment.md"
max_chars=30000 # GitHub comments are capped at 65536 characters
failed=0

{
  echo "## Terraform plan"
  echo
  echo "Commit: \`${GITHUB_SHA:-$(git rev-parse HEAD)}\`"
} >"$out"

for env in "$@"; do
  dir="$root/terraform/envs/$env"
  log=$(mktemp)

  if ! terraform -chdir="$dir" init -input=false -no-color >"$log" 2>&1; then
    summary="FAILED (init)"
    failed=1
  else
    terraform -chdir="$dir" plan -input=false -no-color -lock-timeout=120s \
      -detailed-exitcode >"$log" 2>&1
    case $? in
      0) summary="No changes" ;;
      2) summary=$(grep -E '^Plan:' "$log" | head -1) ;;
      *) summary="FAILED"; failed=1 ;;
    esac
  fi

  # Drop the refresh noise; keep the diff and any errors.
  body=$(grep -vE 'Refreshing state|Reading\.\.\.|Read complete after' "$log")
  if [ ${#body} -gt $max_chars ]; then
    body="${body:0:$max_chars}"$'\n\n... truncated, see the workflow log for the full plan.'
  fi

  {
    echo
    echo "### \`$env\`: $summary"
    echo
    echo "<details><summary>Show plan</summary>"
    echo
    echo '```'
    echo "$body"
    echo '```'
    echo
    echo "</details>"
  } >>"$out"

  echo "$env: $summary"
  rm -f "$log"
done

[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$out" >>"$GITHUB_STEP_SUMMARY"
exit $failed
