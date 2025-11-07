########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_frontdoor_pl" {
  name     = "rgfdpl${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Log Analytics Workspace that all resources specific to this workload will
## write configured resource logs and metrics to
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawfdpl${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##########  Create PrivateLink Service resources
##########
##########

## Disable privatelink service network policies on the subnet to ensure the PrivateLink Service
## can be created
resource "null_resource" "disable_pls_network_policies" {
  # Trigger recreation if the subnet ID changes
  triggers = {
    subnet_id = var.subnet_id_web
  }

  # Disable private link service network policies
  provisioner "local-exec" {
    command = <<-EOT
      az network vnet subnet update \
        --ids ${var.subnet_id_web} \
        --disable-private-link-service-network-policies true
    EOT
  }
}

## Create a standard load balancer that will front the web servers
##
resource "azurerm_lb" "load_balancer_web" {
  depends_on = [
    null_resource.disable_pls_network_policies
  ]

  name                = "lbweb${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name
  tags                = var.tags

  # Create a standard regional load balancer
  sku      = "Standard"
  sku_tier = "Regional"

  frontend_ip_configuration {
    name = local.load_balancer_fe_config_web_name
    zones = [
      "1",
      "2",
      "3"
    ]

    # Internal networking configuration
    subnet_id                     = var.subnet_id_web
    private_ip_address_allocation = "Static"

    # Use the 5th IP address in the internal subnet for the load balancer IP
    private_ip_address = cidrhost(var.subnet_cidr_web, 5)
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the load balancer
##
resource "azurerm_monitor_diagnostic_setting" "diag_load_balancer_web" {
  name                       = "diag-base"
  target_resource_id         = azurerm_lb.load_balancer_web.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "LoadBalancerHealthEvent"
  }
}

## Create the backend pool for the load balancer. Web server VMs will be added to the pool later in the template
##
resource "azurerm_lb_backend_address_pool" "load_balancer_pool_web" {
  depends_on = [
    azurerm_monitor_diagnostic_setting.diag_load_balancer_web
  ]

  name            = "lbpoolweb"
  loadbalancer_id = azurerm_lb.load_balancer_web.id
}

## Create the probe for the web server load balancer
##
resource "azurerm_lb_probe" "load_balancer_probe_web" {
  depends_on = [
    azurerm_lb_backend_address_pool.load_balancer_pool_web
  ]

  name            = "lbpoolweb"
  loadbalancer_id = azurerm_lb.load_balancer_web.id
  protocol        = "Tcp"
  # Web server uses port 8080
  port                = 8080
  interval_in_seconds = 5
  number_of_probes    = 2
}

## Create the load balancer rule to send all traffic to the backend pool
##
resource "azurerm_lb_rule" "load_balancer_rule_web" {
  depends_on = [
    azurerm_lb_probe.load_balancer_probe_web
  ]

  name                           = "lbrulebeweb"
  loadbalancer_id                = azurerm_lb.load_balancer_web.id
  frontend_ip_configuration_name = local.load_balancer_fe_config_web_name
  backend_address_pool_ids = [
    azurerm_lb_backend_address_pool.load_balancer_pool_web.id
  ]
  probe_id                = azurerm_lb_probe.load_balancer_probe_web.id
  protocol                = "Tcp"
  frontend_port           = 80
  backend_port            = 8080
  floating_ip_enabled     = false
  idle_timeout_in_minutes = 4
  load_distribution       = "Default"
  disable_outbound_snat   = true
}

## Create the PrivateLink Service
##
resource "azurerm_private_link_service" "pls_web" {
  depends_on = [
    azurerm_lb_rule.load_balancer_rule_web
  ]

  name                = "plsweb${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name
  tags                = var.tags

  load_balancer_frontend_ip_configuration_ids = [
    azurerm_lb.load_balancer_web.frontend_ip_configuration[0].id
  ]

  # This is used for multi-tenant purposes and tells you the source tenant
  # It requires additional processing of the header per the instructions in this link
  # https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/service/private-link
  enable_proxy_protocol = false

  # Uncomment this to make it visible only within the current subscription
  visibility_subscription_ids = [
    "*"
  ]

  # Make this auto-approved only for the current subscription
  auto_approval_subscription_ids = [
    data.azurerm_subscription.current.subscription_id
  ]

  # This single NAT IP configuration can handle 64000 TCP Ports per backend VM
  nat_ip_configuration {
    name                       = "primary"
    subnet_id                  = var.subnet_id_web
    private_ip_address         = cidrhost(var.subnet_cidr_web, 20)
    private_ip_address_version = "IPv4"
    primary                    = true
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create the Ubuntu virtual machines that will act as web servers running Apache
##########
##########

## Create the network interfaces for the internal NIC of the virtual machine
##
resource "azurerm_network_interface" "nic_web_internal" {
  count = local.vm_count

  name                = "nicwebintvm${count.index + 1}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name
  tags                = var.tags

  # Low end SKUs like D2s_v3 which are likely used for this lab only support one NIC with accelerated networking 
  accelerated_networking_enabled = true

  # IP forwarding is not needed since this is a web server
  ip_forwarding_enabled = false
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id_web
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.subnet_cidr_web, 10 + count.index)
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Associate the web server NICs to the internal load balancer backend pool
##
resource "azurerm_network_interface_backend_address_pool_association" "internal_nic_pool" {
  depends_on = [
    azurerm_lb_backend_address_pool.load_balancer_pool_web
  ]

  count = local.vm_count

  network_interface_id    = azurerm_network_interface.nic_web_internal[count.index].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.load_balancer_pool_web.id
}

## Create the virtual machines that will act as a network virtual appliance (NVA)
##
resource "azurerm_linux_virtual_machine" "vm_web" {
  depends_on = [
    azurerm_network_interface.nic_web_internal,
    azurerm_network_interface_backend_address_pool_association.internal_nic_pool
  ]

  count = local.vm_count

  name                = "vmweb${count.index + 1}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name

  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  size = var.vm_size
  network_interface_ids = [
    azurerm_network_interface.nic_web_internal[count.index].id,
  ]

  # Enable boot diagnostics to allow for console shell access if needed using Microsoft-managed storage account
  boot_diagnostics {
  }

  # Configure the machine with a system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "mdosvmweb${count.index + 1}${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 100
    caching              = "ReadWrite"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Use the custom script extension to bootstrap the Ubuntu machine as a simple web server running Apache
## on port 8080
resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_linux_virtual_machine.vm_web
  ]

  count = local.vm_count

  virtual_machine_id = azurerm_linux_virtual_machine.vm_web[count.index].id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  # Provision a simple web server running apache with a hello world page with the hostname of the machine and mysql server (doesn't do anything really)
  settings = jsonencode({
    commandToExecute = <<-EOT
      /bin/bash -c "echo '${replace(base64encode(file("${path.module}/../../scripts/bootstrap-ubuntu-web.sh")), "'", "'\\''")}' | base64 -d > /tmp/bootstrap-ubuntu-web.sh && \
      chmod +x /tmp/bootstrap-ubuntu-web.sh && \
      /bin/bash /tmp/bootstrap-ubuntu-web.sh"
    EOT
  })

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create the Azure FrontDoor instance
##########
##########

## Create the FrontDoor profile that establishes the SKU
##
resource "azurerm_cdn_frontdoor_profile" "front_door_profile" {
  name                = "fdplprofile${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name

  # Configure FrontDoor Premium SKU
  sku_name = "Premium_AzureFrontDoor"

  # Set timeout for FrontDoor to respond
  response_timeout_seconds = 120

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Azure FrontDoor instance
##
resource "azurerm_monitor_diagnostic_setting" "diag_front_door_profile" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_cdn_frontdoor_profile.front_door_profile.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }
}

## Create the FrontDoor endpoint which establishes the default FQDN of the instance
##
resource "azurerm_cdn_frontdoor_endpoint" "front_door_endpoint" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile
  ]

  name = "fdplendpoint${var.region_code}${var.random_string}"
  tags = var.tags

  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door_profile.id
  enabled                  = true

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a FrontDoor origin group which establishes the load balancing
## properties and health probe for the backends
resource "azurerm_cdn_frontdoor_origin_group" "front_door_origin_group" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile
  ]

  name                     = "fdplorgroup${var.region_code}${var.random_string}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door_profile.id

  # Disable session affinity since this is a stateless web server
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 2
  }

  # Configure a health probe to do a simple GET
  health_probe {
    protocol            = "Http"
    interval_in_seconds = 30
    request_type        = "HEAD"
    path                = "/"
  }
}

