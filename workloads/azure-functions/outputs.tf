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
  value = var.function_plan_sku == "FC1" ? azurerm_function_app_flex_consumption.function_app_flex_consumption[0].id : azurerm_linux_function_app.function_app_premium_plan[0].id
}

output "function_app_name" {
  value = var.function_plan_sku == "FC1" ? azurerm_function_app_flex_consumption.function_app_flex_consumption[0].name : azurerm_linux_function_app.function_app_premium_plan[0].name
}