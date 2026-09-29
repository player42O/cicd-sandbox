module "ecs_service" {
  source = "../../modules/ecs-service"

  project_name   = var.project_name
  environment    = var.environment
  service_name   = "echo-service"
  image          = "public.ecr.aws/nginx/nginx:stable-alpine"
  container_port = 80

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  # Environment variables
  environment_variables = merge(
    {
      APP_NAME        = "echo-service"
      LOG_LEVEL       = var.environment == "prod" ? "info" : "debug"
      ECHO_PREFIX     = "[echo]"
      REQUEST_TIMEOUT = "30"
      MAX_RETRIES     = "3"
    },
    var.extra_environment_variables
  )
}
