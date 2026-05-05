# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "letsencrypt_account_key" {
  name         = var.letsencrypt_account_key.secret_name
  key_vault_id = var.letsencrypt_account_key.key_vault_resource_id
}

## Retrieve the CSR from the certificate. This is a data plane action against the Key Vault
## and the azurerm_key_vault_certificate resource does not expose the CSR. This requires a 
## cli command to retrieve it in base 64 and convert it to PEM
data "external" "certificate_csr" {
  depends_on = [
    azurerm_key_vault_certificate.app_gateway_certificate
  ]

  program = ["bash", "-c", <<EOT
    csr=$(az keyvault certificate pending show \
      --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_app_gateway_custom_domain.id).resource_name} \
      --name ${azurerm_key_vault_certificate.app_gateway_certificate.name} \
      --query csr -o tsv)
    pem="-----BEGIN CERTIFICATE REQUEST-----\n$csr\n-----END CERTIFICATE REQUEST-----"
    echo "{\"csr\": \"$pem\"}"
  EOT
  ]
}

## Fetch the completed certificate after it's been issued and merged into Key Vault
##
data "azurerm_key_vault_certificate" "app_gateway_certificate_completed" {
  depends_on = [
    null_resource.merge_certificate
  ]

  name         = azurerm_key_vault_certificate.app_gateway_certificate.name
  key_vault_id = azurerm_key_vault.key_vault_app_gateway_custom_domain.id
}
