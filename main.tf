## Create a random string
##
resource "random_string" "unique" {
  length  = 3
  numeric = true
  lower   = true
  upper   = false
  special = false
}

## Create resource groups
##
resource "azurerm_resource_group" "rgtran" {
  for_each = var.environment_details

  name     = "rgtr${local.region_abbreviations[each.value.region_name]}${random_string.unique.result}"
  location = each.value.region_name
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_resource_group" "rgshared" {
  for_each = var.environment_details

  name     = "rgsh${local.region_abbreviations[each.value.region_name]}${random_string.unique.result}"
  location = each.value.region_name
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_resource_group" "rgwork" {
  for_each = var.environment_details

  name     = "rgwl${local.region_abbreviations[each.value.region_name]}${random_string.unique.result}"
  location = each.value.region_name
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Grant the Terraform identity access to Key Vault secrets, certificates, and keys all Key Vaults
##
resource "azurerm_role_assignment" "tf_key_vault_admin" {
  for_each = var.environment_details

  scope                = azurerm_resource_group.rgshared[each.key].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.identity_config.object_id
}

## Create Log Analytics Workspace and DCR rules for Windows and Linux in the primary region and Azure Monitor Data Collection Endpoints 
## for each region
module "law" {
  depends_on = [
    azurerm_resource_group.rgshared
  ]

  source        = "./modules/log-analytics-workspace"
  random_string = random_string.unique.result
  purpose       = "law"
  environments  = {
    for env_key, env_value in var.environment_details :
    env_key => {
      region_name                 = env_value.region_name
      region_code                 = local.region_abbreviations[env_value.region_name]
      region_resource_group_name  = azurerm_resource_group.rgshared[env_key].name
    }
  }
  retention_in_days = 30
  tags = local.tags
}

## Create Storage Accounts for Flow Logs
##
module "storage_account_flow_logs" {
  for_each = var.environment_details

  depends_on = [
    azurerm_resource_group.rgshared,
    module.law
  ]

  source              = "./modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  region              = each.value.region_name
  region_code         = local.region_abbreviations[each.value.region_name]
  resource_group_name = azurerm_resource_group.rgshared[each.key].name
  tags                = local.tags

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]
  law_resource_id                 = module.law.id
}

## Create Transit Virtual Networks (Hub)
##
module "vnet_transit" {
  depends_on = [
    azurerm_resource_group.rgtran,
    module.law,
    module.storage_account_flow_logs
  ]

  # Create a transit virtual network for both primary and secondary regions
  for_each = var.environment_details

  source              = "./modules/vnet-transit"
  random_string       = random_string.unique.result
  region              = each.value.region_name
  region_code         = local.region_abbreviations[each.value.region_name]
  resource_group_name = azurerm_resource_group.rgtran[each.key].name
  tags = local.tags

  # Assign the appropriate CIDR blocks depending on whether the environment is primary or secondary
  address_space_vnet   = each.key == "primary" ? local.vnet_cidr_tr_pri : local.vnet_cidr_tr_sec

  # Carve out the virtual network CIDR block depending on whether the environment is primary or secondary
  subnet_cidr_gateway  = each.key == "primary" ? cidrsubnet(local.vnet_cidr_tr_pri, 3, 0) : cidrsubnet(local.vnet_cidr_tr_sec, 3, 0)
  subnet_cidr_firewall = each.key == "primary" ? cidrsubnet(local.vnet_cidr_tr_pri, 3, 1) : cidrsubnet(local.vnet_cidr_tr_sec, 3, 1)

  # Pass the CIDR block for the Private Resolver Inbound Endpoint subnet which is used in upstream Azure Firewall rules
  private_resolver_inbound_endpoint_subnet_cidr      = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 1) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)

  # Pass the entire CIDR ranges for on-premises and Azure addresses to be used in Azure Firewall rules
  address_space_onpremises = var.address_space_onpremises
  address_space_azure = var.address_space_cloud

  # Pass the CIDR blocks for APIM and AML compute subnets, which are used in Azure Firewall rules
  address_space_apim = each.key == "primary" ? [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 2),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 2)
    ] : [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 2),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 2)
  ]
  address_space_amlcpt = each.key == "primary" ? [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 1),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 1)
    ] : [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 1),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 1)
  ]

  # Pass the CIDR blocks that will be used for the shared services and workload virtual networks. These are used in UDRs in the GatewaySubnet and Azure Firewall rules
  vnet_cidr_ss        = each.key == "primary" ? local.vnet_cidr_ss_pri : local.vnet_cidr_ss_sec
  vnet_cidr_wl = each.key == "primary" ? [
    local.vnet_cidr_wl1_pri,
    local.vnet_cidr_wl2_pri
    ] : [
    local.vnet_cidr_wl1_sec,
    local.vnet_cidr_wl2_sec
  ]

  # Pass the details to enable VNet Flow Logs and Traffic Analytics
  network_watcher_name                = "${var.network_watcher_name_prefix}${each.value.region_name}"
  network_watcher_resource_group_name = var.network_watcher_resource_group_name
  storage_account_id_flow_logs        = module.storage_account_flow_logs[each.key].id
  log_analytics_workspace_guid        = module.law.workspace_id
  log_analytics_workspace_resource_id = module.law.id
  log_analytics_workspace_region      = module.law.location
}

