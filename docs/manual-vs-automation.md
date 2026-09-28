# Infra change: manual flow vs automated flow

Example change used throughout: **add one environment variable to one service**
(`services/service-a/main.tf`) and roll it out to dev, then prod.

---

## 1. Manual flow (today)

Everything below runs on an engineer's laptop, with their own AWS credentials.

### a. Prepare the change

```bash
cd ~/infra-repo
git switch main
git pull                                   # start from the latest main
git switch -c feature/service-a-add-FEATURE_X
```

Edit `services/service-a/main.tf` and add the variable to `environment_variables`:

```hcl
environment_variables = {
  EXISTING_VAR = "..."
  FEATURE_X    = "true"     # new
}
```

```bash
terraform fmt -recursive                  # keep formatting consistent
git diff                                   # check what changed
```

### b. Commit, push, open the PR

```bash
git add services/service-a/main.tf
git commit -m "service-a: add FEATURE_X env var"
git push -u origin feature/service-a-add-FEATURE_X
gh pr create --base main --reviewer <senior> \
  --title "service-a: add FEATURE_X" --body "Adds FEATURE_X=true to service-a."
```

### c. Review and merge

- Senior reads the diff on GitHub. There is **no plan output** on the PR, so the
  reviewer has to imagine what Terraform will do.
- Senior approves and merges.

### d. Deploy (by hand, on a laptop)

```bash
git switch main && git pull                # get the merged code

aws sso login / aws login                  # engineer's own AWS session
cd envs/dev
terraform init                             # needs the backend config
terraform plan -var-file=dev.tfvars -out=dev.plan    # tfvars live only on the laptop
# read the plan carefully...
terraform apply dev.plan

cd ../prod
terraform init
terraform plan -var-file=prod.tfvars -out=prod.plan
# read the plan carefully...
terraform apply prod.plan
```

### Weak points of the manual flow

| Problem | Why it matters |
|---|---|
| Only people with the tfvars file and AWS admin access can deploy | One person is a bottleneck; nothing ships while they are away |
| The plan is not on the PR | Reviewer approves code without seeing its real effect |
| Apply runs from a laptop | No record of who applied what, when, or from which commit |
| Laptop may be on an old commit or a dirty branch | What is deployed can differ from what is in `main` |
| Long-lived AWS credentials on laptops | Larger blast radius if a laptop or key leaks |
| ~10 manual steps per change | Easy to skip one (forget prod, forget `fmt`, apply the wrong env) |

---

## 2. Automated flow (target)

Same change, but people only do the parts that need a human: **decide** and **approve**.

```
 engineer                GitHub                          AWS
 ────────                ──────                          ───
 run script ───────────► branch + commit + PR
                         │
                         ├─ CI: terraform plan ────────► read-only role (OIDC)
                         │   plan posted on the PR
                         │
 senior reviews ───────► approve + merge
 diff AND plan           │
                         ├─ CD: apply to dev ──────────► apply role (OIDC)
                         │   (automatic)
                         │
 senior approves ──────► "prod" environment gate
 prod deploy             │
                         └─ CD: apply to prod ─────────► apply role (OIDC)
```

### a. Prepare the change: one command (v1)

```bash
./scripts/add-env-var.sh service-a FEATURE_X true
```

The script does steps 1a and 1b for you: switch to an up-to-date `main`, create
the branch, edit `environment_variables`, `terraform fmt`, commit, push, and
open the PR with the right reviewer.

### b. Plan on the PR (v2)

A GitHub Actions workflow runs `terraform plan` for every changed environment
and posts the result as a PR comment. It signs in to AWS with **OIDC** as a
**read-only** role that only pull requests from this repo can assume. No AWS
keys are stored in GitHub.

### c. Review and merge

The senior reviews the diff **and** the exact plan, then approves and merges.

### d. Apply on merge (v3)

- **dev** applies automatically after merge.
- **prod** waits in a GitHub **environment** with a required reviewer. The
  senior clicks *Approve* and the same pipeline applies prod.
- The apply role can only be assumed by jobs running in those environments.
- Every run is logged in GitHub Actions: who approved, which commit, and the full output.

### e. Optional later step (v4)

A GitHub UI form (workflow_dispatch) so non-engineers can request an env var
change without touching git at all.

---

## 3. Side by side

| Step | Manual | Automated |
|---|---|---|
| Create branch, edit, commit, push, PR | Engineer, ~6 commands | Script, 1 command |
| See what Terraform will change | Only whoever runs plan locally | Plan posted on every PR |
| Review | Diff only | Diff + plan |
| Who can deploy | Whoever has tfvars + admin creds | The pipeline, after approval |
| dev deploy | Manual | Automatic after merge |
| prod deploy | Manual | One click on the approval gate |
| AWS credentials | Long-lived, on laptops | Short-lived OIDC tokens, per job |
| Audit trail | None / memory | GitHub Actions run history |
| Deployed code = `main`? | Not guaranteed | Always (runs on the merge commit) |

**What does not change:** a senior still approves every change, and prod still
needs an explicit human approval. The automation removes the typing, not the
control.

---

## 4. Rollout plan

| Version | Adds | Risk |
|---|---|---|
| v1 | PR-creation script; plan/apply stay manual | None: it only automates git |
| v2 | `terraform plan` on PRs (read-only role) | Very low: plan cannot change anything |
| v3 | Apply on merge: dev auto, prod gated | Medium: needs the tfvars moved out of laptops first (e.g. SSM / Secrets Manager / GitHub environment secrets) |
| v4 | UI form | Low |

Each version is useful on its own, so we can stop at any point.

This sandbox repo (personal AWS + GitHub account) is a small copy of the
layout, used to prove each version works before proposing it for the real repo.
