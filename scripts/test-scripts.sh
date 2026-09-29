#!/usr/bin/env bash
# Tests for ship.sh and add-env-var.sh. Safe to run any time: it works in a
# temp dir against a local copy of origin, and gh is replaced by a stub, so
# nothing is pushed to GitHub. Run: scripts/test-scripts.sh
SRC=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
T=$(mktemp -d)
git clone -q --bare "$(git -C "$SRC" remote get-url origin)" "$T/origin.git"
git clone -q "$T/origin.git" "$T/work"
git clone -q "$T/origin.git" "$T/other"   # a teammate, to move origin/main ahead
cd "$T/work"
cp "$SRC"/scripts/{ship,add-env-var}.sh scripts/
git -C "$T/other" config user.email t@t && git -C "$T/other" config user.name t
git config user.email t@t && git config user.name t
# Commit the new scripts to origin so every test starts clean.
git add -A && git commit -qm "scripts under test" && git push -q origin main

mkdir -p "$T/bin"
cat >"$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >>"$T/gh.log"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr view") [ -f "$T/pr-state" ] && echo "\$(cat $T/pr-state) https://example/pr/1"; exit 0 ;;
  "pr create") echo OPEN >"$T/pr-state"; echo "https://example/pr/1" ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

pass=0 fail=0
check() { # check "<name>" <expected-exit> <actual-exit> "<extra condition result>"
  if [ "$2" = "$3" ] && [ "${4:-ok}" = ok ]; then echo "PASS $1"; pass=$((pass+1));
  else echo "FAIL $1 (exit $3, wanted $2; cond=${4:-ok})"; fail=$((fail+1)); fi
}
reset_main() { git switch -q main 2>/dev/null; git reset -q --hard origin/main; git clean -qfd; rm -f "$T/pr-state"; }
S=./scripts/ship.sh
A=./scripts/add-env-var.sh
f=terraform/services/hello-service/main.tf

# 1. Nothing to ship
$S --yes "noop" >/dev/null; check "clean tree -> nothing to ship" 2 $?

# 2. Edit on main -> new branch from origin/main, pushed, PR created, local main untouched
sed -i 's/GREETING  = "hello"/GREETING  = "hi"/' $f
$S --yes "hello-service: say hi" >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = change/hello-service-say-hi ] \
  && git ls-remote --exit-code origin change/hello-service-say-hi >/dev/null \
  && [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] \
  && grep -q "pr create" "$T/gh.log" && echo ok || echo bad)
check "edit on main -> branch, push, PR" 0 $rc "$c"

# 3. Second edit on that branch -> commit + push, updates existing PR (no new PR)
: >"$T/gh.log"
sed -i 's/GREETING  = "hi"/GREETING  = "hey"/' $f
out=$($S --yes "hello-service: say hey" 2>&1); rc=$?
c=$(grep -q "Updated existing PR" <<<"$out" && ! grep -q "pr create" "$T/gh.log" \
  && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/change/hello-service-say-hi)" ] && echo ok || echo bad)
check "edit on feature branch -> updates PR" 0 $rc "$c"
reset_main

# 4. New untracked file is included
mkdir -p terraform/services/new-svc && printf 'locals {\n  a = 1\n}\n' > terraform/services/new-svc/main.tf
$S --yes --no-push "add new-svc" >/dev/null 2>&1; rc=$?
c=$(git show --name-only --format= HEAD | grep -q new-svc/main.tf && echo ok || echo bad)
check "untracked file included" 0 $rc "$c"
reset_main

# 5. Badly formatted file gets formatted in the commit
sed -i 's/^\(    APP_NAME  = "hello-service"\)$/\1\n        X = "1"/' $f   # new line, wrong indent
$S --yes --no-push "fmt test" >/dev/null 2>&1; rc=$?
c=$(git show HEAD:$f | grep -qE '^    X +?= "1"$' && echo ok || echo bad)
check "fmt applied before commit" 0 $rc "$c"
reset_main

# 5b. Whitespace-only edit that fmt undoes -> nothing to ship
sed -i 's/APP_NAME  = "hello-service"/APP_NAME = "hello-service"/' $f
$S --yes --no-push "whitespace only" >/dev/null 2>&1; check "fmt leaves no changes -> nothing to ship" 2 $?
reset_main

