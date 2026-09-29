# cicd-sandbox

A small, near-free copy of a typical ECS + Terraform layout, used to prove a
PR → plan → approve → apply pipeline before proposing it for a real repo.

## Layout

```
bootstrap/            account-level setup, applied by hand only:
                      budget alert, S3 state bucket, GitHub OIDC, CI roles
terraform/
  modules/            ecs-cluster, ecs-service
  services/<svc>/     one wrapper per service; env vars live here
  envs/dev, envs/prod one state per environment
scripts/
  ship.sh             ship any local edits: branch, fmt, commit, push, PR
  add-env-var.sh      shortcut: edit one env var, then ship.sh
  test-scripts.sh     tests for the two above (local only, pushes nothing)
  ci-plan.sh          used by CI: plan every env, write the PR comment
  ci-apply.sh         used by CI: plan + apply one env
.github/workflows/
  terraform-plan.yml  on PR: fmt check + plan dev and prod, comment on PR
  terraform-apply.yml on merge: apply dev, then prod after approval
docs/                 manual vs automated flow
```

## Flow

1. Edit any files, then `./scripts/ship.sh "echo-service: raise timeout"`
   opens a PR. For a single env var, `./scripts/add-env-var.sh hello-service
   FEATURE_X true` does the edit too.
2. CI posts the dev + prod plan on the PR (read-only AWS role).
3. Merge → dev applies automatically.
4. Approve the `prod` deployment in GitHub → prod applies.

AWS access from CI uses OIDC. No AWS keys are stored in GitHub.

## Cost

About $0/month: ECS services run 0 tasks, state is a few KB in S3, IAM/OIDC
are free. A $5/month budget alert is in `bootstrap/`.
Setting `desired_count` above 0 starts Fargate billing (~$0.01/hour per task).
