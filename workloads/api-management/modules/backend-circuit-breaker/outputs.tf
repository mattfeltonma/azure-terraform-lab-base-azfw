output "id" {
  value       = azurerm_api_management_backend.backend.id
  description = "The resource ID of the API Management backend with circuit breaker"
}

output "name" {
  value       = azurerm_api_management_backend.backend.name
  description = "The name of the API Management backend with circuit breaker"
}

output "url" {
  value       = var.url
  description = "The URL of the API Management backend with circuit breaker"
}