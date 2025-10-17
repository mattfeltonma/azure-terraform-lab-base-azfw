########## Create transit virtual network and supporting resources
########## 

## Create transit virtual network
##
resource "azurerm_virtual_network" "vnet_transit" {
  name                = "vnettrs${var.region_code}${var.random_string}"
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

## Create diagnostic settings for the virtual network to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_vnet_transit" {
  name                       = "diag"
  target_resource_id         = azurerm_virtual_network.vnet_transit.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "VMProtectionAlerts"
  }
}

## Create the virtual network flow logs and enable traffic analytics
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "fltrs${var.region_code}${var.random_string}"
  network_watcher_name = var.network_watcher_name
  resource_group_name  = var.network_watcher_resource_group_name

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet_transit.id

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

## Create the GatewaySubnet
##
resource "azurerm_subnet" "subnet_gateway" {
  depends_on = [
    azurerm_network_watcher_flow_log.vnet_flow_log,
    azurerm_virtual_network.vnet_transit
  ]

  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_transit.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 0)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create the AzureFirewallSubnet
##
resource "azurerm_subnet" "subnet_firewall" {
  depends_on = [
    azurerm_subnet.subnet_gateway
  ]

  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_transit.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 1)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create the route table for the GatewaySubnet
##
resource "azurerm_route_table" "rt_gateway" {
  name                = "rtgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = true

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the route table for the AzureFirewallSubnet
##
resource "azurerm_route_table" "rt_azfw" {
  name                = "rtfw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = true

  route {
    name                   = "udr-default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "Internet"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Associate the route table to the GatewaySubnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_gateway" {
  depends_on = [
    azurerm_virtual_network_gateway.vgw_vpn
  ]
  subnet_id      = azurerm_subnet.subnet_gateway.id
  route_table_id = azurerm_route_table.rt_gateway.id
}

## Associate the route table to the AzureFirewallSubnet
##
resource "azurerm_subnet_route_table_association" "route_table_association_azfw" {
  depends_on = [
    azurerm_firewall.azure_firewall,
    azurerm_subnet_route_table_association.route_table_association_gateway
  ]
  subnet_id      = azurerm_subnet.subnet_firewall.id
  route_table_id = azurerm_route_table.rt_azfw.id
}

########## Create VPN Gateway
##########

## Create the public IPs for the VPN Gateways
##
resource "azurerm_public_ip" "pip_vpn_gateway" {
  count = 2

  name                = "pipvpn${count.index + 1}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  # As of 9/2025 public IPs are deployed as zone redundant by default even if you don't specify zones
  # https://azure.microsoft.com/en-us/blog/azure-public-ips-are-now-zone-redundant-by-default/

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Enable diagnostic settings for the public IPs used by the VPN Gateways
##
resource "azurerm_monitor_diagnostic_setting" "diag_pip_vpn_gateway" {
  depends_on = [
    azurerm_public_ip.pip_vpn_gateway
  ]

  count = length(azurerm_public_ip.pip_vpn_gateway)

  name                       = "diag-base"
  target_resource_id         = azurerm_public_ip.pip_vpn_gateway[count.index].id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "DDoSProtectionNotifications"
  }
  enabled_log {
    category = "DDoSMitigationFlowLogs"
  }
  enabled_log {
    category = "DDoSMitigationReports"
  }
}

## Create the VPN Gateway
##
resource "azurerm_virtual_network_gateway" "vgw_vpn" {
  depends_on = [
    azurerm_public_ip.pip_vpn_gateway
  ]

  name                = "vngvpn${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1"

  active_active = true
  enable_bgp    = true

  ip_configuration {
    name                          = "ipconfig-1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_vpn_gateway[0].id
    subnet_id                     = azurerm_subnet.subnet_gateway.id
  }

  ip_configuration {
    name                          = "ipconfig-2"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_vpn_gateway[1].id
    subnet_id                     = azurerm_subnet.subnet_gateway.id
  }

  bgp_settings {
    asn = 65515
    peering_addresses {
      ip_configuration_name = "ipconfig-1"
    }

  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the virtual network gateway
##
resource "azurerm_monitor_diagnostic_setting" "diag_vng_vpn_gateway" {
  name                       = "diag-base"
  target_resource_id         = azurerm_virtual_network_gateway.vgw_vpn.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category = "GatewayDiagnosticLog"
  }
  enabled_log {
    category = "IKEDiagnosticLog"
  }
  enabled_log {
    category = "P2SDiagnosticLog"
  }
  enabled_log {
    category = "RouteDiagnosticLog"
  }
  enabled_log {
    category = "TunnelDiagnosticLog"
  }
}

########## Create Azure Firewall and supporting resources
##########

## Create IP Groups for on-premises, Azure, and RFC1918 address spaces
##
resource "azurerm_ip_group" "ip_group_on_prem" {
  name                = "igonprem${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  cidrs = [
    var.address_space_onpremises
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_ip_group" "ip_group_azure" {
  name                = "igazure${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  cidrs = [
    var.address_space_azure
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_ip_group" "ip_group_rfc1918" {
  name                = "igrfc1918${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  cidrs = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16"
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create IP groups for workload-specific resources including APIM and AML compute
##
resource "azurerm_ip_group" "ip_group_apim" {
  name                = "igapim${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  cidrs = var.address_space_apim

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_ip_group" "ip_group_amlcpt" {
  name                = "igamlcpt${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name

  cidrs = var.address_space_amlcpt

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Azure Firewall Policy and Rule Collections
##
resource "azurerm_firewall_policy" "firewall_policy" {
  name                = "fpazfw${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.region

  sku = var.firewall_sku_tier

  dns {
    proxy_enabled = true
    servers       = var.dns_servers
  }

  insights {
    enabled                            = true
    default_log_analytics_workspace_id = var.log_analytics_workspace_resource_id
    retention_in_days                  = 30

    log_analytics_workspace {
      id                = var.log_analytics_workspace_resource_id
      firewall_location = var.region
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "rule_collection_group_enterprise" {
  depends_on = [
    azurerm_firewall_policy.firewall_policy,
    azurerm_ip_group.ip_group_azure,
    azurerm_ip_group.ip_group_on_prem,
    azurerm_ip_group.ip_group_rfc1918,
    azurerm_ip_group.ip_group_amlcpt,
    azurerm_ip_group.ip_group_apim
  ]
  name               = "MyEnterpriseRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id
  priority           = 500
  network_rule_collection {
    name     = "AllowWindowsVmRequired"
    action   = "Allow"
    priority = 1500
    rule {
      name        = "AllowKmsActivation"
      description = "Allows activation of Windows VMs with Azure KMS Service"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_fqdns = [
        "kms.core.windows.net",
        "azkms.core.windows.net"
      ]
      destination_ports = [
        "1688"
      ]
    }
    rule {
      name        = "AllowNtp"
      description = "Allow machines to communicate with NTP servers"
      protocols = [
        "TCP",
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_fqdns = [
        "time.windows.com"
      ]
      destination_ports = [
        "123"
      ]
    }
  }
  network_rule_collection {
    name     = "AllowLinuxVmRequired"
    action   = "Allow"
    priority = 1501
    rule {
      name        = "AllowNtp"
      description = "Allow machines to communicate with NTP servers"
      protocols = [
        "TCP",
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_fqdns = [
        "ntp.ubuntu.com"
      ]
      destination_ports = [
        "123"
      ]
    }
  }
  network_rule_collection {
    name     = "AllowOnPremisesRemoteAccess"
    action   = "Allow"
    priority = 1502
    rule {
      name        = "AllowOnPremisesRemoteAccess"
      description = "Allow machines on-premises to establish remote connections over RDP and SSH"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_on_prem.id
      ]
      destination_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_ports = [
        "2222",
        "22",
        "3389",
        "3390"
      ]
    }
  }
  network_rule_collection {
    name     = "AllowDns"
    action   = "Allow"
    priority = 1503
    rule {
      name        = "AllowDnsInAzure"
      description = "Allow machines in Azure to communicate with DNS servers"
      protocols = [
        "TCP",
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id,
        azurerm_ip_group.ip_group_on_prem.id
      ]
      destination_addresses = [
        var.private_resolver_inbound_endpoint_subnet_cidr
      ]
      destination_ports = [
        "53"
      ]
    }
  }
  network_rule_collection {
    name     = "AllowAzureToAzure"
    action   = "Allow"
    priority = 1504
    rule {
      name        = "AllowAzureToAzure"
      description = "Allow Azure resources to communicate with each other"
      protocols = [
        "TCP",
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_ports = [
        "*"
      ]
    }
  }
  application_rule_collection {
    name     = "AllowAzureToInternetTraffic"
    action   = "Allow"
    priority = 2500
    rule {
      name        = "AllowAzureResourcesToInternet"
      description = "Allows Azures resources to contact any HTTP or HTTPS endpoint"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_azure.id
      ]
      destination_fqdns = [
        "*"
      ]
    }
  }
  application_rule_collection {
    name     = "AllowOnPremisesToAzure"
    action   = "Allow"
    priority = 2501
    rule {
      name        = "AllowWebTrafficOnPremisesToAzure"
      description = "Allows Azures resources to contact any HTTP or HTTPS endpoint"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_on_prem.id
      ]
      destination_fqdns = [
        "*"
      ]
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "rule_collection_group_workload_apim" {
  depends_on = [
    azurerm_firewall_policy.firewall_policy,
    azurerm_firewall_policy_rule_collection_group.rule_collection_group_enterprise
  ]
  name               = "MyWorkloadApimRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id
  priority           = 400

  network_rule_collection {
    name     = "AllowInternalApimNetworkRules"
    action   = "Allow"
    priority = 1400
    rule {
      name        = "AllowAzureMonitor"
      description = "Allow APIM instance to communicate with Azure Monitor"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "AzureMonitor"
      ]
      destination_ports = [
        "1886",
        "443",
        "12000"
      ]
    }
    rule {
      name        = "AllowAzureStorage"
      description = "Allow APIM instance to communicate with Azure Storage"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "Storage"
      ]
      destination_ports = [
        "443",
        "445"
      ]
    }
    rule {
      name        = "AllowEventHub"
      description = "Allow APIM instance to communicate with Azure Event Hub"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "EventHub"
      ]
      destination_ports = [
        "443",
        "5671-5672"
      ]
    }
    rule {
      name        = "AllowKeyVault"
      description = "Allow APIM instance to communicate with Azure Key Vault"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "AzureKeyVault"
      ]
      destination_ports = [
        "443"
      ]
    }
    rule {
      name        = "AllowSql"
      description = "Allow APIM instance to communicate with Azure SQL"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "Sql"
      ]
      destination_ports = [
        "1433"
      ]
    }
    rule {
      name        = "AllowNtp"
      description = "Allow APIM instance to communicate with NTP servers"
      protocols = [
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "*"
      ]
      destination_ports = [
        "123"
      ]
    }
    rule {
      name        = "AllowDns"
      description = "Allow APIM instance to communicate with DNS servers"
      protocols = [
        "UDP",
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        var.private_resolver_inbound_endpoint_subnet_cidr
      ]
      destination_ports = [
        "53"
      ]
    }
    rule {
      name        = "AllowAzureKmsServers"
      description = "Allow Windows machines to activate with Azure KMS Servers"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "AzurePlatformLKM"
      ]
      destination_ports = [
        "1688"
      ]
    }
    rule {
      name        = "AllowEntraID"
      description = "Allow traffic to Entra ID"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_addresses = [
        "AzureActiveDirectory"
      ]
      destination_ports = [
        "443",
        "80"
      ]
    }
  }
  application_rule_collection {
    name     = "AllowInternalApimAppRules"
    action   = "Allow"
    priority = 2400
    rule {
      name        = "AllowCrlLookups"
      description = "Allows network flows to support CRL checks for APIM instance hosts"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "ocsp.msocsp.com",
        "crl.microsoft.com",
        "mscrl.microsoft.com",
        "ocsp.digicert.com",
        "oneocsp.microsoft.com",
        "issuer.pki.azure.com"
      ]
    }
    rule {
      name        = "AllowPortalDiagnostics"
      description = "Allows network flows to support Azure Portal Diagnostics"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "dc.services.visualstudio.com"
      ]
    }
    rule {
      name        = "AllowMicrosoftDiagnostics"
      description = "Allows network flows to support Microsoft Diagnostics on APIM instance hosts"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "azurewatsonanalysis-prod.core.windows.net",
        "shavamanifestazurecdnprod1.azureedge.net",
        "shavamanifestcdnprod1.azureedge.net",
        "settings-win.data.microsoft.com",
        "v10.events.data.microsoft.com"
      ]
    }
    rule {
      name        = "AllowWindowsUpdate"
      description = "Allows network flows to support Microsoft Updates on APIM instance hosts"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "*.update.microsoft.com",
        "*.ctldl.windowsupdate.com",
        "ctldl.windowsupdate.com",
        "download.windowsupdate.com",
        "fe3.delivery.mp.microsoft.com",
        "go.microsoft.com",
        "msedge.api.cdp.microsoft.com"
      ]
    }
    rule {
      name        = "AllowMicrosoftDefender"
      description = "Allows network flows to support Microsoft Defender on APIM instance hosts"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "wdcp.microsoft.com",
        "wdcpalt.microsoft.com"
      ]
    }
    rule {
      name        = "AllowOtherFlow"
      description = "Allows network flows to support other flows to bootstrap APIM instance hosts"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_apim.id
      ]
      destination_fqdns = [
        "config.edge.skype.com",
        "azureprofiler.trafficmanager.net",
        "clientconfig.passport.net"
      ]
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "rule_collection_group_workload_aml_compute" {
  depends_on = [
    azurerm_firewall_policy.firewall_policy,
    azurerm_firewall_policy_rule_collection_group.rule_collection_ggroup_workload_apim
  ]
  name               = "MyWorkloadAmlComputeRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id
  priority           = 300

  network_rule_collection {
    name     = "AllowAmlComputeNetworkRules"
    action   = "Allow"
    priority = 1300
    rule {
      name        = "AllowEntraId"
      description = "Allow communication to Entra ID"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_addresses = [
        "AzureActiveDirectory"
      ]
      destination_ports = [
        "80",
        "443"
      ]
    }
    rule {
      name        = "AllowMachineLearningTcp"
      description = "Allow AML Compute to communciate with Azure Machine Learning Service over TCP"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_addresses = [
        "AzureMachineLearning"
      ]
      destination_ports = [
        "443",
        "8787",
        "18881"
      ]
    }
    rule {
      name        = "AllowMachineLearningUdp"
      description = "Allow AML Compute to communciate with Azure Machine Learning Service over UDP"
      protocols = [
        "UDP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_addresses = [
        "AzureMachineLearning"
      ]
      destination_ports = [
        "5831"
      ]
    }
    rule {
      name        = "AllowAzureBatchNodeManagement"
      description = "Allow AML Compute to communciate with Azure Batch Node Management"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_addresses = [
        "BatchNodeManagement.${var.region}"
      ]
      destination_ports = [
        "443"
      ]
    }
    rule {
      name        = "AllowAzureStorage"
      description = "Allow AML Compute to communciate with Azure Storage"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_addresses = [
        "Storage.${var.region}"
      ]
      destination_ports = [
        "443"
      ]
    }
    rule {
      name        = "AllowMicrosoftDocker"
      description = "Allows access to docker images provided by Microsoft"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "Frontdoor.FirstParty",
        "MicrosoftContainerRegistry"
      ]
      destination_ports = [
        "443"
      ]
    }
    rule {
      name        = "AllowGlobalEntryAmlStudio"
      description = "Allows storing of images and environments for AutoML"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "AzureFrontDoor.FrontEnd"
      ]
      destination_ports = [
        "443"
      ]
    }
    rule {
      name        = "AllowAzureMonitor"
      description = "Allows communication with Azure Monitor"
      protocols = [
        "TCP"
      ]
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "AzureMonitor"
      ]
      destination_ports = [
        "443"
      ]
    }
  }
  application_rule_collection {
    name     = "AllowAmlComputeApplicationRules"
    action   = "Allow"
    priority = 2300
    rule {
      name        = "AllowMicrosoftGraph"
      description = "Allows AML Compute to communicate with Microsoft Graph"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "graph.windows.net"
      ]
    }
    rule {
      name        = "AllowAmlWorkspaces"
      description = "Allows AML Compute to communicate with Azure Machine Learning Services"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "*.instances.azureml.ms"
      ]
    }
    rule {
      name        = "AllowAmlAzureBatch"
      description = "Allows AML Compute to communicate with Azure Batch"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "*.${var.region}.batch.azure.com",
        "*.${var.region}.service.batch.azure.com"
      ]
    }
    rule {
      name        = "AllowAzureStorage"
      description = "Allows AML Compute to communicate with Azure Storage"
      protocols {
        type = "Https"
        port = 443
      }
      source_ip_groups = [
        azurerm_ip_group.ip_group_amlcpt.id
      ]
      destination_fqdns = [
        "*.blob.core.windows.net",
        "*.queue.core.windows.net",
        "*.table.core.windows.net"
      ]
    }
  }
}


