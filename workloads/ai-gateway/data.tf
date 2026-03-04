# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

## Retrieve the CSR from the certificate. This is a data plane action against the Key Vault
## and the azurerm_key_vault_certificate resource does not expose the CSR. This requires a 
## cli command to retrieve it in base 64 and convert it to PEM
data "external" "certificate_csr" {
  count = var.provision_certificate ? 1 : 0

  depends_on = [
    azurerm_key_vault_certificate.apim_gateway_certificate
  ]

  program = ["bash", "-c", <<EOT
    csr=$(az keyvault certificate pending show \
      --vault-name ${provider::azurerm::parse_resource_id(var.key_vault_id).resource_name} \
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
  key_vault_id = var.key_vault_id
}