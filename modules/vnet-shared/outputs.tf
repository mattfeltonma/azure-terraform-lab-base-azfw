output "private_resolver_inbound_endpoint_ip" {
  value       = azurerm_private_dns_resolver_inbound_endpoint.inbound_endpoint.ip_configurations[0].private_ip_address
  description = "The private IP address of the Azure Private DNS Resolver inbound endpoint"
}

output "dns_resolver_inbound_endpoint_resource_id" {
  value       = azurerm_private_dns_resolver_inbound_endpoint.inbound_endpoint.id
  description = "The resource ID of the Azure Private DNS Resolver inbound endpoint"
}

output "resource_group_name_shared_services" {
  value       = var.resource_group_name
  description = "The name of the shared services resource group"
}

output "subnet_id_bastion" {
  value       = azurerm_subnet.subnet_bastion.id
  description = "The resource id of the Azure Bastion subnet"
}
 
output "subnet_id_dnsin" {
  value       = azurerm_subnet.subnet_dnsin.id
  description = "The resource id of the Private DNS Resolver Inbound endpoint subnet"
}

output "subnet_id_dnsout" {
  value       = azurerm_subnet.subnet_dnsout.id
  description = "The resource id of the Private DNS Resolver Outbound endpoint subnet"
}

output "subnet_id_svc" {
  value       = azurerm_subnet.subnet_svc.id
  description = "The resource id of the private endpoint subnet"
}

output "subnet_id_tools" {
  value       = azurerm_subnet.subnet_tools.id
  description = "The resource ID of the tools subnet"
}

output "vnet_shared_services_name" {
  value       = azurerm_virtual_network.vnet_shared.name
  description = "The name of the shared services virtual network"
}

output "vnet_shared_services_resource_id" {
  value       = azurerm_virtual_network.vnet_shared.id
  description = "The resource ID of the shared services virtual network"
}