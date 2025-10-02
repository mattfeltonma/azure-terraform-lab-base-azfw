# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

data "azurerm_client_config" "current" {}

# Retrieve the API keys for the Bing Grounding Search resource
data "azapi_resource_action" "bing_api_keys" {
  depends_on = [
    azapi_resource.bing_grounding_search_foundry
  ]

  type                   = "Microsoft.Bing/accounts@2020-06-10"
  resource_id            = azapi_resource.bing_grounding_search_foundry.id
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["key1", "key2"]
}