## Create Public IP for Azure Firewall
##
resource "azurerm_public_ip" "pip_azure_firewall" {
  name                = "pipfw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  # As of 9/2025 public IPs are deployed as zone redundant by default even if you don't specify zones
  # https://azure.microsoft.com/en-us/blog/azure-public-ips-are-now-zone-redundant-by-default/

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the Azure Firewall instance
##
resource "azurerm_firewall" "azure_firewall" {
  depends_on = [
    azurerm_firewall_policy.firewall_policy,
    azurerm_firewall_policy_rule_collection_group.rule_collection_group_enterprise,
    azurerm_firewall_policy_rule_collection_group.rule_collection_group_workload_apim,
    azurerm_firewall_policy_rule_collection_group.rule_collection_group_workload_aml_compute,
    azurerm_public_ip.pip_azure_firewall
  ]

  name                = "azfw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name


  sku_name           = "AZFW_VNet"
  sku_tier           = var.firewall_sku_tier
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id

  ip_configuration {
    name                 = "fwipconfig"
    subnet_id            = azurerm_subnet.subnet_firewall.id
    public_ip_address_id = azurerm_public_ip.pip_azure_firewall.id
  }

  tags = merge(var.tags, { cycle = "true" })

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_azure_firewall" {
  depends_on = [
    azurerm_firewall.azure_firewall
  ]

  name                           = "diag-base"
  target_resource_id             = azurerm_firewall.azure_firewall.id
  log_analytics_workspace_id     = var.log_analytics_workspace_resource_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }
  enabled_log {
    category = "AZFWApplicationRule"
  }
  enabled_log {
    category = "AZFWNatRule"
  }
  enabled_log {
    category = "AZFWThreatIntel"
  }
  enabled_log {
    category = "AZFWIdpsSignature"
  }
  enabled_log {
    category = "AZFWDnsQuery"
  }
  enabled_log {
    category = "AZFWFqdnResolveFailure"
  }
  enabled_log {
    category = "AZFWApplicationRuleAggregation"
  }
  enabled_log {
    category = "AZFWNetworkRuleAggregation"
  }
  enabled_log {
    category = "AZFWNatRuleAggregation"
  }
}

