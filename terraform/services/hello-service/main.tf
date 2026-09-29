module "ecs_service" {
  source = "../../modules/ecs-service"

  project_name   = var.project_name
  environment    = var.environment
  service_name   = "hello-service"
  image          = "public.ecr.aws/nginx/nginx:stable-alpine"
  container_port = 80

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  # Environment variables
  environment_variables = {
    APP_NAME    = "hello-service"
    GREETING    = "hello"
    LOG_LEVEL   = var.environment == "prod" ? "info" : "debug"
    FEATURE_X   = "true"
    MIN_RETRIES = "1"
  }
}