## Create the FrontDoor origin which points to the PrivateLink Service
## and establishes the http/https ports
resource "azurerm_cdn_frontdoor_origin" "front_door_origin" {
  depends_on = [
    azurerm_cdn_frontdoor_origin_group.front_door_origin_group,
    azurerm_private_link_service.pls_web
  ]

  name                          = "fdplorgroup${var.region_code}${var.random_string}"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.front_door_origin_group.id

  # Enable this origin
  enabled = true

  # Disable certificate name checks on the backend
  certificate_name_check_enabled = true

  # Configure specifics of origin
  host_name          = "www.jogcloud.com"
  origin_host_header = "www.jogcloud.com"
  http_port          = 80
  https_port         = 443
  priority           = 1
  weight             = 100

  # PrivateLink Service settings of backend
  private_link {
    request_message        = "Approve this fool!"
    location               = var.region
    private_link_target_id = azurerm_private_link_service.pls_web.id
  }
}

## Create a FrontDoor rule set which will hold the routing rules
##
resource "azurerm_cdn_frontdoor_rule_set" "front_door_rule_set" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile
  ]

  name                     = "fdplruleset${var.region_code}${var.random_string}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door_profile.id
}

## Create a FrontDoor rule
##
resource "azurerm_cdn_frontdoor_rule" "front_door_rule" {
  depends_on = [
    azurerm_cdn_frontdoor_origin.front_door_origin,
    azurerm_cdn_frontdoor_origin_group.front_door_origin_group,
    azurerm_cdn_frontdoor_rule_set.front_door_rule_set
  ]

  name                      = "fdplrule${var.region_code}${var.random_string}"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.front_door_rule_set.id
  order                     = 1

  behavior_on_match = "Continue"

  # Add a pointless action because Terraform azurerm provider has a bug with an empty actions when creating the routing rule
  actions {
    request_header_action {
      header_action = "Append"
      header_name   = "X-Passthrough-Rule"
      value         = "true"
    }
  }

}

