output "aml_registry_production_resource_id" {
  value       = azapi_resource.aml_registry_production.id
  description = "The resource id of the Production AML Registry"
}

output "aml_registry_non_production_resource_id" {
  value       = azapi_resource.aml_registry_non_production.id
  description = "The resource id of the Non-Production AML Registry"
}