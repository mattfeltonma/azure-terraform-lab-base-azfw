########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_app_gateway" {
  name     = "rgappgw${var.region_code}${var.random_string}"
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
  name                = "lawappgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name

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

########## Create Network Security Perimeters that will be used to restrict access to resources that support the Application Gateway instance
########## that support the Application Gateway instance
##########

## Create a Network Security Perimeter that will be used to restrict access to resources that support
## the Application Gateway instance
resource "azapi_resource" "nsp_app_gateway_resources" {
  depends_on = [
    azurerm_resource_group.rg_app_gateway,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspappgw${var.region_code}${var.random_string}"
  location  = var.region
  parent_id = azurerm_resource_group.rg_app_gateway.id
  tags      = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_app_gateway_resources" {
  depends_on = [
    azapi_resource.nsp_app_gateway_resources
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_app_gateway_resources.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspIntraPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPrivateInboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterOutboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspOutboundAttempt"
  }
}

## Create a Network Security Perimeter profile that will be associated with the Key Vault instance used
## to store the certificate used for the custom domain name of the Application Gateway.
resource "azapi_resource" "profile_nsp_key_vault_app_gateway" {
  depends_on = [
    azapi_resource.nsp_app_gateway_resources
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pkvappgw"
  location  = var.region
  parent_id = azapi_resource.nsp_app_gateway_resources.id
}

## Create an access rule to allow the Application Gateway service to connect to the Key Vault instance
## to pull the certificate to associate it with the custom domain name of the Application Gateway
resource "azapi_resource" "access_rule_key_vault_app_gateway_sub_id" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_app_gateway
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arkvappgwtrustedsubs"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_key_vault_app_gateway.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      # Allow the subscription containing the Application Gateway to bypass the NSP
      subscriptions = [
        {
          id = data.azurerm_subscription.current.id
        }
      ]
    }
  }
}

## Create an access rule to allow the machine deploying the Terraform resources data plane access to the Key Vault
## Only required for my shitty lab
resource "azapi_resource" "access_rule_key_vault_app_gateway_ipprefix" {
  depends_on = [
    azapi_resource.access_rule_key_vault_app_gateway_sub_id
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arkvappgwtrustedips"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_key_vault_app_gateway.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      # This address prefix exception is only required for this lab
      addressPrefixes = [
        "${var.trusted_ip}/32"
      ]
    }
  }
}

########## Create an Azure Key Vault instance and supporting resources to store the certificate used for the custom domain name
########## for the Application Gateway
##########

