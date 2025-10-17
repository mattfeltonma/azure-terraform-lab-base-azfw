########## Create shared virtual network and supporting resources
##########

## Create shared services virtual network
##
resource "azurerm_virtual_network" "vnet_shared" {
  name                = "vnetss${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  address_space = [
    var.address_space_vnet
  ]
  
  # Set virtual network to use wire server since this is the virtual network
  # where all Private DNS Zones and Forwarding Rule Sets will be linked to
  dns_servers = ["168.63.129.16"]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the virtual network to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_vnet_shared" {
  name                       = "diag"
  target_resource_id         = azurerm_virtual_network.vnet_shared.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "VMProtectionAlerts"
  }
}

## Create the virtual network flow logs and enable traffic analytics
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "flss${var.region_code}${var.random_string}"
  network_watcher_name = var.network_watcher_name
  resource_group_name  = var.network_watcher_resource_group_name

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet_shared.id

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

## Create the AzureBastionSubnet
##
resource "azurerm_subnet" "subnet_bastion" {

  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 0)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create the subnet where the Azure Private DNS Resolver inbound endpoint will be deployed
##
resource "azurerm_subnet" "subnet_dnsin" {

  name                 = "snet-dnsin"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 1)
  ]
  private_endpoint_network_policies = "Enabled"

  ## Delegation must be added because redeployment will fail without it.
  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

## Create the subnet where the Azure Private DNS Resolver outbound endpoint will be deployed
##
resource "azurerm_subnet" "subnet_dnsout" {

  name                 = "snet-dnsout"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 2)
  ]
  private_endpoint_network_policies = "Enabled"

  ## Delegation must be added because redeployment will fail without it.
  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

## Create the subnet where supporting services will be deployed
##
resource "azurerm_subnet" "subnet_svc" {

  name                 = "snet-svc"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 3)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create the subnet where virtual machines running tools will be deployed
##
resource "azurerm_subnet" "subnet_tools" {

  name                 = "snet-tools"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 4)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Peer the virtual network with the transit virtual network and vice versa
##
resource "azurerm_virtual_network_peering" "vnet_peering_to_transit" {
  name                         = "peer-${azurerm_virtual_network.vnet_shared.name}${var.region_code}${var.random_string}-to-transit"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet_shared.name
  remote_virtual_network_id    = var.vnet_id_transit
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_to_shared" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_transit
  ]

  name                         = "peer-transit-to-${azurerm_virtual_network.vnet_shared.name}${var.region_code}${var.random_string}"
  resource_group_name          = var.resource_group_name_hub
  virtual_network_name         = local.vnet_name_transit
  remote_virtual_network_id    = azurerm_virtual_network.vnet_shared.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

## Create the route table for the subnet where the Private DNS Resolver inbound endpoint is deployed
##
resource "azurerm_route_table" "rt_dnsin" {
  name                = "rtdnsin${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = true

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

## Create the route table for the subnet where the Private DNS Resolver outbound endpoint is deployed
##
resource "azurerm_route_table" "rt_dnsout" {
  name                = "rtdnsout${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = true

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

## Create the route table for the subnet where virtual machines running tools will be deployed
##
resource "azurerm_route_table" "rt_tools" {
  name                = "rttools${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = true

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

## Associate the route table to the Private DNS Resolver inbound endpoint subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_dnsin" {
  depends_on = [
    azurerm_subnet.subnet_dnsin,
    azurerm_route_table.rt_dnsin,
    azurerm_virtual_network_peering.vnet_peering_to_shared
  ]

  subnet_id      = azurerm_subnet.subnet_dnsin.id
  route_table_id = azurerm_route_table.rt_dnsin.id
}

## Associate the route table to the Private DNS Resolver outbound endpoint subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_dnsout" {
  depends_on = [
    azurerm_subnet.subnet_dnsout,
    azurerm_route_table.rt_dnsout,
    azurerm_subnet_route_table_association.route_table_association_dnsin
  ]

  subnet_id      = azurerm_subnet.subnet_dnsout.id
  route_table_id = azurerm_route_table.rt_dnsout.id
}

## Associate the route table to the tools subnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_tools" {
  depends_on = [
    azurerm_subnet.subnet_tools,
    azurerm_route_table.rt_tools,
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_subnet_route_table_association.route_table_association_dnsout
  ]

  subnet_id      = azurerm_subnet.subnet_tools.id
  route_table_id = azurerm_route_table.rt_tools.id
}

