########## Create worklaod virtual network, subnets, route tables, and network security groups
########## 

## Create virtual network for workload
##
resource "azurerm_virtual_network" "vnet_workload" {
  name                = "vnetwl${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  address_space = [
    var.address_space_vnet
  ]
  dns_servers = var.dns_servers

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the virtual network
##
resource "azurerm_monitor_diagnostic_setting" "diag_vnet_workload" {
  name                       = "diag"
  target_resource_id         = azurerm_virtual_network.vnet_workload.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "VMProtectionAlerts"
  }
}

## Create the virtual network flow logs and enable traffic analytics
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "flwl${var.workload_number}${var.region_code}${var.random_string}"
  network_watcher_name = var.network_watcher_name
  resource_group_name  = var.network_watcher_resource_group_name

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet_workload.id

  # Enable VNet Flow Logs and use version 2
  enabled = true
  version = 2

  # Send the flow logs to a storage account and retain them for 7 days
  storage_account_id = var.storage_account_id_flow_logs
  retention_policy {
    enabled = true
    days    = 7
  }

  # Send the flow logs to Traffic Analytics and send every 10 minutes
  traffic_analytics {
    enabled               = true
    workspace_id          = var.log_analytics_workspace_guid
    workspace_region      = var.log_analytics_workspace_region
    workspace_resource_id = var.log_analytics_workspace_resource_id
    interval_in_minutes   = 10
  }


  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create subnet for Application Gateway
##
resource "azurerm_subnet" "subnet_app_gateway" {
  name                 = "snet-agw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 0)
  ]

  private_endpoint_network_policies = "Enabled"
}

## Create subnet for used for Azure Machine Learning injected compute
##
resource "azurerm_subnet" "subnet_amlcpt" {
  name                 = "snet-amlcpt"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 1)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet for API Management
##
resource "azurerm_subnet" "subnet_apim" {
  name                 = "snet-apim"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 2)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet for application tier
