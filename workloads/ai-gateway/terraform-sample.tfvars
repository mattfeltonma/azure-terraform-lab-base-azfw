# Classic SKUs only
#customer_managed_public_ip = false

# Both classic internal mode and v2 with VNet injection
#apim_private_dns_zone_name = "apim.example.com"
#apim_generation_v2 = true
#cloudflare_zone_id = "00000000000000000000000000000000"
#entra_id_tenant_id = "00000000-0000-0000-0000-000000000000"
#letsencrypt_account_key = {
#  key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-centralcredentials/providers/Microsoft.KeyVault/vaults/kvcentral"
#  secret_name           = "letsencryptaccountkey"
#}
#letsencrypt_account_email = "user@example.com"
#networking_model_v2 = "vnet_injected"
#provision_certificate = true
#publisher_name = "example"
#publisher_email = "user@example.com"
#random_string = "xxxx"
#region = "eastus2"
#region_code = "eus2"
#resource_group_dns = "rg-dns-example"
#service_principal_object_id = "00000000-0000-0000-0000-000000000000"
#sku = "PremiumV2_1"
#apim_injection_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-workload/providers/Microsoft.Network/virtualNetworks/vnet-workload/subnets/snet-apim"
#subnet_id_private_endpoints = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-workload/providers/Microsoft.Network/virtualNetworks/vnet-workload/subnets/snet-svc"
#subscription_id_infrastructure = "00000000-0000-0000-0000-000000000000"
#tags = {environment = "lab", product = "apim"}
trusted_ip = "55.55.55.55"
#user_object_id = "00000000-0000-0000-0000-000000000000"
#virtual_network_id_shared_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.Network/virtualNetworks/vnet-shared"

# v2 with Private Endpoint and VNet integration and not using a custom domain
apim_generation_v2 = true
apim_integration_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-workload/providers/Microsoft.Network/virtualNetworks/vnet-workload/subnets/snet-vint"
apim_pe_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-workload/providers/Microsoft.Network/virtualNetworks/vnet-workload/subnets/snet-apim"
entra_id_tenant_id = "00000000-0000-0000-0000-000000000000"
networking_model_v2 = "vnet_integrated"
provision_certificate = false
publisher_name = "example"
publisher_email = "user@example.com"
random_string = "xxxx"
region = "eastus2"
region_code = "eus2"
resource_group_dns = "rg-dns-example"
service_principal_object_id = "00000000-0000-0000-0000-000000000000"
sku = "StandardV2_1"
subnet_id_private_endpoints = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-workload/providers/Microsoft.Network/virtualNetworks/vnet-workload/subnets/snet-svc"
subscription_id_infrastructure = "00000000-0000-0000-0000-000000000000"
tags = {environment = "lab", product = "apim"}
trusted_ip = "55.55.55.55"
user_object_id = "00000000-0000-0000-0000-000000000000"
virtual_network_id_shared_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.Network/virtualNetworks/vnet-shared"