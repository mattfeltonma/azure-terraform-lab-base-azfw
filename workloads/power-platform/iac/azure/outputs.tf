output "resource_group_name_resources" {
  value = azurerm_resource_group.rg_power_platform_resources.name
}

output "resource_group_id_resources" {
  value = azurerm_resource_group.rg_power_platform_resources.id
}

output "resource_group_name_power_platform_billing" {
  value = azurerm_resource_group.rg_power_platform_billing.name
}

output "resource_group_id_power_platform_billing" {
  value = azurerm_resource_group.rg_power_platform_billing.id
}

output "subscription_id_billing" {
  value = var.subscription_id_billing
}

output "workload_vnet_names" {
  value = {
    for region_index, vnet in module.workload_vnet :
    tostring(region_index) => vnet.vnet_workload_name
  }
}

output "workload_vnet_ids" {
  value = {
    for region_index, vnet in module.workload_vnet :
    tostring(region_index) => vnet.vnet_workload_id
  }
}

output "workload_vnet_subnet_ids" {
  value = {
    for region_index, vnet in module.workload_vnet :
    tostring(region_index) => vnet.subnet_id_app
  }
}