output "project_resource_id" {
  value       = azapi_resource.aml_project.id
  description = "The resource id of the AML Project"
}

output "project_workspace_id" {
  value       = azapi_resource.aml_project.id
  description = "The resource id of the AML Workspace the project is deployed to"
}