## Create Shared Services Virtual Networks
##
module "vnet_shared" {
  depends_on = [
    azurerm_resource_group.rgshared,
    module.vnet_transit
  ]
  for_each = var.environment_details

  source              = "./modules/vnet-shared"
  random_string       = random_string.unique.result
  region              = each.value.region_name
  region_code         = local.region_abbreviations[each.value.region_name]
  resource_group_name = azurerm_resource_group.rgshared[each.key].name
  resource_group_id = azurerm_resource_group.rgshared[each.key].id
  tags = local.tags

  # Assign the appropriate CIDR blocks depending on whether the environment is primary or secondary
  address_space_vnet   = each.key == "primary" ? local.vnet_cidr_ss_pri : local.vnet_cidr_ss_sec

  # Set the IP address of the Azure Firewall to be as the next hop for route tables
  firewall_private_ip = module.vnet_transit[each.key].azfw_private_ip

  # Pass the entire CIDR ranges for on-premises and Azure addresses to be used in Network Security Group rules
  address_space_azure = var.address_space_cloud
  address_space_onpremises = var.address_space_onpremises

  # Pass the transit virtual network details which are used to create a virtual network peering
  resource_group_name_hub = azurerm_resource_group.rgtran[each.key].name
  vnet_id_transit = module.vnet_transit[each.key].vnet_transit_id
  vnet_name_transit = module.vnet_transit[each.key].vnet_transit_name

  # Set the username and password for the virtual machine to be deployed to the tools subnet
  #
  vm_admin_username = var.vm_admin_username
  vm_admin_password = var.vm_admin_password

  # Pass the details to enable VNet Flow Logs and Traffic Analytics
  network_watcher_name                = "${var.network_watcher_name_prefix}${each.value.region_name}"
  network_watcher_resource_group_name = var.network_watcher_resource_group_name
  storage_account_id_flow_logs        = module.storage_account_flow_logs[each.key].id
  log_analytics_workspace_guid        = module.law.workspace_id
  log_analytics_workspace_resource_id = module.law.id
  log_analytics_workspace_region      = module.law.location
}

##### When multiple environments are defined peer the transit virtual networks and setup cross environment routing
#####

## Peer each transit virtual networks if there are multiple environments defined
##
resource "azurerm_virtual_network_peering" "peer_transit" {
  depends_on = [
    module.vnet_transit,
    module.vnet_shared
  ]
  count = length(var.environment_details) > 1 ? 2 : 0

  name                      = "peer${keys(var.environment_details)[count.index]}to${keys(var.environment_details)[count.index == 0 ? 1 : 0]}"
  resource_group_name       = module.vnet_transit[keys(var.environment_details)[count.index] == "primary" ? "primary" : "secondary"].resource_group_name_transit
  virtual_network_name      = module.vnet_transit[keys(var.environment_details)[count.index] == "primary" ? "primary" : "secondary"].vnet_transit_name
  remote_virtual_network_id = module.vnet_transit[keys(var.environment_details)[count.index] == "primary" ? "secondary" : "primary"].vnet_transit_id
}

## Modify the Azure Firewall route tables in each environment to route traffic to the appropriate firewall in the other environment if there are multiple environments defined
##
resource "azurerm_route" "rt_env_to_env" {
  depends_on = [
    azurerm_virtual_network_peering.peer_transit
  ]
  count = length(var.environment_details) > 1 ? 2 : 0

  name                   = "rt${keys(var.environment_details)[count.index]}to${keys(var.environment_details)[count.index == 0 ? 1 : 0]}"
  resource_group_name    = module.vnet_transit[keys(var.environment_details)[count.index]].resource_group_name_transit
  route_table_name       = module.vnet_transit[keys(var.environment_details)[count.index]].route_table_name_azfw
  address_prefix         = keys(var.environment_details)[count.index] == "primary" ? var.environment_details["secondary"].address_space : var.environment_details["primary"].address_space
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = keys(var.environment_details)[count.index] == "primary" ? module.vnet_transit["secondary"].azfw_private_ip : module.vnet_transit["primary"].azfw_private_ip

}

