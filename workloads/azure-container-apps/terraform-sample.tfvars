aca_environment_domain_name = "ace.somedomain.com"
dedicated_workload_profile  = false
letsencrypt_account_email   = "someone@email.com"
letsencrypt_account_key = {
  key_vault_resource_id = "/subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/resourceGroups/rg-centralcredentials/providers/Microsoft.KeyVault/vaults/kvcentraljog"
  secret_name           = "letsencryptaccountkey"
}
region                         = "westus3"
region_code                    = "wus3"
random_string                  = "1gq"
resource_group_name_dns        = "rgshwus31gq"
subnet_id_aca                  = "/subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/resourceGroups/rgwlwus31gq/providers/Microsoft.Network/virtualNetworks/vnetwl2wus31gq/subnets/snet-vint"
subnet_id_svc                  = "/subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/resourceGroups/rgwlwus31gq/providers/Microsoft.Network/virtualNetworks/vnetwl2wus31gq/subnets/snet-svc"
subscription_id_infrastructure = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
tags = {
  environment = "lab"
  product     = "aca"
}
trusted_ip = "X.X.X.X"