##
resource "azurerm_subnet" "subnet_app" {
  name                 = "snet-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 3)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet for data tier
##
resource "azurerm_subnet" "subnet_data" {
  name                 = "snet-data"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 4)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet for management components
##
resource "azurerm_subnet" "subnet_mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 5)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet for supporting services
##
resource "azurerm_subnet" "subnet_svc" {
  name                 = "snet-svc"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 6)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create subnet that is used for virtual network integration
##
resource "azurerm_subnet" "subnet_vint" {
  name                 = "snet-vint"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_workload.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 7)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Peer the virtual network with the transit virtual network
##
resource "azurerm_virtual_network_peering" "vnet_peering_to_transit" {
  name                         = "peer-${azurerm_virtual_network.vnet_workload.name}-to-${var.vnet_name_transit}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet_workload.name
  remote_virtual_network_id    = var.vnet_id_transit
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_to_spoke" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_transit
  ]

  name                         = "peer-${var.vnet_name_transit}-to-${azurerm_virtual_network.vnet_workload.name}"
  resource_group_name          = var.resource_group_name_transit
  virtual_network_name         = var.vnet_name_transit
  remote_virtual_network_id    = azurerm_virtual_network.vnet_workload.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

##### Create the route tables and associate them with the subnets
#####

## Create route table for Application Gateway. This assumes the application gateway will not be a private Application Gateway
##
resource "azurerm_route_table" "route_table_app_gateway" {
  name                = "rtagw${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name           = "udr-default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  route {
    name                   = "udr-rfc1918-1"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  route {
    name                   = "udr-rfc1918-2"
    address_prefix         = "172.16.0.0/12"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  route {
    name                   = "udr-rfc1918-3"
    address_prefix         = "192.168.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for Azure Machine Learning injected compute
##
resource "azurerm_route_table" "route_table_amlcpt" {
  name                = "rtamlcpt${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for API Management
##
resource "azurerm_route_table" "route_table_apim" {
  name                = "rtapim${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  route {
    name                   = "udr-api-management"
    address_prefix         = "ApiManagement"
    next_hop_type          = "Internet"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for management tier
##
resource "azurerm_route_table" "route_table_mgmt" {
  name                = "rtmgmt${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for application tier
##
resource "azurerm_route_table" "route_table_app" {
  name                = "rtapp${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for data tier
##
resource "azurerm_route_table" "route_table_data" {
  name                = "rtdata${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create route table for virtual network integration
##
resource "azurerm_route_table" "route_table_vint" {
  name                = "rtvint${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Associate the route table to the Application Gateway subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_app_gateway" {
  depends_on = [
    azurerm_subnet.subnet_app_gateway,
    azurerm_route_table.route_table_app_gateway
  ]

  subnet_id      = azurerm_subnet.subnet_app_gateway.id
  route_table_id = azurerm_route_table.route_table_app_gateway.id
}

## Associate the route table to the Azure Machine Learning injected compute subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_amlcpt" {
  depends_on = [
    azurerm_subnet.subnet_amlcpt,
    azurerm_route_table.route_table_amlcpt,
    azurerm_subnet_route_table_association.route_table_association_app_gateway
  ]

  subnet_id      = azurerm_subnet.subnet_amlcpt.id
  route_table_id = azurerm_route_table.route_table_amlcpt.id
}

## Associate the route table to the API Management subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_apim" {
  depends_on = [
    azurerm_subnet.subnet_apim,
    azurerm_route_table.route_table_apim,
    azurerm_subnet_route_table_association.route_table_association_amlcpt
  ]

  subnet_id      = azurerm_subnet.subnet_apim.id
  route_table_id = azurerm_route_table.route_table_apim.id
}

## Associate the route table to the management tier subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_mgmt" {
  depends_on = [
    azurerm_subnet.subnet_mgmt,
    azurerm_route_table.route_table_mgmt,
    azurerm_subnet_route_table_association.route_table_association_apim
  ]

  subnet_id      = azurerm_subnet.subnet_mgmt.id
  route_table_id = azurerm_route_table.route_table_mgmt.id
}

## Associate the route table to the application tier subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    azurerm_route_table.route_table_app,
    azurerm_subnet_route_table_association.route_table_association_mgmt
  ]

  subnet_id      = azurerm_subnet.subnet_app.id
  route_table_id = azurerm_route_table.route_table_app.id
}

## Associate the route table to the data tier subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_data" {
  depends_on = [
    azurerm_subnet.subnet_data,
    azurerm_route_table.route_table_data,
    azurerm_subnet_route_table_association.route_table_association_app
  ]

  subnet_id      = azurerm_subnet.subnet_data.id
  route_table_id = azurerm_route_table.route_table_data.id
}

## Associate the route table to the virtual network integration subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_vint" {
  depends_on = [
    azurerm_subnet.subnet_vint,
    azurerm_route_table.route_table_vint,
    azurerm_subnet_route_table_association.route_table_association_data
  ]

  subnet_id      = azurerm_subnet.subnet_vint.id
  route_table_id = azurerm_route_table.route_table_vint.id
}

##### Create the network security groups
#####

## Create the network security group for Application Gateway subnet
##
resource "azurerm_network_security_group" "nsg_app_gateway" {
  name                = "nsgagw${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  security_rule {
      name                       = "AllowHttpInboundFromInternet"
      description                = "Allow inbound HTTP to Application Gateway Internet"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 80
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
  }

  security_rule {
      name                       = "AllowHttpsInboundFromInternet"
      description                = "Allow inbound HTTPS to Application Gateway Internet"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
  }

  security_rule {
      name                       = "AllowHttpHttpsInboundFromIntranet"
      description                = "Allow inbound HTTP/HTTPS to Application Gateway from Intranet"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = [80, 443]
      source_address_prefixes    = [
        "192.168.0.0/16",
        "172.16.0.0/12",
        "10.0.0.0/8"
      ]
      destination_address_prefix = "*"
  }

  security_rule {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow inbound Application Gateway Manager Traffic"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "65200-65535"
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
  }

  security_rule {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound traffic from Azure Load Balancer to support probes"
      priority                   = 1040
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for Azure Machine Learning injected compute
##
resource "azurerm_network_security_group" "nsg_amlcpt" {
  name                = "nsgamlcpt${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for API Management
##
resource "azurerm_network_security_group" "nsg_apim" {
  name                = "nsgapim${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  security_rule {
      name                   = "AllowHttpsInboundFromRfc1918"
      description            = "Allow inbound HTTP from RFC1918"
      priority               = 1000
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      source_port_range      = "*"
      destination_port_range = 443
      source_address_prefixes = [
        "192.168.0.0/16",
        "172.16.0.0/12",
        "10.0.0.0/8"
      ]
      destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
      name                       = "AllowApiManagementManagerService"
      description                = "Allow inbound management of API Management instancest"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 3443
      source_address_prefix      = "ApiManagement"
      destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
          name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound traffic from Azure Load Balancer to support probes"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 6390
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
          name                       = "AllowApiManagementSyncCachePolicies"
      description                = "Allow instances within API Management Service to sync cache policies"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = 4290
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
          name              = "AllowApiManagementSyncRateLimits"
      description       = "Allow instances within API Management Service to sync rate limits"
      priority          = 1040
      direction         = "Inbound"
      access            = "Allow"
      protocol          = "Tcp"
      source_port_range = "*"
      destination_port_ranges = [
        "6380",
        "6381-6383"
      ]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
      name                       = "DenyAllInbound"
      description                = "Deny all inbound traffic"
      priority                   = 2000
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for management resources
##
resource "azurerm_network_security_group" "nsg_mgmt" {
  name                = "nsgmgmt${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for the application tier
##
resource "azurerm_network_security_group" "nsg_app" {
  name                = "nsgapp${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for the data tier
##
resource "azurerm_network_security_group" "nsg_data" {
  name                = "nsgdata${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for supporting services
##
resource "azurerm_network_security_group" "nsg_svc" {
  name                = "nsgsvc${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the network security group for the subnet that will be used for VNet integration
##
resource "azurerm_network_security_group" "nsg_vint" {
  name                = "nsgvint${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Associate the network security group with the Application Gateway subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app_gateway" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_vint,
    azurerm_subnet.subnet_app_gateway,
    azurerm_network_security_group.nsg_app_gateway
  ]

  subnet_id                 = azurerm_subnet.subnet_app_gateway.id
  network_security_group_id = azurerm_network_security_group.nsg_app_gateway.id
}

## Associate the network security group with the subnet that will be used for Azure Machine Learning injected compute
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_amlcpt" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_app_gateway,
    azurerm_subnet.subnet_amlcpt,
    azurerm_network_security_group.nsg_amlcpt,
  ]

  subnet_id                 = azurerm_subnet.subnet_amlcpt.id
  network_security_group_id = azurerm_network_security_group.nsg_amlcpt.id
}

## Associate the network security group with the subnet that will be used for API Management
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_apim" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_amlcpt,
    azurerm_subnet.subnet_apim,
    azurerm_network_security_group.nsg_apim
  ]

  subnet_id                 = azurerm_subnet.subnet_apim.id
  network_security_group_id = azurerm_network_security_group.nsg_apim.id
}

## Associate the network security group with the subnet that will be used for management resources
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_mgmt" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_apim,
    azurerm_subnet.subnet_mgmt,
    azurerm_network_security_group.nsg_mgmt
  ]

  subnet_id                 = azurerm_subnet.subnet_mgmt.id
  network_security_group_id = azurerm_network_security_group.nsg_mgmt.id
}

## Associate the network security group with the subnet that will be used for the application tier
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_mgmt,
    azurerm_subnet.subnet_app,
    azurerm_network_security_group.nsg_app
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = azurerm_network_security_group.nsg_app.id
}

## Associate the network security group with the subnet that will be used for the data tier
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_data" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_app,
    azurerm_subnet.subnet_data,
    azurerm_network_security_group.nsg_data
  ]

  subnet_id                 = azurerm_subnet.subnet_data.id
  network_security_group_id = azurerm_network_security_group.nsg_data.id
}

## Associate the network security group with the subnet that will be used for supporting services
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_data,
    azurerm_subnet.subnet_svc,
    azurerm_network_security_group.nsg_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = azurerm_network_security_group.nsg_svc.id
}

