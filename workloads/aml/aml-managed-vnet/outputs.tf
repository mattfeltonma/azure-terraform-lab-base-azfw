output "aml_workspace_container_registry_resource_id" {
  value       = azurerm_container_registry.acr_aml_workspace.id
  description = "The resource id of the AML Workspace Container Registry"
}

output "aml_workspace_resource_id" {
  value       = azapi_resource.aml_workspace.id
  description = "The resource id of the AML Workspace"
}

output "aml_workspace_system_assigned_identity_principal_id" {
  value       = azapi_resource.aml_workspace.output.identity.principalId
  description = "The principal id of the AML Workspace system assigned identity"
}

output "aml_workspace_aml_workspace_id" {
  value       = azapi_resource.aml_workspace.output.properties.workspaceId
  description = "The AML workspace id of the AML Workspace the project is deployed to"
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.law_workload.id
  description = "The resource id of the AML Workspace Log Analytics Workspace"
}

output "aml_workspace_private_endpoint_ip_address" {
  value       = azurerm_private_endpoint.pe_aml_workspace.private_service_connection.0.private_ip_address
  description = "The Private Endpoint IP address of the AML Workspace Private Endpoint"
}

output "aml_workspace_storage_account_id" {
  value       = azurerm_storage_account.storage_account_aml_workspace.id
  description = "The resource id of the AML Workspace Storage Account"
}