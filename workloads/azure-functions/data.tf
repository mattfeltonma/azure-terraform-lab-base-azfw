# Get the azurerm provider details such as active subscription id
data "azurerm_subscription" "current" {}
data "azurerm_client_config" "identity_config" {}
data "azurerm_client_config" "current" {}

# Get the azuread provider details
data "azuread_client_config" "current" {}