# Get the azurerm provider details such as active subscription id
data "azurerm_subscription" "current" {}
data "azurerm_client_config" "identity_config" {}
data "azurerm_client_config" "current" {}

# Get the azuread provider details
data "azuread_client_config" "current" {}

# Get the secret uri for the storage account connection string from the key vault
data "azurerm_key_vault_secret" "secret_storage_account_connection_string_function" {
  depends_on = [
    azurerm_key_vault_secret.secret_storage_account_connection_string_function
  ]

  name         = "storageaccountconnectionstring"
  key_vault_id = azurerm_key_vault.key_vault_function.id
}