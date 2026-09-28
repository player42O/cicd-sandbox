output "state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "ci_plan_role_arn" {
  value = aws_iam_role.ci["plan"].arn
}

output "ci_apply_role_arn" {
  value = aws_iam_role.ci["apply"].arn
}
