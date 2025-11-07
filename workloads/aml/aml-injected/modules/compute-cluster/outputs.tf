output "compute_cluster_build_id" {
  description = "The resource ID of the AML Compute Cluster for building environment images"
  value       = azurerm_machine_learning_compute_cluster.aml_compute_cluster_build.id
}

output "compute_cluster_build_name" {
  description = "The name of the AML Compute Cluster for building environment images"
  value       = azurerm_machine_learning_compute_cluster.aml_compute_cluster_build.name
}