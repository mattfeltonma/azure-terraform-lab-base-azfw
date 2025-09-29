output "dcr_id_windows" {
  value       = azurerm_monitor_data_collection_rule.rule_windows.id
  description = "The resource id of the Data Collection Rule for Windows"
}

output "dcr_id_linux" {
  value       = azurerm_monitor_data_collection_rule.rule_linux.id
  description = "The resource id of the Data Collection Rule for Linux"
}

output "dce_id_primary" {
  value       = azurerm_monitor_data_collection_endpoint.endpoint["primary"].id
  description = "The resource id of the Data Collection Endpoint for the primary region"
}

output "dce_id_secondary" {
  value       = try(azurerm_monitor_data_collection_endpoint.endpoint["secondary"].id, null)
  description = "The resource id of the Data Collection Endpoint for the secondary region"
}

output "name" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace.name
  description = "The name of the log analytics workspace"
}

output "id" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace.id
  description = "The resource id of the log analytics workspace"
}

output "location" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace.location
  description = "The region of the log analytics workspace"
}

output "workspace_id" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace.workspace_id
  description = "The workspace id"
}