## Create the network security group for the Azure Bastion subnet
##
resource "azurerm_network_security_group" "nsg_bastion" {
  name                = "nsgbastion${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHttpsInbound"
    description                = "Allow inbound HTTPS to allow for connections to Bastion"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    description                = "Allow inbound HTTPS to allow for managemen of Bastion instances"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    description                = "Allow inbound HTTPS to allow Azure Load Balancer health probes"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionHostCommunication"
    description                = "Allow data plane communication between Bastion hosts"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
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

  security_rule {
    name                       = "AllowSshRdpOutbound"
    description                = "Allow Bastion hosts to SSH and RDP to virtual machines"
    priority                   = 1100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [22, 2222, 3389, 3390]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    description                = "Allow Bastion to connect to dependent services in Azure"
    priority                   = 1110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowBastionCommunication"
    description                = "Allow data plane communication between Bastion hosts"
    priority                   = 1120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowHttpOutbound"
    description                = "Allow Bastion to connect to dependent services on the Internet"
    priority                   = 1130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = 80
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "DenyAllOutbound"
    description                = "Deny all outbound traffic"
    priority                   = 2100
    direction                  = "Outbound"
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

  tags = var.tags
}

## Create the network security group for the Private DNS Resolver inbound endpoint subnet
##
resource "azurerm_network_security_group" "nsg_dnsin" {
  name                = "nsgdnsin${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  security_rule {
      name                   = "AllowTcpDnsInbound"
      description            = "Allow inbound DNS traffic"
      priority               = 1000
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "*"
      source_port_range      = "*"
      destination_port_range = 53
      source_address_prefixes = [
        var.address_space_azure,
        var.address_space_onpremises
      ]
      destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

  tags = var.tags
}

## Create the network security group for the Private DNS Resolver outbound endpoint subnet
##
resource "azurerm_network_security_group" "nsg_dnsout" {
  name                = "nsgdnsout${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

  tags = var.tags
}

## Create the network security group for the tools subnet
##
resource "azurerm_network_security_group" "nsg_tools" {
  name                = "nsptools${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

  tags = var.tags
}

## Create the network security group for the supporting services subnet
##
resource "azurerm_network_security_group" "nsg_svc" {
  name                = "nspsvc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

  tags = var.tags
}

## Associate network security group to the Azure Bastion subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_bastion" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_virtual_network_peering.vnet_peering_to_transit,
    azurerm_subnet.subnet_bastion,
    azurerm_network_security_group.nsg_bastion,
    azurerm_subnet_route_table_association.route_table_association_tools
  ]

  subnet_id                 = azurerm_subnet.subnet_bastion.id
  network_security_group_id = azurerm_network_security_group.nsg_bastion.id
}

## Associate network security group to the Private DNS Resolver inbound endpoint subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_dnsin" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_virtual_network_peering.vnet_peering_to_transit,
    azurerm_subnet.subnet_dnsin,
    azurerm_network_security_group.nsg_dnsin,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_dnsin.id
  network_security_group_id = azurerm_network_security_group.nsg_dnsin.id
}

## Associate network security group to the Private DNS Resolver outbound endpoint subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_dnsout" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_virtual_network_peering.vnet_peering_to_transit,
    azurerm_subnet.subnet_dnsout,
    azurerm_network_security_group.nsg_dnsout,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_dnsin
  ]
  subnet_id                 = azurerm_subnet.subnet_dnsout.id
  network_security_group_id = azurerm_network_security_group.nsg_dnsout.id
}

