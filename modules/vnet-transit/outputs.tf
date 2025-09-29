output "azfw_private_ip" {
  value = azurerm_firewall.azure_firewall.ip_configuration[0].private_ip_address
  description = "The private IP address of the Azure Firewall"
}

output "policy_id" {
  value       = azurerm_firewall_policy.firewall_policy.id
  description = "The id of the Azure Firewall Policy"
}

output "resource_group_name_transit" {
  value       = var.resource_group_name
  description = "The name of the transit services resource group"
}
 
output "route_table_id_gateway" {
  value       = azurerm_route_table.rt_gateway.id
  description = "The id of the route table associated with the GatewaySubnet"
}

output "route_table_id_azfw" {
  value       = azurerm_route_table.rt_azfw.id
  description = "The id of the route table associated with the AzureFirewallSubnett"
}

output "route_table_name_gateway" {
  value       = azurerm_route_table.rt_gateway.name
  description = "The name of the route table associated with the GatewaySubnet"
}

output "route_table_name_azfw" {
  value       = azurerm_route_table.rt_azfw.name
  description = "The name of the route table associated with the AzureFirewallSubnet"
}

output "subnet_id_gateway" {
  value       = azurerm_subnet.subnet_gateway.id
  description = "The resource id of the GatewaySubnet subnet"
}

output "subnet_id_firewall" {
  value       = azurerm_subnet.subnet_firewall.id
  description = "The resource id of the AzureFirewallSubnet subnet"
}

output "vnet_transit_name" {
  value       = azurerm_virtual_network.vnet_transit.name
  description = "The name of the transit virtual network"
}

output "vnet_transit_id" {
  value       = azurerm_virtual_network.vnet_transit.id
  description = "The id of the transit virtual network"
}