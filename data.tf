# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

# Get a copy of the firewall policy to be used to check the firewall config
data "azapi_resource" "firewall_policy_current_standard" {
  for_each = var.environment_details

  type        = "Microsoft.Network/firewallPolicies@2026-01-01"
  resource_id = module.vnet_transit[each.key].policy_id_standard
}

data "azapi_resource" "firewall_policy_current_premium" {
  for_each = var.environment_details

  type        = "Microsoft.Network/firewallPolicies@2026-01-01"
  resource_id = module.vnet_transit[each.key].policy_id_premium
}