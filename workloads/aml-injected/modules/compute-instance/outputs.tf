output "compute_instance_id" {
  description = "The resource ID of the AML Compute Instance for development"
  value       = azurerm_machine_learning_compute_instance.aml_compute_instance_dev.id
}

output "compute_instance_name" {
  description = "The name of the AML Compute Instance for development"
  value       = azurerm_machine_learning_compute_instance.aml_compute_instance_dev.name
}