output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "services" {
  value = [
    module.hello_service.service_name,
    module.echo_service.service_name,
    module.worker_service.service_name,
  ]
}
