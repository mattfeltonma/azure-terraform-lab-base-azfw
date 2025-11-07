output "project_resource_id" {
  value       = azapi_resource.aml_project.id
  description = "The resource id of the AML Project"
}

output "project_workspace_id" {
  value       = azapi_resource.aml_project.id
  description = "The resource id of the AML Workspace the project is deployed to"
}

output "project_storage_account_id" {
  value       = azurerm_storage_account.storage_account_project.id
  description = "The resource id of the AML Project Storage Account that can be used for additional storage"
}

output "project_workspace_managed_identity_principal_id" {
  value       = azapi_resource.aml_project.output.identity.principalId
  description = "The principal id of the AML Project workspace managed identity"
}