## Create an Azure Key Vault instance to store the certificate used for the custom domain name
##
resource "azurerm_key_vault" "key_vault_app_gateway_custom_domain" {
  depends_on = [
    azurerm_resource_group.rg_app_gateway,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "kvappgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name
  # Adding tag specific to my environment. Not needed outside my environment
  # TODO: Remove this tag when NSPs support cross-NSP links which will allow diagnostic
  # logs to be delivered outside the NSP
  tags = merge(var.tags, { SecurityControl = "Ignore" })

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  # Configure vault to support Azure RBAC-based authorization of data-plane
  rbac_authorization_enabled = true

  # Disable purge protection since this is a lab
  purge_protection_enabled = false

  # TODO: 3/2026 This is set to true for now to allow the IP exception that is specific to my environment. Once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  # then this can be set to false and the network_acls section can be removed and instead rely on NSP ruleset.
  public_network_access_enabled = true
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []
    ip_rules = [
      var.trusted_ip
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_app_gateway_custom_domain" {
  depends_on = [
    azurerm_key_vault.key_vault_app_gateway_custom_domain
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_app_gateway_custom_domain.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create a Network Security Perimeter resource assocation to associate the Key Vault with the NSP profile
##
resource "azapi_resource" "assoc_app_gateway_key_vault_custom_domain" {
  depends_on = [
    azapi_resource.access_rule_key_vault_app_gateway_ipprefix,
    azapi_resource.access_rule_key_vault_app_gateway_sub_id,
    azurerm_key_vault.key_vault_app_gateway_custom_domain
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raappgwkv"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_app_gateway_resources.id
  schema_validation_enabled = false

  body = {
    properties = {
      # TODO: 3/2026 Typically don't enforce since no NSP links yet, but need to in order to restrict network access to Key Vault
      # while supporting App Gateway to pull from it
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_key_vault.key_vault_app_gateway_custom_domain.id
      }
      profile = {
        id = azapi_resource.profile_nsp_key_vault_app_gateway.id
      }
    }
  }
}

## Create a Private Endpoint to the Key Vault
## 
resource "azurerm_private_endpoint" "private_endpoint_key_vault_app_gateway" {
  depends_on = [
    azapi_resource.assoc_app_gateway_key_vault_custom_domain
  ]

  name                = "pekvappgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name
  subnet_id           = var.subnet_id_svc

  private_service_connection {
    name                           = "pekvappgw${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.key_vault_app_gateway_custom_domain.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_app_gateway_custom_domain.name}vault"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }

  tags = var.tags
}

## Link the Azure Private DNS Zone for Key Vault to the virtual network the Application Gateway is deployed to. Not sure why, but this is documented as being required
##
resource "azurerm_private_dns_zone_virtual_network_link" "link_key_vault_app_gateway_custom_domain" {
  depends_on = [
    azurerm_private_endpoint.private_endpoint_key_vault_app_gateway
  ]

  name                  = "linkappgw${var.region_code}${var.random_string}"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = "privatelink.vaultcore.azure.net"
  virtual_network_id    = local.app_gateway_virtual_network_id
}

########## Create a certificate that will be used for the custom domain name of the Application Gateway and store it in the Key Vault
##########
##########

## Create a certificate request in Azure Key Vault
##
resource "azurerm_key_vault_certificate" "app_gateway_certificate" {
  depends_on = [
    azapi_resource.assoc_app_gateway_key_vault_custom_domain,
    azurerm_private_endpoint.private_endpoint_key_vault_app_gateway,
    azurerm_key_vault.key_vault_app_gateway_custom_domain
  ]

  name         = "app-gateway${var.random_string}"
  key_vault_id = azurerm_key_vault.key_vault_app_gateway_custom_domain.id

  certificate_policy {
    issuer_parameters {
      # Use unknown since it's not Digicert or GlobalSign
      name = "Unknown"
    }

    key_properties {
      # Private key must be exportable for APIM to pull the PFX into its own store
      exportable = true
      key_size   = 4096
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=*.${var.app_gateway_domain_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [
          "*.${var.app_gateway_domain_name}"
        ]
      }

      key_usage = [
        "digitalSignature",
        "keyEncipherment"
      ]
    }
  }
}

## Create a registration object
##
resource "acme_registration" "app_gateway_certificate_registration_letsencrypt" {
  depends_on = [
    data.azurerm_key_vault_secret.letsencrypt_account_key
  ]

  # Replaces \r\n with newlines to account for the way Key Vault butchers the PEM
  account_key_pem = replace(
    replace(
      data.azurerm_key_vault_secret.letsencrypt_account_key.value,
      "\\r\\n",
      "\n"
    ),
    "\\n",
    "\n"
  )
  email_address = var.letsencrypt_account_email
}

## Create a certificate request using Cloudflare for DNS validation
##
resource "acme_certificate" "app_gateway_certificate_request" {
  depends_on = [
    data.azurerm_key_vault_secret.letsencrypt_account_key
  ]

  account_key_pem         = acme_registration.app_gateway_certificate_registration_letsencrypt.account_key_pem
  certificate_request_pem = data.external.certificate_csr.result.csr

  dns_challenge {
    provider = "cloudflare"
    config = {
      CLOUDFLARE_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
  # Don't revoke certs on destroy since they are revoked every 90 days and I may want to redeploy
  revoke_certificate_on_destroy = false
}

## Add the signed certificate into Key Vault to complete the CSR process
##
resource "null_resource" "merge_certificate" {
  depends_on = [
    acme_certificate.app_gateway_certificate_request
  ]

  triggers = {
    certificate_pem = acme_certificate.app_gateway_certificate_request.certificate_pem
  }

  provisioner "local-exec" {
    command = <<EOT
      # Check if the certificate is still in pending state
      CERT_STATUS=$(az keyvault certificate pending show \
        --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_app_gateway_custom_domain.id).resource_name} \
        --name ${azurerm_key_vault_certificate.app_gateway_certificate.name} \
        --query "status" -o tsv 2>/dev/null || echo "notfound")
      
      if [ "$CERT_STATUS" = "inProgress" ]; then
        echo "Certificate is pending, merging signed certificate..."
        echo '${acme_certificate.app_gateway_certificate_request.certificate_pem}' > ${path.module}/signed-cert.pem
        echo '${acme_certificate.app_gateway_certificate_request.issuer_pem}' >> ${path.module}/signed-cert.pem
        az keyvault certificate pending merge \
          --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_app_gateway_custom_domain.id).resource_name} \
          --name ${azurerm_key_vault_certificate.app_gateway_certificate.name} \
          --file ${path.module}/signed-cert.pem
        rm ${path.module}/signed-cert.pem
        echo "Certificate merged successfully."
      else
        echo "Certificate is not in pending state (status: $CERT_STATUS), skipping merge."
      fi
    EOT
  }
}

########## Create the user-assigned managed identity and relevant RBAC role assignments
##########
##########

## Create the user-assigned managed for the Application Gateway instance
##
resource "azurerm_user_assigned_identity" "umi_app_gateway" {
  depends_on = [
    azurerm_resource_group.rg_app_gateway,
    null_resource.merge_certificate
  ]

  name                = "umiappgateway${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name

  tags = var.tags
}

## Sleep for 10 seconds to allow the user-assigned managed identity to replicate through Entra ID
##
resource "time_sleep" "wait_umi_app_gateway" {

  depends_on = [
    azurerm_user_assigned_identity.umi_app_gateway
  ]
  create_duration = "120s"
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for Application Gateway instance
## the Key Vault Secrets User role on the Key Vault instance holding the certificate for the Application Gateway custom domain
##
resource "azurerm_role_assignment" "umi_app_gateway_key_vault_certificate_user" {
  depends_on = [
    time_sleep.wait_umi_app_gateway,
    azurerm_key_vault.key_vault_app_gateway_custom_domain
  ]

  scope                = azurerm_key_vault.key_vault_app_gateway_custom_domain.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.umi_app_gateway.principal_id
}

## Sleep for 120 seconds to allow the replication of the RBAC role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_app_gateway_permissions" {
  depends_on = [
    azurerm_role_assignment.umi_app_gateway_key_vault_certificate_user
  ]
  create_duration = "120s"
}

########## Create the Application Gateway instance and supporting resources
##########
##########

## Create a public IP address to associate to the Application Gateway if it is being deployed with a public listener
##
resource "azurerm_public_ip" "app_gateway_public_ip" {
  count = var.public_listener == true ? 1 : 0

  name                = "pip-agw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

## Create the Application Gateway instance
##
resource "azurerm_application_gateway" "app_gateway" {
  depends_on = [
    null_resource.merge_certificate,
    time_sleep.wait_umi_app_gateway_permissions
  ]

  name                = "appgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_app_gateway.name
  tags                = var.tags

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_app_gateway.id
    ]
  }

  sku {
    # Configure to use WAF SKU
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  waf_configuration {
    enabled            = true
    firewall_mode      = "Detection"
    rule_set_type      = "OWASP"
    rule_set_version   = "3.2"
    request_body_check = true

  }

  ## Create frontend IP configurations and gateway ip configuration
  ##

  # Create a public frontend IP configuration to be used with a public listener if configured to deploy a public listener
  dynamic "frontend_ip_configuration" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name                 = local.frontend_ip_configuration_public_name
      public_ip_address_id = azurerm_public_ip.app_gateway_public_ip[0].id
    }
  }

  # Create a private frontend IP configuration to be used with a private listener
  frontend_ip_configuration {
    name                          = local.frontend_ip_configuration_private_name
    subnet_id                     = var.subnet_id_app_gateway
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address
  }

  # This is the subnet the Application Gateway will be deployed to
  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.subnet_id_app_gateway
  }

  ## Create frontend ports for HTTP, HTTPS, TCP, and TLS
  ##

  # Create the frontend ports for HTTP traffic
  frontend_port {
    name = local.frontend_port_http_name
    port = 80
  }

 # Create the frontend ports for HTTPS traffic
  frontend_port {
    name = local.frontend_port_https_name
    port = 443
  }

  # Create a frontend port for TCP proxy for the private listener
  # The public and private listener can't share the same frontend port for TCP
  frontend_port {
    name = local.frontend_port_tcp_proxy_name_private
    port = var.tcp_port
  }

  # Create a frontend port for TCP proxy for the public listener
  # The public and private listener can't share the same frontend port for TCP
  dynamic "frontend_port" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name = local.frontend_port_tcp_proxy_name_public
      port = var.tcp_port + 2
    }
  }

  # Create a frontend port for TLS proxy for the private listener
  # The public and private listener can't share the same frontend port for TLS
  frontend_port {
      name = local.frontend_port_tls_proxy_name_private
      port = var.tcp_port + 1
  }

  # Create a frontend port for TLS proxy for the public listener if configured to deploy a public listener
  # The public and private listener can't share the same frontend port for TLS
  dynamic "frontend_port" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name = local.frontend_port_tls_proxy_name_public
      port = var.tcp_port + 3
    }
  }
  ## Create custom probes
  ##

  # Create the custom probe for http
  probe {
    name                                      = local.probe_http_name
    protocol                                  = "Http"
    port                                      = 80
    path                                      = "/healthz"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  # Create the custom probe for https
  probe {
    name                                      = local.probe_https_name
    protocol                                  = "Https"
    port                                      = 443
    path                                      = "/healthz"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  # Create the custom probe for TCP
  probe {
    name                = local.probe_tcp_name
    protocol            = "Tcp"
    port                = var.tcp_port
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  # Create the custom probe for TLS
  probe {
    name                = local.probe_tls_name
    protocol            = "Tls"
    port                = var.tcp_port
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  ## Create empty backend address pools
  ##

  # Create backend pool used for http and https
  backend_address_pool {
    name = local.backend_pool_web_default
  }

  # Create backend pool used for tcp proxy
  backend_address_pool {
    name = local.backend_pool_tcp_proxy_default
  }

  ## Create backend HTTP/S and TCP/TLS settings
  ##

  # Create the backend settings for http
  backend_http_settings {
    name                                = local.backend_http_settings_http_default
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = "20"
    pick_host_name_from_backend_address = true
    probe_name = local.probe_http_name
  }

  # Create the backend settings for https
  backend_http_settings {
    name                                = local.backend_http_settings_https_default
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = "20"
    pick_host_name_from_backend_address = true
    probe_name = local.probe_https_name
  }

  # Create the backend settings for TCP
  backend {
    name                           = local.backend_tcp_settings_tcp_proxy_default
    port                           = var.tcp_port
    protocol                       = "Tcp"
    client_ip_preservation_enabled = true
    probe_name                     = local.probe_tcp_name
    timeout_in_seconds             = 20
  }

  # Create the backend settings for TLS
  backend {
    name                           = local.backend_tls_settings_tls_proxy_default
    port                           = var.tcp_port
    protocol                       = "Tls"
    client_ip_preservation_enabled = true
    probe_name                     = local.probe_tls_name
    timeout_in_seconds             = 20
    host_name = "testapp.local"
  }

  # SSL certificate used for HTTPS and TLS listeners
  ssl_certificate {
    name                = local.ssl_certificate_name
    key_vault_secret_id = data.azurerm_key_vault_certificate.app_gateway_certificate_completed.versionless_secret_id
  }

  ## Create listeners
  ##

  # Create listener for http associated to the public ip if creating a public listener
  dynamic "http_listener" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name                           = local.listener_http_name_public
      frontend_ip_configuration_name = local.frontend_ip_configuration_public_name
      frontend_port_name             = local.frontend_port_http_name
      protocol                       = "Http"
    }
  }

  # Create listener for https associated to the public ip if creating a public listener
  dynamic "http_listener" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name                           = local.listener_https_name_public
      frontend_ip_configuration_name = local.frontend_ip_configuration_public_name
      frontend_port_name             = local.frontend_port_https_name
      protocol                       = "Https"
      ssl_certificate_name           = local.ssl_certificate_name
    }
  }

  # Create listener for http associated to the private ip
  http_listener {
    name                           = local.listener_http_name_private
    frontend_ip_configuration_name = local.frontend_ip_configuration_private_name
    frontend_port_name             = local.frontend_port_http_name
    protocol                       = "Http"
  }

  # Create listener for https associated to the private ip
  http_listener {
    name                           = local.listener_https_name_private
    frontend_ip_configuration_name = local.frontend_ip_configuration_private_name
    frontend_port_name             = local.frontend_port_https_name
    protocol                       = "Https"
    ssl_certificate_name           = local.ssl_certificate_name
  }

  # Create listener for tcp associated to the public ip address if creating a public listener
  dynamic "listener" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name                           = local.listener_tcp_proxy_name_public
      frontend_ip_configuration_name = local.frontend_ip_configuration_public_name
      frontend_port_name             = local.frontend_port_tcp_proxy_name_public
      protocol                       = "Tcp"
    }
  }

  # Create listener for tls associated to the public ip address if creating a public listener
  dynamic "listener" {
    for_each = var.public_listener == true ? [1] : []
    content {
      name                           = local.listener_tls_proxy_name_public
      frontend_ip_configuration_name = local.frontend_ip_configuration_public_name
      frontend_port_name             = local.frontend_port_tls_proxy_name_public
      protocol                       = "Tls"
      ssl_certificate_name           = local.ssl_certificate_name
    }
  }

  # Create listener for tcp associated to the private ip address
  listener {
    name                           = local.listener_tcp_proxy_name_private
    frontend_ip_configuration_name = local.frontend_ip_configuration_private_name
    frontend_port_name             = local.frontend_port_tcp_proxy_name_private
    protocol                       = "Tcp"
  }

  # Create listener for tls associated to the private ip address
  listener {
      name                           = local.listener_tls_proxy_name_private
      frontend_ip_configuration_name = local.frontend_ip_configuration_private_name
      frontend_port_name             = local.frontend_port_tls_proxy_name_private
      protocol                       = "Tls"
      ssl_certificate_name           = local.ssl_certificate_name
  }

  ## Create routing rules
  ##

  # Create a basic routing rule for http 
  request_routing_rule {
    name                       = local.routing_rule_http_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.listener_http_name_public
    backend_address_pool_name  = local.backend_pool_web_default
    backend_http_settings_name = local.backend_http_settings_http_default
  }

  # Create a basic routing rule for TCP
  routing_rule {
    name                      = local.routing_rule_tcp_proxy_name
    priority                  = 101
    listener_name             = local.listener_tcp_proxy_name_public
    backend_address_pool_name = local.backend_pool_tcp_proxy_default
    backend_name              = local.backend_tcp_settings_tcp_proxy_default
  }
}

