output "key_vault_id" {
  value = azurerm_key_vault.key_vault_function.id
}

output "key_vault_name" {
  value = azurerm_key_vault.key_vault_function.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.key_vault_function.vault_uri
}

output "function_app_id" {
  value = azurerm_function_app_flex_consumption.function_app.id
}

output "function_app_name" {
  value = azurerm_function_app_flex_consumption.function_app.name
}