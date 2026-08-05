output "id" {
  value       = azapi_resource.backend.id
  description = "The resource ID of the API Management backend with circuit breaker"
}

output "name" {
  value       = azapi_resource.backend.name
  description = "The name of the API Management backend with circuit breaker"
}