## Associate the network security group with the subnet that will be used for VNet integration
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_vint" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    azurerm_subnet.subnet_vint,
    azurerm_network_security_group.nsg_vint
  ]

  subnet_id                 = azurerm_subnet.subnet_vint.id
  network_security_group_id = azurerm_network_security_group.nsg_vint.id
}

##### Create managed identity, Key Vault, and Private Endpoint for Key Vault
#####

## Create a user-assigned managed identity that can be used with any deployed workload
##
resource "azurerm_user_assigned_identity" "umi" {
  location            = var.region
  name                = "umiwl${var.workload_number}${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create an Azure Key Vault which will be used to store secrets, keys, and certificates for the workload
##
resource "azurerm_key_vault" "key_vault_workload" {
  depends_on = [ 
    azurerm_user_assigned_identity.umi
   ]

  name                = "kv${var.workload_number}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  rbac_authorization_enabled = true

  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Deny"
    bypass         = "None"
    ip_rules       = []
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for workload Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_workload" {
  depends_on = [ 
    azurerm_key_vault.key_vault_workload
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_workload.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create role assignment granting user-assigned managed identity access to Key Vault
##
resource "azurerm_role_assignment" "role_assignment_key_vault_workload_kv_umi" {
  depends_on = [ 
    azurerm_monitor_diagnostic_setting.diag_key_vault_workload
  ]
  name                 = uuidv5("dns", "${azurerm_key_vault.key_vault_workload.name}${azurerm_user_assigned_identity.umi.principal_id}")
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.key_vault_workload.name}"
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.umi.principal_id
}

## Create a Private Endpoint for the workload Key Vault
##
resource "azurerm_private_endpoint" "pe_key_vault_workload" {
  depends_on = [ 
    azurerm_key_vault.key_vault_workload
   ]

  name                = "pe${azurerm_key_vault.key_vault_workload.name}vaults"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags = var.tags
  subnet_id           = azurerm_subnet.subnet_svc.id

  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_workload.name}vaults"

  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_workload.name}vaults"
    private_connection_resource_id = azurerm_key_vault.key_vault_workload.id
    subresource_names = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azurerm_key_vault.key_vault_workload.name}vaults"
    private_dns_zone_ids = ["/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_shared_services}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}