# 6. Invalid HCL -> error, still on main, edit kept, nothing committed
echo 'broken = (((' >> $f
$S --yes "broken" >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = main ] && ! git diff --quiet -- $f \
  && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && echo ok || echo bad)
check "invalid HCL stops before branching" 1 $rc "$c"
reset_main

# 7. Local commit on main not on origin -> refuse
echo "# note" >> README.md && git commit -qam "local only" && echo "# more" >> README.md
$S --yes "should refuse" >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = main ] && echo ok || echo bad)
check "local-only commit on main -> refuse" 1 $rc "$c"
reset_main

# 8. origin/main moved ahead (teammate), edit a different file -> branch from new origin/main
git -C "$T/other" pull -q && echo "# teammate" >> "$T/other/README.md" \
  && git -C "$T/other" commit -qam "teammate change" && git -C "$T/other" push -q
sed -i 's/GREETING  = "hello"/GREETING  = "yo"/' $f
$S --yes --no-push "behind but no conflict" >/dev/null 2>&1; rc=$?
c=$(git merge-base --is-ancestor origin/main HEAD && grep -q teammate README.md && echo ok || echo bad)
check "behind origin, no conflict -> based on latest" 0 $rc "$c"
git switch -q main; git branch -q -D change/behind-but-no-conflict

# 9. origin/main changed the same file you edited -> refuse, edit kept
git -C "$T/other" pull -q && sed -i 's/GREETING  = "hello"/GREETING  = "teammate"/' "$T/other/$f" \
  && git -C "$T/other" commit -qam "teammate edits hello" && git -C "$T/other" push -q
git reset -q --hard HEAD   # local main is now 2 behind origin
sed -i 's/GREETING  = "hello"/GREETING  = "mine"/' $f
$S --yes "conflict" >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = main ] && grep -q '"mine"' $f && git diff --cached --quiet && echo ok || echo bad)
check "conflicting upstream change -> refuse, edit kept" 1 $rc "$c"
reset_main

# 10. Answer "n" -> cancelled, edit kept, nothing staged
sed -i 's/GREETING  = "teammate"/GREETING  = "cancel-me"/' $f
echo n | $S "cancel" >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = main ] && grep -q cancel-me $f && git diff --cached --quiet && echo ok || echo bad)
check "answer n -> cancelled, edit kept" 2 $rc "$c"
reset_main

# 11. add-env-var on main -> env/ branch + PR via ship
: >"$T/gh.log"
$A --yes hello-service NEW_FLAG on >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = env/hello-service-new-flag ] && grep -q 'NEW_FLAG *= "on"' $f \
  && grep -q "pr create" "$T/gh.log" && echo ok || echo bad)
check "add-env-var on main -> new PR" 0 $rc "$c"

# 12. add-env-var again on that branch -> second commit, same PR
: >"$T/gh.log"
$A --yes hello-service OTHER_FLAG off >/dev/null 2>&1; rc=$?
c=$([ "$(git branch --show-current)" = env/hello-service-new-flag ] && [ "$(git rev-list --count origin/main..HEAD)" = 2 ] \
  && ! grep -q "pr create" "$T/gh.log" && echo ok || echo bad)
check "add-env-var on branch -> 2 vars, 1 PR" 0 $rc "$c"
reset_main

# 13. add-env-var cancelled -> edit reverted, clean tree
echo n | $A echo-service CANCELLED x >/dev/null 2>&1; rc=$?
c=$([ -z "$(git status --porcelain)" ] && [ "$(git branch --show-current)" = main ] && echo ok || echo bad)
check "add-env-var cancel -> reverted" 2 $rc "$c"

# 14. add-env-var same value -> nothing to do
$A --yes echo-service REQUEST_TIMEOUT 30 >/dev/null 2>&1; rc=$?
c=$([ -z "$(git status --porcelain)" ] && echo ok || echo bad)
check "add-env-var unchanged -> no-op" 0 $rc "$c"

# 15. Leftover branch whose PR is already merged -> refuse, edit kept
git switch -q -c env/old-merged && echo MERGED >"$T/pr-state"
echo "# late" >> README.md
$S --yes "too late" >/dev/null 2>&1; rc=$?
c=$(grep -q "late" README.md && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && echo ok || echo bad)
check "branch with merged PR -> refuse" 1 $rc "$c"
reset_main

echo "== $pass passed, $fail failed"
rm -rf "$T"
