#!/usr/bin/env bash
# Ship your local edits as a pull request: branch, fmt, commit, push, PR.
# Edit any files you like first, then run this.
#
# Usage: scripts/ship.sh [options] "<title>"
#
#   <title>   commit message and PR title, e.g. "echo-service: raise timeout"
#
# Options:
#   --branch NAME  branch to create (default: change/<title as slug>)
#   --yes          don't ask for confirmation
#   --no-push      commit only; don't push or open a PR
#
# Environment:
#   PR_REVIEWER  GitHub user to request a review from (optional)
#   BASE_BRANCH  branch to start from and target (default: main)
#
# On the base branch: creates a new branch from the latest origin/<base> and
# carries your edits onto it; your local base branch is left untouched.
# On any other branch: commits there and pushes, which updates its open PR.
#
# Exit codes: 0 shipped, 1 error, 2 cancelled or nothing to ship.
set -euo pipefail

yes=false push=true branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:?--branch needs a name}; shift ;;
    --yes) yes=true ;;
    --no-push) push=false ;;
    -h | --help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
  shift
done
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: $(basename "$0") [--branch NAME] [--yes] [--no-push] \"<title>\"" >&2; exit 1; }

title=$1
base=${BASE_BRANCH:-main}
die() { echo "error: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
current=$(git branch --show-current)
[ -n "$current" ] || die "not on a branch (detached HEAD)"

if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to ship: no changes in the working tree."
  exit 2
fi

if $push; then
  gh auth status >/dev/null 2>&1 || die "gh is not logged in"
fi

# Format first, so formatting fixes are part of the commit, and invalid HCL
# stops us before anything is created.
if [ -d terraform ] && ! fmt_out=$(terraform fmt -recursive -no-color terraform 2>&1); then
  echo "$fmt_out" >&2
  die "terraform fmt failed (invalid HCL?); fix the file and run again"
fi
if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to ship: after terraform fmt there are no changes left."
  exit 2
fi

has_origin=false
git remote get-url origin >/dev/null 2>&1 && has_origin=true

if [ "$current" = "$base" ]; then
  if $has_origin; then
    git fetch -q origin "$base"
    start="origin/$base"
    # Local commits on base would be silently left out of the PR.
    ahead=$(git rev-list --count "$start..HEAD")
    [ "$ahead" -eq 0 ] || die "local $base has $ahead commit(s) not on origin; move them to a branch first"
  else
    start=$base
  fi
  if [ -z "$branch" ]; then
    slug=$(tr 'A-Z' 'a-z' <<<"$title" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-50 | sed -E 's/-+$//')
    branch="change/${slug:-update}"
  fi
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name: $branch"
  git rev-parse -q --verify "refs/heads/$branch" >/dev/null && die "branch $branch already exists"
else
  [ -z "$branch" ] || [ "$branch" = "$current" ] || die "--branch given, but you are already on $current"
  branch=$current
  # Committing to a branch whose PR is finished would never deploy.
  if $push; then
    pr_info=$(gh pr view "$branch" --json state,url --jq '.state + " " + .url' 2>/dev/null || true)
    case "$pr_info" in
      MERGED* | CLOSED*) die "the PR for $branch is already ${pr_info%% *}; run: git switch $base && git pull, then ship again" ;;
    esac
  fi
fi

# Review.
git add -A
echo "Branch: $branch (base: $base)"
git --no-pager diff --cached --stat
git --no-pager diff --cached
if ! $yes; then
  read -rp "Commit and push these changes as \"$title\"? [y/N] " answer
  if [[ ! $answer =~ ^[Yy]$ ]]; then
    git reset -q
    echo "Cancelled; your edits are still in the working tree."
    exit 2
  fi
fi

if [ "$current" = "$base" ] && [ "$start" != "$base" ]; then
  # Carries the staged edits over. Git refuses if a file you edited also
  # changed upstream, so nothing can be overwritten.
  if ! git switch -q -c "$branch" "$start" 2>/dev/null; then
    git reset -q
    die "your edits touch files that changed on origin/$base; run: git stash && git pull && git stash pop"
  fi
elif [ "$current" = "$base" ]; then
  git switch -q -c "$branch"
fi

files=$(git diff --cached --name-only)
git commit -q -m "$title"
echo "Committed on $branch: $title"

if ! $push; then
  echo "--no-push: stopping here. Push with: git push -u origin $branch"
  exit 0
fi

git push -q -u origin "$branch"

if [[ ${pr_info:-} == OPEN* ]]; then
  echo "Updated existing PR: ${pr_info#OPEN }"
  exit 0
fi

body="$(printf '%s\n\nFiles changed:\n%s\n\nThe Terraform plan for dev and prod will be posted below by CI.' \
  "$title" "$(sed 's/^/- `/; s/$/`/' <<<"$files")")"
reviewer_args=()
[ -n "${PR_REVIEWER:-}" ] && reviewer_args=(--reviewer "$PR_REVIEWER")
gh pr create --base "$base" --head "$branch" --title "$title" --body "$body" "${reviewer_args[@]}"
