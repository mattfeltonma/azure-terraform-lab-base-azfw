output "vnet_workload_name" {
  value       = azurerm_virtual_network.vnet_workload.name
  description = "The name of the virtual network"
}

output "vnet_workload_id" {
  value       = azurerm_virtual_network.vnet_workload.id
  description = "The id of the virtual network"
}

output "route_table_id_app_gateway" {
  value       = azurerm_route_table.route_table_app_gateway.id
  description = "The resource id of the Application Gateway route table"
}

output "route_table_id_amlcpt" {
  value       = azurerm_route_table.route_table_amlcpt.id
  description = "The resource id of the AML Compute route table"
}

output "route_table_id_apim" {
  value       = azurerm_route_table.route_table_apim.id
  description = "The resource id of the API Management route table"
}

output "route_table_id_app" {
  value       = azurerm_route_table.route_table_app.id
  description = "The resource id of the application route table"
}

output "route_table_id_data" {
  value       = azurerm_route_table.route_table_data.id
  description = "The resource id of the data route table"
}

output "route_table_id_mgmt" {
  value       = azurerm_route_table.route_table_mgmt.id
  description = "The resource id of the management route table"
}

output "route_table_id_vint" {
  value       = azurerm_route_table.route_table_vint.id
  description = "The resource id of the virtual network integration route table"
}

output "subnet_id_app_gateway" {
  value       = azurerm_subnet.subnet_app_gateway.id
  description = "The resource id of the Application Gateway subnet"
}

output "subnet_id_amlcpt" {
  value       = azurerm_subnet.subnet_amlcpt.id
  description = "The resource id of the AML Compute subnet"
}

output "subnet_id_apim" {
  value       = azurerm_subnet.subnet_apim.id
  description = "The resource id of the API Management subnet"
}

output "subnet_id_app" {
  value       = azurerm_subnet.subnet_app.id
  description = "The resource id of the application subnet"
}

output "subnet_id_data" {
  value       = azurerm_subnet.subnet_data.id
  description = "The resource id of the data subnet"
}

output "subnet_id_mgmt" {
  value       = azurerm_subnet.subnet_mgmt.id
  description = "The resource id of the management subnet"
}

output "subnet_id_svc" {
  value       = azurerm_subnet.subnet_svc.id
  description = "The resource id of the services subnet"
}

output "subnet_id_vint" {
  value       = azurerm_subnet.subnet_vint.id
  description = "The resource id of the virtual network integration subnet"
}