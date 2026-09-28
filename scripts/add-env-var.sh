#!/usr/bin/env bash
# Add or change one env var in a service and open the PR, in one command.
#
# Usage: scripts/add-env-var.sh [options] <service> <NAME> <value>
#
#   <service>  folder under terraform/services/ (e.g. hello-service)
#   <NAME>     UPPER_SNAKE_CASE variable name
#   <value>    string value (quoted for you); with --raw, an HCL expression
#
# Options:
#   --raw        insert <value> as-is, e.g. var.redis_endpoint
#   --yes        don't ask for confirmation
#   --no-push    commit on a local branch only (no push, no PR)
#
# Environment:
#   PR_REVIEWER  GitHub user to request a review from (optional)
#   BASE_BRANCH  branch to start from and target (default: main)
#
# Edits the first `environment_variables = {...}` map in the service's main.tf.
# Handles `= {`, `= merge({` and `= merge(` with `{` on the next line.
set -euo pipefail

raw=false yes=false push=true
while [ $# -gt 0 ]; do
  case "$1" in
    --raw) raw=true ;;
    --yes) yes=true ;;
    --no-push) push=false ;;
    -h | --help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
  shift
done
[ $# -eq 3 ] || { echo "usage: $(basename "$0") [--raw] [--yes] [--no-push] <service> <NAME> <value>" >&2; exit 1; }

service=$1 name=$2 value=$3
base=${BASE_BRANCH:-main}
die() { echo "error: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
file="terraform/services/$service/main.tf"

[ -f "$file" ] || die "no such service: $file"
[[ $name =~ ^[A-Z][A-Z0-9_]*$ ]] || die "NAME must be UPPER_SNAKE_CASE: $name"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash first"
if $push; then
  gh auth status >/dev/null 2>&1 || die "gh is not logged in"
fi

# HCL value: quote and escape strings; ${ and %{ would start interpolation.
if $raw; then
  hcl_value=$value
else
  escaped=${value//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  escaped=${escaped//\$\{/\$\$\{}
  escaped=${escaped//%\{/%%\{}
  hcl_value="\"$escaped\""
fi

# Start from the latest base branch.
branch="env/$service-$(tr 'A-Z_' 'a-z-' <<<"$name")"
if git remote get-url origin >/dev/null 2>&1; then
  git fetch -q origin "$base"
  start="origin/$base"
else
  start=$base
fi
git rev-parse -q --verify "refs/heads/$branch" >/dev/null && die "branch $branch already exists"
git switch -q -c "$branch" "$start"

# Edit the map. Prints "added", "changed" or "unchanged" to stdout.
tmp=$(mktemp)
# Passed via ENVIRON: awk -v would eat the backslashes in escaped quotes.
result=$(AWK_NAME=$name AWK_VAL=$hcl_value AWK_OUT=$tmp awk '
  function braces(s,   o, c) { o = gsub(/\{/, "{", s); c = gsub(/\}/, "}", s); return o - c }
  function emit(s) { print s > out }
  BEGIN {
    name = ENVIRON["AWK_NAME"]; val = ENVIRON["AWK_VAL"]; out = ENVIRON["AWK_OUT"]
    state = "search"; result = "notfound"
  }
  {
    line = $0
    if (state == "search" && line ~ /^[[:space:]]*environment_variables[[:space:]]*=/) state = "open"
    if (state == "open" && index(line, "{")) {
      state = "inside"; depth = braces(line); emit(line); next
    }
    if (state == "inside") {
      if (indent == "" && line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) {
        match(line, /^[[:space:]]*/); indent = substr(line, 1, RLENGTH)
      }
      # A key at the top level of the map (not inside a nested block).
      if (depth == 1 && line ~ "^[[:space:]]*" name "[[:space:]]*=") {
        match(line, /^[[:space:]]*/)
        newline = substr(line, 1, RLENGTH) name " = " val
        # Compare ignoring alignment spaces around "=".
        a = line; b = newline; gsub(/[[:space:]]+/, " ", a); gsub(/[[:space:]]+/, " ", b)
        result = (a == b) ? "unchanged" : "changed"
        emit(newline); state = "done"; next
      }
      depth += braces(line)
      if (depth <= 0) {
        emit(indent name " = " val); result = "added"; state = "done"
      }
    }
    emit(line)
  }
  END { print result }
' "$file")

case "$result" in
  added | changed) mv "$tmp" "$file" ;;
  unchanged) rm -f "$tmp"; git switch -q -; git branch -q -D "$branch"; echo "$name already has that value; nothing to do."; exit 0 ;;
  *) rm -f "$tmp"; git switch -q -; git branch -q -D "$branch"; die "no environment_variables map found in $file" ;;
esac

# fmt also catches a value that breaks the HCL; undo everything if so.
if ! terraform fmt -no-color "$file" >/dev/null 2>&1; then
  git checkout -q -- "$file"; git switch -q -; git branch -q -D "$branch"
  die "the edited file is not valid HCL; nothing changed"
fi
git --no-pager diff -- "$file"

if ! $yes; then
  read -rp "Commit and open a PR for this change? [y/N] " answer
  if [[ ! $answer =~ ^[Yy]$ ]]; then
    git checkout -q -- "$file"; git switch -q -; git branch -q -D "$branch"
    echo "Cancelled; nothing changed."; exit 1
  fi
fi

verb=$([ "$result" = added ] && echo add || echo change)
title="$service: $verb $name"
git add "$file"
git commit -q -m "$title"
echo "Committed on $branch: $title"

if ! $push; then
  echo "--no-push: stopping here. Push with: git push -u origin $branch"
  exit 0
fi

git push -q -u origin "$branch"
body="$(printf '%s `%s` in `%s` (all environments).\n\nThe Terraform plan for dev and prod will be posted below by CI.' \
  "$([ "$result" = added ] && echo Adds || echo Changes)" "$name" "$service")"
reviewer_args=()
[ -n "${PR_REVIEWER:-}" ] && reviewer_args=(--reviewer "$PR_REVIEWER")
gh pr create --base "$base" --head "$branch" --title "$title" --body "$body" "${reviewer_args[@]}"
