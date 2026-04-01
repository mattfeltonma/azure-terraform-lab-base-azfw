# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "letsencrypt_account_key" {
  count = var.aca_environment_domain_name != null ? 1 : 0

  name         = var.letsencrypt_account_key.secret_name
  key_vault_id = var.letsencrypt_account_key.key_vault_resource_id
}

## Retrieve the CSR from the certificate. This is a data plane action against the Key Vault
## and the azurerm_key_vault_certificate resource does not expose the CSR. This requires a 
## cli command to retrieve it in base 64 and convert it to PEM
data "external" "certificate_csr" {
  depends_on = [
    azurerm_key_vault_certificate.aca_env_certificate
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  program = ["bash", "-c", <<EOT
    csr=$(az keyvault certificate pending show \
      --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_aca_env_custom_domain[0].id).resource_name} \
      --name ${azurerm_key_vault_certificate.aca_env_certificate[0].name} \
      --query csr -o tsv)
    pem="-----BEGIN CERTIFICATE REQUEST-----\n$csr\n-----END CERTIFICATE REQUEST-----"
    echo "{\"csr\": \"$pem\"}"
  EOT
  ]
}
