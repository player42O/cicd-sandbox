resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-${var.environment}"

  # Container Insights bills per metric; not needed for the sandbox.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