## Associate network security group to the tools subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_tools" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_virtual_network_peering.vnet_peering_to_transit,
    azurerm_subnet.subnet_tools,
    azurerm_network_security_group.nsg_tools,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_dnsout
  ]
  subnet_id                 = azurerm_subnet.subnet_tools.id
  network_security_group_id = azurerm_network_security_group.nsg_tools.id
}

## Associate network security group to the supporting services subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_shared,
    azurerm_virtual_network_peering.vnet_peering_to_transit,
    azurerm_subnet.subnet_svc,
    azurerm_network_security_group.nsg_svc,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_tools
  ]
  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = azurerm_network_security_group.nsg_svc.id
}

########## Create Private DNS Resolver and supporting resources
##########

## Create the Private DNS Resolver
##
resource "azurerm_private_dns_resolver" "resolver" {
  depends_on = [
    azurerm_subnet.subnet_dnsin,
    azurerm_subnet.subnet_dnsout,
    azurerm_subnet_route_table_association.route_table_association_dnsin,
    azurerm_subnet_route_table_association.route_table_association_dnsout,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc
  ]
  name                = "pdnsresolv${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.region
  virtual_network_id  = azurerm_virtual_network.vnet_shared.id
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the Private DNS Resolver inbound endpoint
##
resource "azurerm_private_dns_resolver_inbound_endpoint" "inbound_endpoint" {
  name                    = "dnsrin${var.region_code}${var.random_string}"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = var.region
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.subnet_dnsin.id
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the Private DNS Resolver outbound endpoint
##
resource "azurerm_private_dns_resolver_outbound_endpoint" "outbound_endpoint" {
  depends_on = [ 
    azurerm_private_dns_resolver_inbound_endpoint.inbound_endpoint 
  ]

  name                    = "dnsrout${var.region_code}${var.random_string}"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = var.region
  subnet_id               = azurerm_subnet.subnet_dnsout.id
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the forwarding rule set to forward DNS queries for a specific domain to a specific IP address
##
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "frs" {
  depends_on = [ 
    azurerm_private_dns_resolver_outbound_endpoint.outbound_endpoint 
  ]

  name                    = "dnsfrs${var.region_code}${var.random_string}"
  resource_group_name     = var.resource_group_name
  location               = var.region
  private_dns_resolver_outbound_endpoint_ids = [
    azurerm_private_dns_resolver_outbound_endpoint.outbound_endpoint.id
  ]
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the forwarding rule set to the virtual network link to the shared services virtual network
##
resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_link_frs_shared" {
  depends_on = [ 
    azurerm_private_dns_resolver_dns_forwarding_ruleset.frs
  ]

  name                        = "vnetlinkfrs${azurerm_virtual_network.vnet_shared.name}${var.region_code}${var.random_string}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.frs.id
  virtual_network_id         = azurerm_virtual_network.vnet_shared.id
}

########## Create DNS Security Policy and supporting resources
##########

## Create domain list that can contain domains to alert on
##
resource "azapi_resource" "domain_list_alert" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlalert${var.region_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
      ]
    }
    tags = var.tags
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create domain list that can contain domains to block
##
resource "azapi_resource" "domain_list_blocked" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlblocked${var.region_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
      ]
    }
    tags = var.tags
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create domain list that can contain domains to allow
##
resource "azapi_resource" "domain_list_allow" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlallow${var.region_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
        "."
      ]
    }
    tags = var.tags
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the DNS Security Policy that can be used to log DNS queries and control DNS resolution
##
resource "azapi_resource" "drp_enterprise" {
  depends_on = [ 
    azapi_resource.domain_list_allow,
    azapi_resource.domain_list_blocked,
    azapi_resource.domain_list_alert
   ]

  type                      = "Microsoft.Network/dnsResolverPolicies@2025-05-01"
  name                      = "drpent${var.region_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    tags = var.tags
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the DNS Security Policies to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_dns_security_policy" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.drp_enterprise.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "DnsResponse"
  }
}

