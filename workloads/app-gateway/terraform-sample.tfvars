app_gateway_domain_name = "agw.example.com"
letsencrypt_account_email = "admin@example.com"
letsencrypt_account_key = {
  key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-centralcredentials/providers/Microsoft.KeyVault/vaults/kvcentral"
  secret_name           = "letsencryptaccountkey"
}
private_ip_address = "10.0.8.10"
public_listener = true
region = "westus3"
region_code = "wus3"
random_string = "abc123"
resource_group_name_dns = "rgshwus3abc"
subnet_id_app_gateway = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rgwlwus3abc/providers/Microsoft.Network/virtualNetworks/vnetwl1wus3abc/subnets/snet-agw"
subnet_id_svc = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rgwlwus3abc/providers/Microsoft.Network/virtualNetworks/vnetwl1wus3abc/subnets/snet-svc"
subscription_id_infrastructure = "00000000-0000-0000-0000-000000000000"
tags = {
  environment = "lab"
  product     = "agw"
}
tcp_port = 3389
trusted_ip = "0.0.0.0"