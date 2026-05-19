########## Create a Bot Service
##########
##########

## Create the Bot Service
resource "azurerm_bot_service_azure_bot" "bot_service" {
  name                = "bots${var.agent_name}"
  resource_group_name = var.resource_group_name
  location            = "Global"

  display_name            = "Bot Service for ${var.agent_name}"
  microsoft_app_id        = var.agent_identity_principal_id
  microsoft_app_type      = "SingleTenant"
  microsoft_app_tenant_id = var.entra_id_tenant_id

  sku      = var.bot_service_sku
  endpoint = var.activity_endpoint

  public_network_access_enabled = false

  tags = var.tags
}

## Create diagnostic settings for the Bot Service
##
resource "azurerm_monitor_diagnostic_setting" "diag_bot_service" {
  depends_on = [
    azurerm_bot_service_azure_bot.bot_service
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_bot_service_azure_bot.bot_service.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "BotRequest"
  }
}

## Create the Bot Service Channel
##
resource "azurerm_bot_channel_ms_teams" "bot_channel_teams" {
  depends_on = [ 
    azurerm_bot_service_azure_bot.bot_service 
  ]

  bot_name              = azurerm_bot_service_azure_bot.bot_service.name
  location            = "Global"
  resource_group_name = var.resource_group_name
}