##### Create Private DNS Zones and link to the shared services virtual network in the primary environment and then modify the DNS firewall settings to point to the inbound resolver
##### If multiple environments are specified create virtual network links to the shared services environment in each region

## Create the Private DNS Zones in the primary Shared Services resource group
##
resource "azurerm_private_dns_zone" "zone" {
  depends_on = [
    module.vnet_shared,
    azurerm_route.rt_env_to_env
   ]

  for_each = local.filtered_private_dns_namespaces_with_regional_zones

  name                = each.value
  resource_group_name = module.vnet_shared["primary"].resource_group_name_shared_services
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Link the Private DNS Zones to the shared services virtual networks in each environment
##
resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  depends_on = [
    azurerm_private_dns_zone.zone,
    module.vnet_shared
  ]

  for_each = local.private_dns_namespaces_env_map

  name                = "${each.value.namespace}-${each.value.environment}-link"
  resource_group_name = module.vnet_shared["primary"].resource_group_name_shared_services
  private_dns_zone_name = each.value.namespace
  virtual_network_id  = module.vnet_shared[each.value.environment].vnet_shared_services_resource_id
  registration_enabled = false
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Update the Azure Firewall DNS settings to point to the Private Resolver Inbound Endpoint IP address
##
resource "null_resource" "update_firewall_dns_policy" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.link
  ]

  for_each = var.environment_details
  
  # Trigger only if Azure Firewall Policy changes or if DNS resolver IP changes
  triggers = {
    firewall_policy_id = module.vnet_transit[each.key].policy_id
    dns_resolver_ip    = module.vnet_shared[each.key].private_resolver_inbound_endpoint_ip
  }
  
  provisioner "local-exec" {
    command = "az network firewall policy update --ids ${module.vnet_transit[each.key].policy_id} --dns-servers ${module.vnet_shared[each.key].private_resolver_inbound_endpoint_ip}"
  }
}

## Update the transit virtual network to use the Private DNS Resolver inbound endpoint IP as the DNS server
##
resource "azurerm_virtual_network_dns_servers" "update_dns_servers_transit" {
  depends_on = [
    null_resource.update_firewall_dns_policy
  ]

  for_each = var.environment_details

  virtual_network_id = module.vnet_transit[each.key].vnet_transit_id
  dns_servers        = [module.vnet_shared["primary"].private_resolver_inbound_endpoint_ip]
}

##### Create workload virtual network
#####
module "vnet_workload" {
  depends_on = [
    null_resource.update_firewall_dns_policy
  ]

  for_each = { for env in local.workload_object : "${env.environment}-${env.workload_number}" => env }

  source              = "./modules/vnet-workload"
  random_string       = random_string.unique.result
  workload_number     = each.value.workload_number
  region              = var.environment_details[each.value.environment].region_name
  region_code         = local.region_abbreviations[var.environment_details[each.value.environment].region_name]
  resource_group_name = azurerm_resource_group.rgwork[each.value.environment].name
  resource_group_id   = azurerm_resource_group.rgwork[each.value.environment].id
  tags = local.tags

  # Set the address space for the virtual network
  address_space_vnet   = each.value.environment == "primary" ? (each.value.workload_number == 1 ? local.vnet_cidr_wl1_pri : local.vnet_cidr_wl2_pri) : (each.value.workload_number == 1 ? local.vnet_cidr_wl1_sec : local.vnet_cidr_wl2_sec)

  # Set the DNS servers to be used in the virtual network
  dns_servers = [
    module.vnet_shared[each.value.environment].private_resolver_inbound_endpoint_ip
  ]

  # Set the firewall IP address that route tables will point to for egress
  firewall_private_ip = module.vnet_transit[each.value.environment].azfw_private_ip

  # Pass the properties of the transit virtual network
  resource_group_name_transit = azurerm_resource_group.rgtran[each.value.environment].name
  vnet_id_transit = module.vnet_transit[each.value.environment].vnet_transit_id
  vnet_name_transit = module.vnet_transit[each.value.environment].vnet_transit_name

  # Pass the properties of the shared services virtual network
  resource_group_name_shared_services = azurerm_resource_group.rgshared["primary"].name

  # Pass the details to enable VNet Flow Logs and Traffic Analytics
  network_watcher_name                = "${var.network_watcher_name_prefix}${var.environment_details[each.value.environment].region_name}"
  network_watcher_resource_group_name = var.network_watcher_resource_group_name
  storage_account_id_flow_logs        = module.storage_account_flow_logs[each.value.environment].id
  log_analytics_workspace_guid        = module.law.workspace_id
  log_analytics_workspace_resource_id = module.law.id
  log_analytics_workspace_region      = module.law.location


}

