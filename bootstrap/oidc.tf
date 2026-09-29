# GitHub Actions signs in with short-lived OIDC tokens: no AWS keys stored in GitHub.
#
# Two roles, each trusted by exactly one repo and one kind of job:
#   ci-plan  - pull request jobs, and jobs on main outside an environment
#              (prod plan before approval, nightly drift check); read-only,
#              can plan but not change anything.
#   ci-apply - jobs running in the dev/prod GitHub environments (prod has a
#              required reviewer), so only approved deploys get write access.
#
# Neither role can edit these roles or this bootstrap stack; bootstrap is only
# ever applied by hand with the admin user.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  app_role_arn_pattern = "arn:aws:iam::${var.account_id}:role/cicd-sandbox-app-*"
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    plan = [
      "${var.github_oidc_subject_prefix}:pull_request",
      "${var.github_oidc_subject_prefix}:ref:refs/heads/main",
    ]
    apply = [for env in ["dev", "prod"] : "${var.github_oidc_subject_prefix}:environment:${env}"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each = data.aws_iam_policy_document.github_trust

  name               = "cicd-sandbox-ci-${each.key}"
  assume_role_policy = each.value.json
}

# --- ci-plan: read everything, write only the state lock file ---

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.ci["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.ci["plan"].id
  policy = data.aws_iam_policy_document.plan_state_lock.json
}

# --- ci-apply: PowerUser (no IAM), plus IAM limited to cicd-sandbox-app-* roles ---

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.ci["apply"].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_app_roles" {
  statement {
    sid = "ManageAppRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.app_role_arn_pattern]
  }

  statement {
    sid       = "PassAppRolesToEcs"
    actions   = ["iam:PassRole"]
    resources = [local.app_role_arn_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "apply_app_roles" {
  name   = "app-roles"
  role   = aws_iam_role.ci["apply"].id
  policy = data.aws_iam_policy_document.apply_app_roles.json
}