########## Add user-defined routes to the GatewaySubnet pointing attached spoke virtual networks to Azure Firewall
##########

## Create user-defined route for shared services spoke
##
resource "azurerm_route" "udr_shared_services" {
  depends_on = [
    azurerm_firewall.azure_firewall,
    azurerm_subnet_route_table_association.route_table_association_gateway
  ]

  name                = "udr-ss"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.rt_gateway.name
  address_prefix      = var.vnet_cidr_ss
  next_hop_type       = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.azure_firewall.ip_configuration[0].private_ip_address
}

## Create user-defined routes each workload spoke
##
resource "azurerm_route" "udr_workloads" {
  depends_on = [
    azurerm_firewall.azure_firewall,
    azurerm_subnet_route_table_association.route_table_association_gateway,
    azurerm_route.udr_shared_services
  ]

  count               = length(var.vnet_cidr_wl)

  name                = "udr-wl${count.index + 1}"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.rt_gateway.name
  address_prefix      = var.vnet_cidr_wl[count.index]
  next_hop_type       = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.azure_firewall.ip_configuration[0].private_ip_address
}

########## Configure the transit virtual network to use the Azure Firewall instance as its DNS server
##########

## Set the DNS server settings to the Azure Firewall instance
##
resource "azurerm_virtual_network_dns_servers" "vnet_dns_servers" {
  depends_on = [
    azurerm_virtual_network_gateway.vgw_vpn,
    azurerm_firewall.azure_firewall,
    azurerm_route.udr_shared_services,
    azurerm_route.udr_workloads
  ]

  virtual_network_id = azurerm_virtual_network.vnet_transit.id
  dns_servers        = [
    azurerm_firewall.azure_firewall.ip_configuration[0].private_ip_address
  ]
}