resource "azurerm_cdn_frontdoor_firewall_policy" "front_door_waf_policy" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile
  ]

  name                = "fdplwafpolicy${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_frontdoor_pl.name

  # Configure the SKU for the WAF policy
  sku_name = azurerm_cdn_frontdoor_profile.front_door_profile.sku_name

  # Set to Prevention mode to block requests that match rules
  mode = "Prevention"

  # Create a custom rule to allow the trusted IP address
  custom_rule {
    name     = "AllowTrustedIp"
    enabled  = true
    action   = "Allow"
    priority = 1
    type     = "MatchRule"
    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values = [
        var.trusted_ip
      ]
    }
  }

  custom_rule {
    name     = "BlockAllOthers"
    enabled  = true
    action   = "Block"
    priority = 2
    type     = "MatchRule"
    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = true
      match_values = [
        var.trusted_ip
      ]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "front_door_security_policy" {
  depends_on = [
    azurerm_cdn_frontdoor_profile.front_door_profile,
    azurerm_cdn_frontdoor_firewall_policy.front_door_waf_policy
  ]

  name                     = "fdplsecpolicy${var.region_code}${var.random_string}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.front_door_profile.id

  # Associate the WAF policy created earlier
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.front_door_waf_policy.id
      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.front_door_endpoint.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_cdn_frontdoor_route" "front_door_route" {
  depends_on = [
    azurerm_cdn_frontdoor_endpoint.front_door_endpoint,
    azurerm_cdn_frontdoor_origin.front_door_origin,
    azurerm_cdn_frontdoor_origin_group.front_door_origin_group,
    azurerm_cdn_frontdoor_rule_set.front_door_rule_set,
    azurerm_cdn_frontdoor_security_policy.front_door_security_policy
  ]

  name                          = "fdplroute${var.region_code}${var.random_string}"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.front_door_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.front_door_origin_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.front_door_origin.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.front_door_rule_set.id]

  # Enable the FrontDoor route
  enabled = true

  forwarding_protocol    = "HttpOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http","Https"]
}
