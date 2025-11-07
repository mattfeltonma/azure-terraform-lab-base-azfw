output "hub_workspace_container_registry_resource_id" {
  value       = azurerm_container_registry.acr_aml_hub.id
  description = "The resource id of the AML Hub Container Registry"
}

output "hub_workspace_resource_id" {
  value       = azapi_resource.aml_hub.id
  description = "The resource id of the AML Hub"
}

output "hub_workspace_system_assigned_identity_principal_id" {
  value       = azapi_resource.aml_hub.output.identity.principalId
  description = "The principal id of the AML Hub system assigned identity"
}

output "hub_workspace_aml_workspace_id" {
  value       = azapi_resource.aml_hub.output.properties.workspaceId
  description = "The AML workspace id of the AML Hub Workspace the project is deployed to"
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  description = "The resource id of the AML Hub Log Analytics Workspace"
}

output "hub_workspace_private_endpoint_ip_address" {
  value       = azurerm_private_endpoint.pe_aml_hub.private_service_connection.0.private_ip_address
  description = "The Private Endpoint IP address of the AML Hub Workspace Private Endpoint"
}

output "hub_workspace_storage_account_id" {
  value       = azurerm_storage_account.storage_account_aml_hub.id
  description = "The resource id of the AML Hub Storage Account"
}