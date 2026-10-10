############################## Azure Stuff
##############################
##############################

########## Create base resources
##########
##########

## Use time_static to generate a timestamp which will be used in created_date tag. Use this instead of timestamp
## so Terraform doesn't freak out every time apply is run again
##
resource "time_static" "created" {}

########## Register Power.Platform resource provider
##########
##########

## Register the Microsoft.PowerPlatform resource provider with the Azure subscription
## This can take a few minutes
resource "azurerm_resource_provider_registration" "power_platform" {
  name = "Microsoft.PowerPlatform"
}

########## Create resource group for the billing policy and resource group containing the Azure resources, log analytics workspace, storage account for flow logs,
########## and workload virtual networks that will have subnets delegated to Power Platform
##########

## Create the resource group that the billing policy will be associated with
##
resource "azurerm_resource_group" "rg_power_platform_billing" {
  provider = azurerm.subscription_billing

  name     = "rgppbilling${var.random_string}"
  location = var.regions[0].name
  tags     = merge(var.tags, local.tags)

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create resource groups that will contain virtual networks delegated to Power Platform
##
resource "azurerm_resource_group" "rg_power_platform_resources" {
  depends_on = [
    azurerm_resource_provider_registration.power_platform
  ]

  name     = "rgpp${var.regions[0].code}${var.random_string}"
  location = var.regions[0].name
  tags     = merge(var.tags, local.tags)

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Log Analytics Workspace where diagnostic logs and metrics for the resources deployed in this workload will be sent to
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  depends_on = [
    azurerm_resource_group.rg_power_platform_resources
  ]

  name                = "lawpp${var.regions[0].code}${var.random_string}"
  location            = var.regions[0].name
  resource_group_name = azurerm_resource_group.rg_power_platform_resources.name
  tags                = merge(var.tags, local.tags)

  sku               = "PerGB2018"
  retention_in_days = 30

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create storage accounts in each of the Power Platform regions supported by the environment's location
##
module "storage_account_flow_logs" {

  depends_on = [
    azurerm_resource_group.rg_power_platform_resources,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  for_each = {
    for idx, region in var.regions : idx => region
  }

  source              = "../../../../modules/storage-account"
  purpose             = "flv"
  random_string       = var.random_string
  region              = each.value.name
  region_code         = each.value.code
  resource_group_name = azurerm_resource_group.rg_power_platform_resources.name
  tags                = merge(var.tags, local.tags)

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]
  law_resource_id                 = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
}

## Create workload virtual networks that will have subnets delegated to Power Platform
## in each region supported by the Power Platform environment location
module "workload_vnet" {

  depends_on = [
    azurerm_resource_group.rg_power_platform_resources,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    module.storage_account_flow_logs
  ]

  for_each = {
    for idx, region in var.regions : idx => region
  }

  source                              = "../../../../modules/vnet-workload"
  address_space_vnet                  = each.value.cidr
  dns_servers                         = var.dns_servers
  firewall_private_ip                 = var.firewall_private_ip
  log_analytics_workspace_guid        = azurerm_log_analytics_workspace.log_analytics_workspace_workload.workspace_id
  log_analytics_workspace_region      = var.regions[0].name
  log_analytics_workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  region                              = each.value.name
  region_code                         = each.value.code
  network_watcher_name                = "NetworkWatcher_${each.value.name}"
  network_watcher_resource_group_name = var.network_watcher_resource_group_name
  random_string                       = var.random_string
  resource_group_id                   = azurerm_resource_group.rg_power_platform_resources.id
  resource_group_name                 = azurerm_resource_group.rg_power_platform_resources.name
  resource_group_name_transit         = var.resource_group_name_transit
  resource_group_name_shared_services = var.resource_group_name_shared_services
  storage_account_id_flow_logs        = module.storage_account_flow_logs[each.key].id
  tags                                = merge(var.tags, local.tags)
  vnet_id_transit                     = var.vnet_id_transit
  vnet_name_transit                   = var.vnet_name_transit
  workload_number                     = var.workload_number + each.key
}

########## Delegate a subnet in each workload virtual network to Microsoft.PowerPlatform/enterprisePolicies
########## 
##########

## Delegate the app subnets to Microsoft.PowerPlatform/enterprisePolicies
##
resource "azapi_update_resource" "delegate_subnet_to_power_platform" {

  depends_on = [
    module.workload_vnet
  ]

  for_each = {
    for idx, region in var.regions : idx => region
  }

  type        = "Microsoft.Network/virtualNetworks/subnets@2025-09-01"
  resource_id = module.workload_vnet[each.key].subnet_id_app

  body = {
    properties = {
      delegations = [
        {
          name = "Microsoft.PowerPlatform/enterprisePolicies"
          properties = {
            serviceName = "Microsoft.PowerPlatform/enterprisePolicies"
            actions = [
              "Microsoft.Network/virtualNetworks/subnets/join/action"
            ]
          }
        }
      ]
    }
  }
}