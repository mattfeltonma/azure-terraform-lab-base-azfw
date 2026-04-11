## Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

## Create a data source to repreesent the Let's Encrypt account key stored in 
## the Azure Key Vault
data "azurerm_key_vault_secret" "letsencrypt_account_key" {
  count = var.provision_certificate == true ? 1 : 0

  name         = var.letsencrypt_account_key.secret_name
  key_vault_id = var.letsencrypt_account_key.key_vault_resource_id
}

## Retrieve the CSR from the certificate. This is a data plane action against the Key Vault
## and the azurerm_key_vault_certificate resource does not expose the CSR. This requires a 
## cli command to retrieve it in base 64 and convert it to PEM
data "external" "certificate_csr" {
  depends_on = [
    azurerm_key_vault.key_vault_apim_custom_domain
  ]

  count = var.provision_certificate == true ? 1 : 0

  program = ["bash", "-c", <<EOT
    csr=$(az keyvault certificate pending show \
      --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_apim_custom_domain[0].id).resource_name} \
      --name ${azurerm_key_vault_certificate.apim_gateway_certificate[0].name} \
      --query csr -o tsv)
    pem="-----BEGIN CERTIFICATE REQUEST-----\n$csr\n-----END CERTIFICATE REQUEST-----"
    echo "{\"csr\": \"$pem\"}"
  EOT
  ]
}


## Fetch the completed certificate after it's been issued and merged into Key Vault
##
data "azurerm_key_vault_certificate" "apim_gateway_certificate_completed" {
  count = var.provision_certificate == true ? 1 : 0

  depends_on = [
    null_resource.merge_certificate
  ]

  name         = azurerm_key_vault_certificate.apim_gateway_certificate[0].name
  key_vault_id = azurerm_key_vault.key_vault_apim_custom_domain[0].id
}