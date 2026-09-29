#!/usr/bin/env bash
# Shortcut: add or change one env var in a service, then ship it as a PR.
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
#   --no-push    commit only (no push, no PR)
#
# On main: pulls, edits, and opens a new PR (branch env/<service>-<name>).
# On a feature branch: edits and adds a commit to that branch's PR, so several
# variables can go in one PR.
#
# This script only edits the file; branch, commit, push and PR are done by
# ship.sh (same PR_REVIEWER / BASE_BRANCH settings). For any other kind of
# change, edit the files yourself and run scripts/ship.sh directly.
#
# Edits the first `environment_variables = {...}` map in the service's main.tf.
# Handles `= {`, `= merge({` and `= merge(` with `{` on the next line.
set -euo pipefail

raw=false ship_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --raw) raw=true ;;
    --yes | --no-push) ship_args+=("$1") ;;
    -h | --help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

if [ "$(git branch --show-current)" = "$base" ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git pull -q --ff-only origin "$base" || die "could not fast-forward $base; sort out local commits first"
  fi
  ship_args+=(--branch "env/$service-$(tr 'A-Z_' 'a-z-' <<<"$name")")
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
  unchanged) rm -f "$tmp"; echo "$name already has that value; nothing to do."; exit 0 ;;
  *) rm -f "$tmp"; die "no environment_variables map found in $file" ;;
esac

# fmt also catches a value that breaks the HCL.
if ! terraform fmt -no-color "$file" >/dev/null 2>&1; then
  git checkout -q -- "$file"
  die "the edited value is not valid HCL; nothing changed"
fi

verb=$([ "$result" = added ] && echo add || echo change)
status=0
"$(dirname "$0")/ship.sh" "${ship_args[@]}" "$service: $verb $name" || status=$?

# Cancelled or failed before the commit: don't leave the edit behind.
if ! git diff --quiet -- "$file"; then
  git checkout -q -- "$file"
  echo "Edit to $file reverted."
fi
exit $status