## Create the DNS Security Rules to block that can be used to block domains in the domain block list
##
resource "azapi_resource" "drpr_block_malicious" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drprblockmalicious"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 100
      action = {
        actionType = "Block"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_blocked.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

## Create the DNS Security Rules to alert that can be used to alert domains in the domain alert list
##
resource "azapi_resource" "drpr_alert" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drpralert"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 110
      action = {
        actionType = "Alert"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_alert.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

## Create the DNS Security Rules to allow all domains
##
resource "azapi_resource" "drpr_allow_all" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drprallowall"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 120
      action = {
        actionType = "Allow"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_allow.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

## Link the DNS Security Policy to the shared services virtual network
##
resource "azapi_resource" "vnet_link_drp_enterprise" {
  depends_on = [
    azapi_resource.drp_enterprise,
    azapi_resource.drpr_block_malicious,
    azapi_resource.drpr_allow_all,
    azapi_resource.drpr_alert,
    azurerm_private_dns_resolver_virtual_network_link.vnet_link_frs_shared
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/virtualNetworkLinks@2025-05-01"
  name                      = "vnetlink${azapi_resource.drp_enterprise.name}${azurerm_virtual_network.vnet_shared.name}${var.region_code}${var.random_string}"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    properties = {
      virtualNetwork = {
        id = azurerm_virtual_network.vnet_shared.id
      }
    }
    tags = var.tags
  }
}

########## Create Azure Bastion instance and tool server
##########

## Create a public IP address to be used by the Azure Bastion instance which will run in the production transit virtual network
##
resource "azurerm_public_ip" "pip_bastion" {
  name                = "pipbstnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "bstprod${var.region_code}${var.random_string}"
}

## Create an Azure Bastion instance in the production transit virtual network
##
resource "azurerm_bastion_host" "bastion" {
  depends_on = [
    azurerm_public_ip.pip_bastion
  ]

  name                = "bstnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.pip_bastion.id
  }

  # Use basic SKU since a single virtual network
  sku = "Basic"

  tags = var.tags
}

## Create diagnostic settings for the Azure Bastion instance to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_bastion" {
  name                       = "diag-base"
  target_resource_id         = azurerm_bastion_host.bastion.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "BastionAuditLogs"
  }
}

## Create a user-assigned managed identity that can be used to access upstream resources as virtual machine
##
resource "azurerm_user_assigned_identity" "umi" {
  location            = var.region
  name                = "umivmnsp${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

## Create a public IP address to be used by the Azure virtual machine to allow access to the Internet
##
resource "azurerm_public_ip" "pip_vm" {
  name                = "pipvm${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

## Create the virtual network interface for the virtual machine
##
resource "azurerm_network_interface" "nic" {
  name                = "nicvmnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  # Enable accelerated networking on the network interface
  accelerated_networking_enabled = true

  # Configure the IP settings for the network interface
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_tools.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_tools.address_prefixes[0], 20)
    public_ip_address_id          = azurerm_public_ip.pip_vm.id
  }
  tags = var.tags
}

## Create the virtual machine
##
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "vmtool${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  admin_username = var.vm_admin_username
  admin_password = var.vm_admin_password

  size = var.vm_sku_size
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.umi.id]
  }

  # Enable boot diagnostics using Microsoft-managed storage account
  #
  boot_diagnostics {
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "osdiskvmwebnsp${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
    caching              = "ReadWrite"
  }

  tags = merge(var.tags, {
    cycle = "true"
  })
}

## Execute the provisioning script via the custom script extension
##
resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_windows_virtual_machine.vm
  ]

  virtual_machine_id = azurerm_windows_virtual_machine.vm.id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version =  "1.10"
  protected_settings = jsonencode(
    {
      "commandToExecute" : "powershell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(file("${path.module}/../../scripts/bootstrap-windows-tool.ps1"), "UTF-16LE")}"
    }
  )

  # Adjust timeout because provisioning script can take a fair amount of time
  timeouts {
    create = "60m"
    update = "60m"
  }

  tags = var.tags
}

