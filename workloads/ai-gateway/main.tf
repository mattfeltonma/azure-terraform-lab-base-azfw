########## Create a certificate that will be used by the APIM Gateway
##########
##########

## Create a certificate request in Azure Key Vault
##
resource "azurerm_key_vault_certificate" "apim_gateway_certificate" {
  count = var.provision_certificate == true ? 1 : 0

  name         = "apim-gateway-certificate-v3${var.random_string}"
  key_vault_id = var.key_vault_id

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
      subject            = "CN=apim-example${var.random_string}.${var.apim_private_dns_zone_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = concat(
          [
            "apim-example${var.random_string}.${var.apim_private_dns_zone_name}",
            "apim-example${var.random_string}${var.region_code}.${var.apim_private_dns_zone_name}",
            # These additional SANS are only used for classic SKUs and really aren't even used there
            "apim-example${var.random_string}.management.${var.apim_private_dns_zone_name}",
            "apim-example${var.random_string}.scm.${var.apim_private_dns_zone_name}",
            "apim-example${var.random_string}.developer.${var.apim_private_dns_zone_name}"
          ],
          [
            for region in var.regions_additional : "apim-example${var.random_string}${region.region_code}.${var.apim_private_dns_zone_name}"
          ]
        )
      }

      key_usage = [
        "digitalSignature",
        "keyEncipherment"
      ]
    }
  }
}

## Create a private key to be used for the ACME certificate request
## In real production environments this key should be stored in something like Key Vault to ensure that the
## certificates can be revoked. Here, I just create a random one and if I need a new cert I never revoke the old one
## just create a new one
resource "tls_private_key" "acme_account_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

## Create a registration object
##
resource "acme_registration" "apim_gateway_certificate_registration_letsencrypt" {
  count = var.provision_certificate == true ? 1 : 0

  account_key_pem = tls_private_key.acme_account_key.private_key_pem
  email_address   = var.publisher_email
}

## Create a certificate request using Cloudflare for DNS validation
##
resource "acme_certificate" "apim_gateway_certificate_request" {
  count = var.provision_certificate == true ? 1 : 0

  account_key_pem         = acme_registration.apim_gateway_certificate_registration_letsencrypt[0].account_key_pem
  certificate_request_pem = data.external.certificate_csr[0].result.csr

  dns_challenge {
    provider = "cloudflare"
    config = {
      CLOUDFLARE_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

## Add the signed certificate into Key Vault to complete the CSR process
##
resource "null_resource" "merge_certificate" {
  count = var.provision_certificate == true ? 1 : 0

  depends_on = [
    acme_certificate.apim_gateway_certificate_request
  ]

  triggers = {
    certificate_pem = acme_certificate.apim_gateway_certificate_request[0].certificate_pem
  }

  provisioner "local-exec" {
    command = <<EOT
      # Check if the certificate is still in pending state
      CERT_STATUS=$(az keyvault certificate pending show \
        --vault-name ${provider::azurerm::parse_resource_id(var.key_vault_id).resource_name} \
        --name ${azurerm_key_vault_certificate.apim_gateway_certificate[0].name} \
        --query "status" -o tsv 2>/dev/null || echo "notfound")
      
      if [ "$CERT_STATUS" = "inProgress" ]; then
        echo "Certificate is pending, merging signed certificate..."
        echo '${acme_certificate.apim_gateway_certificate_request[0].certificate_pem}' > ${path.module}/signed-cert.pem
        echo '${acme_certificate.apim_gateway_certificate_request[0].issuer_pem}' >> ${path.module}/signed-cert.pem
        az keyvault certificate pending merge \
          --vault-name ${provider::azurerm::parse_resource_id(var.key_vault_id).resource_name} \
          --name ${azurerm_key_vault_certificate.apim_gateway_certificate[0].name} \
          --file ${path.module}/signed-cert.pem
        rm ${path.module}/signed-cert.pem
        echo "Certificate merged successfully."
      else
        echo "Certificate is not in pending state (status: $CERT_STATUS), skipping merge."
      fi
    EOT
  }
}

## Create the required CNAME record in Cloudfare which is required for v2 APIM custom domain
##
resource "cloudflare_dns_record" "custom_domain_cname" {
  count = var.provision_certificate == true && var.apim_generation_v2 == true ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "apim-example${var.random_string}.${var.apim_private_dns_zone_name}"
  content = "apim${var.region_code}${var.random_string}.azure-api.net"
  ttl     = 60
  type    = "CNAME"

}

########## Create a resource group for the AML Registries
########## 
##########

## Create resource group where resources in this template will be deployed to
##
resource "azurerm_resource_group" "rg_ai_gateway" {
  name     = "rgaigateway${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Log Analytics Workspace for the resources created in this deployment
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawaigateway${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

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

## Pause for 30 seconds after Log Analytics Workspace is created to allow for replication
##
resource "time_sleep" "sleep_law_creation" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]
  create_duration = "30s"
}

########### Create the supporting resources for the API Management instance
###########
###########

## Create a Private DNS Zone that be the custom domain namespace for the API Management instance
##
resource "azurerm_private_dns_zone" "private_dns_zone_apim" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_resource_group.rg_ai_gateway
  ]

  name                = var.apim_private_dns_zone_name
  resource_group_name = var.resource_group_dns
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the Private DNS Zone virtual network link to the shared services virtual network
##
resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_link_apim" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_private_dns_zone.private_dns_zone_apim
  ]

  name                  = azurerm_private_dns_zone.private_dns_zone_apim.name
  resource_group_name   = var.resource_group_dns
  private_dns_zone_name = azurerm_private_dns_zone.private_dns_zone_apim.name
  virtual_network_id    = var.virtual_network_id_shared_services
  registration_enabled  = false

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Application Insights instance that will be used by the API Management instance APIs
## to monitor and track API requests
resource "azurerm_application_insights" "appins_api_management" {
  depends_on = [
    time_sleep.sleep_law_creation
  ]

  name                = "appinsapim${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  application_type    = "other"
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########### Create the Foundry Accounts and deploy the gpt4-o model
###########
###########

## Create Foundry accounts to act as the backends for the API Management instance
##
resource "azurerm_cognitive_account" "ai_foundry_accounts" {
  depends_on = [
    azurerm_resource_group.rg_ai_gateway,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  for_each = local.ai_foundry_regions

  name                = "aif${each.value.region_code}${var.random_string}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = merge(var.tags, { SecurityControl = "Ignore" })

  # Create an AI Foundry Account to support Foundry Projects
  kind                       = "AIServices"
  sku_name                   = "S0"
  project_management_enabled = true

  # Set custom subdomain name for DNS names created for this Foundry resource
  custom_subdomain_name = "aif${each.value.region_code}${var.random_string}"

  # Block public network access to the Foundry account
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Deploy GPT 4o model to the Foundry accounts
##
resource "azurerm_cognitive_deployment" "gpt4o_chat_model_deployments" {
  depends_on = [
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.ai_foundry_accounts[each.key].id

  sku {
    name     = "GlobalStandard"
    capacity = 100
  }

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-08-06"
  }
}

## Create a diagnostic setting for the AI Foundry accounts to send logs to the Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aifoundry_accounts" {
  depends_on = [
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                       = "diag-base"
  target_resource_id         = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "AzureOpenAIRequestUsage"
  }

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Trace"
  }
}

## Create Private Endpoint for AI Foundry account
##
resource "azurerm_private_endpoint" "pe_aifoundry_accounts" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_cognitive_account.ai_foundry_accounts,
    azurerm_cognitive_deployment.gpt4o_chat_model_deployments
  ]

  for_each = local.ai_foundry_regions

  name                = "pe${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}account"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}account"

  private_service_connection {
    name                           = "peconn${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}account"
    private_connection_resource_id = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}account"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########### Create the API Management instance and its dependent resources
###########
###########

## Create a public IP address for API Management instance if customer wishes to manage it in their subscription.
## Otherwise the public IP is managed by Microsoft and is not visible in the subscription.
resource "azurerm_public_ip" "pip_apim" {
  count = var.customer_managed_public_ip && var.apim_generation_v2 == false ? 1 : 0

  name                = "apim${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "apim${var.region_code}${var.random_string}"

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create additional public IP addresses for API Management Gateway instances when using the multi-region gateway feature
## if customer wishes to manage it in their subscription. Otherwise the public IP is managed by Microsoft and is not visible in the subscription.
resource "azurerm_public_ip" "pip_apim_additional_regions" {
  for_each = var.customer_managed_public_ip && var.apim_generation_v2 == false ? { for idx, region in var.regions_additional : region.region => region } : {}

  name                = "apim${each.value.region_code}${var.random_string}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "apim${each.value.region_code}${var.random_string}"

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create an Azure API Management service instance
## This resource creation takes about 40 minutes
resource "azurerm_api_management" "apim" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_application_insights.appins_api_management,
    azurerm_public_ip.pip_apim,
    azurerm_public_ip.pip_apim_additional_regions,
    null_resource.merge_certificate,
    cloudflare_dns_record.custom_domain_cname
  ]

  name                = "apim${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = var.tags

  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email
  sku_name        = var.sku

  # Assign a customer-managed public IP if requested, otherwise leave null to have Microsoft manage the public IP
  public_ip_address_id = var.customer_managed_public_ip && var.apim_generation_v2 == false ? azurerm_public_ip.pip_apim[0].id : null

  # Create an internal-mode API Management instance
  virtual_network_type = "Internal"

  # Create multi-region API Management Gateways if additional regions have been specified
  # TODO: 1/2026 Remove the condition filtering v2 SKUs once v2 supports multi-region gateways
  dynamic "additional_location" {
    for_each = var.apim_generation_v2 == false && var.regions_additional != null ? var.regions_additional : []
    iterator = region
    content {
      location             = region.value.region
      public_ip_address_id = var.customer_managed_public_ip ? azurerm_public_ip.pip_apim_additional_regions[region.value.region].id : null
      virtual_network_configuration {
        subnet_id = region.value.subnet_id
      }
    }
  }

  # Specify the subnet to deploy the primary region API Management instance to
  virtual_network_configuration {
    subnet_id = var.subnet_id
  }

  # Create a system-assigned managed identity for the API Management instance
  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 60 seconds after API Management instance is created to allow for system-managed identity to replicate
##
resource "time_sleep" "sleep_apim_managed_identity" {
  depends_on = [
    azurerm_api_management.apim
  ]
  create_duration = "60s"
}

## Create Azure RBAC Role assignment granting the Key Vault Secrets user role on the
## Key Vault storing the certificate that will be used for the custom domain on the API Management instance
resource "azurerm_role_assignment" "apim_perm_key_vault_secrets_user_key_vault" {
  depends_on = [
    time_sleep.sleep_apim_managed_identity
  ]
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

## Sleep for 120 seconds after creating the role assignment to allow time for permissions to propagate
##
resource "time_sleep" "sleep_apim_rbac" {
  depends_on = [
    azurerm_role_assignment.apim_perm_key_vault_secrets_user_key_vault
  ]
  create_duration = "120s"
}

## Create a diagnostic setting for the API Management instance to send logs to the Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_apim" {
  depends_on = [
    azurerm_api_management.apim,
  ]

  name                           = "diag-base"
  target_resource_id             = azurerm_api_management.apim.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "GatewayLogs"
  }
  enabled_log {
    category = "WebSocketConnectionLogs"
  }
  enabled_log {
    category = "DeveloperPortalAuditLogs"
  }

  enabled_log {
    category = "GatewayLlmLogs"
  }
}

## Create a custom domain names for the API Management instance
## This resource creation takes about 20 minutes
resource "azurerm_api_management_custom_domain" "apim_custom_domains" {
  depends_on = [
    time_sleep.sleep_apim_rbac
  ]

  api_management_id = azurerm_api_management.apim.id

  gateway {
    host_name                = "apim-example${var.random_string}.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.provision_certificate == true ? data.azurerm_key_vault_certificate.apim_gateway_certificate_completed[0].versionless_secret_id : var.key_vault_secret_id_versionless
    default_ssl_binding      = true
  }

  dynamic "management" {
    for_each = var.apim_generation_v2 ? [] : [1]
    content {
      host_name                = "apim-example${var.random_string}.management.${var.apim_private_dns_zone_name}"
      key_vault_certificate_id = var.provision_certificate == true ? data.azurerm_key_vault_certificate.apim_gateway_certificate_completed[0].versionless_secret_id : var.key_vault_secret_id_versionless
    }
  }

  dynamic "scm" {
    for_each = var.apim_generation_v2 ? [] : [1]
    content {
      host_name                = "apim-example${var.random_string}.scm.${var.apim_private_dns_zone_name}"
      key_vault_certificate_id = var.provision_certificate == true ? data.azurerm_key_vault_certificate.apim_gateway_certificate_completed[0].versionless_secret_id : var.key_vault_secret_id_versionless
    }
  }

  dynamic "developer_portal" {
    for_each = var.apim_generation_v2 ? [] : [1]
    content {
      host_name                = "apim-example${var.random_string}.developer.${var.apim_private_dns_zone_name}"
      key_vault_certificate_id = var.provision_certificate == true ? data.azurerm_key_vault_certificate.apim_gateway_certificate_completed[0].versionless_secret_id : var.key_vault_secret_id_versionless
    }
  }
}

########### Create the API Management backends with circuit breakers and backend pools
###########
###########

## Create circuit breaker backends for AI Foundry instances hosting the models used with the OpenAI classic API
##
module "backend_circuit_breaker_aifoundry_instance_openai_classic" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  source       = "./modules/backend-circuit-breaker"
  apim_id      = azurerm_api_management.apim.id
  backend_name = "${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}classic"
  url          = "https://${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}.openai.azure.com/openai"
}

## Create backend pool with AI Foundry backends
##
module "backend_pool_aifoundry_instances_openai_classic" {
  depends_on = [
    module.backend_circuit_breaker_aifoundry_instance_openai_classic
  ]

  source    = "./modules/backend-pool"
  pool_name = "foundry-pool-openai-classic"
  apim_id   = azurerm_api_management.apim.id

  backends = [
    for foundry_backend in module.backend_circuit_breaker_aifoundry_instance_openai_classic :
    {
      id       = foundry_backend.id
      priority = 1
    }
  ]
}

## Create circuit breaker backends for AI Foundry instances hosting the models used with the OpenAI v1 API
##
module "backend_circuit_breaker_aifoundry_instance_openai_v1" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  source       = "./modules/backend-circuit-breaker"
  apim_id      = azurerm_api_management.apim.id
  backend_name = "${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}v1"
  url          = "https://${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}.openai.azure.com/openai/v1"
}

## Create backend pool with AI Foundry backends
##
module "backend_pool_aifoundry_instances_openai_v1" {
  depends_on = [
    module.backend_circuit_breaker_aifoundry_instance_openai_v1
  ]

  source    = "./modules/backend-pool"
  pool_name = "foundry-pool-openai-v1"
  apim_id   = azurerm_api_management.apim.id

  backends = [
    for foundry_backend in module.backend_circuit_breaker_aifoundry_instance_openai_v1 :
    {
      id       = foundry_backend.id
      priority = 1
    }
  ]
}


########### Create API Management loggers
###########
###########

## Create an API Management logger for Application Insights
##
resource "azurerm_api_management_logger" "apim_logger_appinsights" {
  name                = "logger-appinsights"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  resource_id         = azurerm_application_insights.appins_api_management.id

  application_insights {
    instrumentation_key = azurerm_application_insights.appins_api_management.instrumentation_key
  }
}

########### Create APIs for the classic OpenAI API, OpenAI v1 API, and the Foundry AI Model Inference API and create
########### diagnostic settings for both the App Insights Logger and Azure Monitor Logger
###########

## Create an API for the 2024-10-21 OpenAI Inferencing API
##
resource "azurerm_api_management_api" "openai_original" {
  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    module.backend_pool_aifoundry_instances_openai_classic
  ]

  name                  = "azure-openai-original"
  resource_group_name   = azurerm_resource_group.rg_ai_gateway.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Azure OpenAI Inferencing and Authoring API"
  path                  = "openai"
  api_type              = "http"
  protocols             = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/api-specs/2025-04-01-preview-aoai-inferencing.json")
  }
}

## Create diagnostic setting for the OpenAI original API for Application Insights
## 
resource "azapi_resource" "diag_openai_original_api_appsinights" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "applicationinsights"
  parent_id                 = azurerm_api_management_api.openai_original.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/logger-appinsights"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      httpCorrelationProtocol = "W3C"
      metrics = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
    }
  }
}

## Create diagnostic setting for the OpenAI original API for Azure Monitor
##
resource "azapi_resource" "diag_openai_original_api_monitor" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "azuremonitor"
  parent_id                 = azurerm_api_management_api.openai_original.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/azuremonitor"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
        responses = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
      }
    }
  }
}

## Create an API for the v1 OpenAI API
##
resource "azurerm_api_management_api" "openai_v1" {
  depends_on = [
    azurerm_api_management_api.openai_original,
    module.backend_pool_aifoundry_instances_openai_v1
  ]

  name                  = "azure-openai-v1"
  resource_group_name   = azurerm_resource_group.rg_ai_gateway.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Azure OpenAI v1 API"
  path                  = "openai-v1"
  api_type              = "http"
  protocols             = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/api-specs/azure-v1-v1-generated.json")
  }
}

## Create diagnostic setting for the OpenAI original API for Application Insights
## 
resource "azapi_resource" "diag_openai_v1_api_appsinights" {
  depends_on = [
    azurerm_api_management_api.openai_v1
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "applicationinsights"
  parent_id                 = azurerm_api_management_api.openai_v1.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/logger-appinsights"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      httpCorrelationProtocol = "W3C"
      metrics = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
    }
  }
}

## Create diagnostic setting for the OpenAI v1 API for Azure Monitor
##
resource "azapi_resource" "diag_openai_v1_api_monitor" {
  depends_on = [
    azurerm_api_management_api.openai_v1
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "azuremonitor"
  parent_id                 = azurerm_api_management_api.openai_v1.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/azuremonitor"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
        responses = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
      }
    }
  }
}

########### Create an API Management Policies for the APIs
###########
###########

## Create an API Management policy for the OpenAI original API
## 
resource "azurerm_api_management_api_policy" "apim_policy_openai_original" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  api_name            = azurerm_api_management_api.openai_original.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
          <base />
          <!-- Evaluate the JWT and ensure it was issued by the right Entra ID tenant -->
          <validate-jwt header-name="Authorization" failed-validation-httpcode="403" failed-validation-error-message="Forbidden">
              <openid-config url="https://login.microsoftonline.com/${var.entra_id_tenant_id}/v2.0/.well-known/openid-configuration" />
              <issuers>
                  <issuer>https://sts.windows.net/${var.entra_id_tenant_id}/</issuer>
              </issuers>
          </validate-jwt>
          <!-- Extract the Entra ID application id from the JWT -->
          <set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("Authorization",string.Empty).Split(' ').Last().AsJwt().Claims.GetValueOrDefault("appid", "none"))" />
          <!-- Extract the Agent ID from the x-ms-foundry-agent-id header. This is only relevant for Foundry native agents -->
          <set-variable name="agentId" value="@(context.Request.Headers.GetValueOrDefault("x-ms-foundry-agent-id", "none"))" />
          <!-- Extract the project GUID from the x-ms-foundry-project-id header. This is only relevant for Foundry native agents -->
          <set-variable name="projectId" value="@(context.Request.Headers.GetValueOrDefault("x-ms-foundry-project-id", "none"))" />
          <!-- Extract the Foundry Project name from the "openai-project" header. This is only relevant for Foundry native agents -->
          <set-variable name="projectName" value="@(context.Request.Headers.GetValueOrDefault("openai-project", "none"))" />
          <!-- Extract the deployment name from the uri path -->
          <set-variable name="uriPath" value="@(context.Request.OriginalUrl.Path)" />
          <set-variable name="deploymentName" value="@(System.Text.RegularExpressions.Regex.Match((string)context.Variables["uriPath"], "/deployments/([^/]+)").Groups[1].Value)" />
          <!-- Set the X-Entra-App-ID header to the Entra ID application ID from the JWT -->
          <set-header name="X-Entra-App-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("appId"))</value>
          </set-header>
          <set-header name="X-Foundry-Agent-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("agentId"))</value>
          </set-header>
          <set-header name="X-Foundry-Project-Name" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("projectName"))</value>
          </set-header>
          <set-header name="X-Foundry-Project-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("projectId"))</value>
          </set-header>
          <choose>
            <!-- If the request isn't from a Foundry native agent and is instead an application or external agent -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("agentId") == "none" && context.Variables.GetValueOrDefault<string>("projectId") == "none")">
              <!-- Throttle token usage based on the appid -->
              <llm-token-limit counter-key="@(context.Variables.GetValueOrDefault<string>("appId","none"))" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
              <!-- Emit token metrics to Application Insights -->
              <llm-emit-token-metric namespace="openai-metrics">
                  <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
                  <dimension name="client_ip" value="@(context.Request.IpAddress)" />
                  <dimension name="appId" value="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" />
              </llm-emit-token-metric>
            </when>
            <!-- If the request is from a Foundry native agent -->
            <otherwise>
              <!-- Throttle token usage based on the agentId -->
              <llm-token-limit counter-key="@($"{context.Variables.GetValueOrDefault<string>("projectId")}_{context.Variables.GetValueOrDefault<string>("agentId")}")" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
              <!-- Emit token metrics to Application Insights -->
              <llm-emit-token-metric namespace="llm-metrics">
                  <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
                  <dimension name="client_ip" value="@(context.Request.IpAddress)" />
                  <dimension name="agentId" value="@(context.Variables.GetValueOrDefault<string>("agentId","00000000-0000-0000-0000-000000000000"))" />
                  <dimension name="projectId" value="@(context.Variables.GetValueOrDefault<string>("projectId","00000000-0000-0000-0000-000000000000"))" />
              </llm-emit-token-metric>
            </otherwise>
          </choose>
          <choose>
            <!-- If the request is from a Foundry native agent -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("agentId") != "none" && context.Variables.GetValueOrDefault<string>("projectId") != "none")">
            <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
            </when>
          </choose>
          <set-backend-service backend-id="${module.backend_pool_aifoundry_instances_openai_classic.name}" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <base />
      </outbound>
  </policies>
XML
}

## Create an API Management policy for the OpenAI v1 API
##
resource "azurerm_api_management_api_policy" "apim_policy_openai_v1" {
  api_name            = azurerm_api_management_api.openai_v1.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  xml_content = <<XML
    <policies>
      <inbound>
          <base />
          <!-- Evaluate the JWT and ensure it was issued by the right Entra ID tenant -->
          <validate-jwt header-name="Authorization" failed-validation-httpcode="403" failed-validation-error-message="Forbidden">
              <openid-config url="https://login.microsoftonline.com/${var.entra_id_tenant_id}/v2.0/.well-known/openid-configuration" />
              <issuers>
                  <issuer>https://sts.windows.net/${var.entra_id_tenant_id}/</issuer>
              </issuers>
          </validate-jwt>
          <!-- Extract the Entra ID application id from the JWT -->
          <set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("Authorization",string.Empty).Split(' ').Last().AsJwt().Claims.GetValueOrDefault("appid", "none"))" />
          <!-- Extract the Agent ID from the x-ms-foundry-agent-id header. This is only relevant for Foundry native agents -->
          <set-variable name="agentId" value="@(context.Request.Headers.GetValueOrDefault("x-ms-foundry-agent-id", "none"))" />
          <!-- Extract the project GUID from the x-ms-foundry-project-id header. This is only relevant for Foundry native agents -->
          <set-variable name="projectId" value="@(context.Request.Headers.GetValueOrDefault("x-ms-foundry-project-id", "none"))" />
          <!-- Extract the Foundry Project name from the "openai-project" header. This is only relevant for Foundry native agents -->
          <set-variable name="projectName" value="@(context.Request.Headers.GetValueOrDefault("openai-project", "none"))" />
          <!-- Extract the deployment name from the uri path -->
          <set-variable name="uriPath" value="@(context.Request.OriginalUrl.Path)" />
          <set-variable name="deploymentName" value="@(System.Text.RegularExpressions.Regex.Match((string)context.Variables["uriPath"], "/deployments/([^/]+)").Groups[1].Value)" />
          <!-- Set the X-Entra-App-ID header to the Entra ID application ID from the JWT -->
          <set-header name="X-Entra-App-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("appId"))</value>
          </set-header>
          <set-header name="X-Foundry-Agent-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("agentId"))</value>
          </set-header>
          <set-header name="X-Foundry-Project-Name" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("projectName"))</value>
          </set-header>
          <set-header name="X-Foundry-Project-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("projectId"))</value>
          </set-header>
          <choose>
            <!-- If the request isn't from a Foundry native agent and is instead an application or external agent -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("agentId") == "none" && context.Variables.GetValueOrDefault<string>("projectId") == "none")">
              <!-- Throttle token usage based on the appid -->
              <llm-token-limit counter-key="@(context.Variables.GetValueOrDefault<string>("appId","none"))" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
              <!-- Emit token metrics to Application Insights -->
              <llm-emit-token-metric namespace="openai-metrics">
                  <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
                  <dimension name="client_ip" value="@(context.Request.IpAddress)" />
                  <dimension name="appId" value="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" />
              </llm-emit-token-metric>
            </when>
            <!-- If the request is from a Foundry native agent -->
            <otherwise>
              <!-- Throttle token usage based on the agentId -->
              <llm-token-limit counter-key="@($"{context.Variables.GetValueOrDefault<string>("projectId")}_{context.Variables.GetValueOrDefault<string>("agentId")}")" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
              <!-- Emit token metrics to Application Insights -->
              <llm-emit-token-metric namespace="llm-metrics">
                  <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
                  <dimension name="client_ip" value="@(context.Request.IpAddress)" />
                  <dimension name="agentId" value="@(context.Variables.GetValueOrDefault<string>("agentId","00000000-0000-0000-0000-000000000000"))" />
                  <dimension name="projectId" value="@(context.Variables.GetValueOrDefault<string>("projectId","00000000-0000-0000-0000-000000000000"))" />
              </llm-emit-token-metric>
            </otherwise>
          </choose>
          <choose>
            <!-- If the request is from a Foundry native agent -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("agentId") != "none" && context.Variables.GetValueOrDefault<string>("projectId") != "none")">
            <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
            </when>
          </choose>
          <set-backend-service backend-id="${module.backend_pool_aifoundry_instances_openai_v1.name}" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <base />
      </outbound>
  </policies>
XML
}


########### Create additional APIs for testing the model gateway feature. This APIs will include very basic polciies
########### since this is simply intended to demonstrate how a 3rd party gateway could work
###########

## Create an API for the 2024-10-21 OpenAI Inferencing API that will be used to demonstrate the model gateway connection
##
resource "azurerm_api_management_api" "openai_model_gateway" {
  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    module.backend_pool_aifoundry_instances_openai_classic
  ]

  name                  = "openai-model-gateway"
  resource_group_name   = azurerm_resource_group.rg_ai_gateway.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Azure OpenAI Classic - Model Gateway"
  path                  = "openai-model-gateway"
  api_type              = "http"
  protocols             = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/api-specs/2025-04-01-preview-aoai-inferencing.json")
  }
}

## Create diagnostic setting for the OpenAI Inference API for Application Insights that will be used to demonstrate the model gateway connection
##
resource "azapi_resource" "diag_ai_openai_model_gateway_appsinights" {
  depends_on = [
    azurerm_api_management_api.openai_model_gateway
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "applicationinsights"
  parent_id                 = azurerm_api_management_api.openai_model_gateway.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/logger-appinsights"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      httpCorrelationProtocol = "W3C"
      metrics = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
    }
  }
}

## Create diagnostic setting for the OpenAI original API for Azure Monitor that will be used to demonstrate the model gateway connection
##
resource "azapi_resource" "diag_openai_model_gateway_api_monitor" {
  depends_on = [
    azurerm_api_management_api.openai_model_gateway
  ]

  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "azuremonitor"
  parent_id                 = azurerm_api_management_api.openai_model_gateway.id
  schema_validation_enabled = false
  body = {
    properties = {
      loggerId    = "${azurerm_api_management.apim.id}/loggers/azuremonitor"
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = true
      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }
      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
        responses = {
          maxSizeInBytes = 262144
          messages       = "all"
        }
      }
    }
  }
}

## Create an API Management policy for the OpenAI original API that will be used to demonstrate the model gateway connection. 
## This is a very basic policy
resource "azurerm_api_management_api_policy" "apim_policy_openai_model_gateway" {
  depends_on = [
    azurerm_api_management_api.openai_model_gateway
  ]
  api_name            = azurerm_api_management_api.openai_model_gateway.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
          <base />
          <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
          <set-backend-service backend-id="${module.backend_pool_aifoundry_instances_openai_classic.name}" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <base />
      </outbound>
  </policies>
XML
}

########### Create additional operations and policies that are required to support dynamic model enumeration with
########### Foundry APIM and model gateway integrations
###########

## Create an operation to support getting a specific deployment by name when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_original_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  operation_id        = "get-deployment-by-name"
  api_name            = azurerm_api_management_api.openai_original.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "Get Deployment by Name"
  method              = "GET"
  url_template        = "/deployments/{deploymentName}"

  template_parameter {
    name     = "deploymentName"
    required = true
    type     = "string"
  }
}

## Create an policy for the get deployment by name operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_original_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_original_get_deployment_by_name,
  ]

  api_name            = azurerm_api_management_api.openai_original.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_original_get_deployment_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments/{deploymentName}?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Specify a Foundry deployment that has the models deployed -->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

## Create an operation to support enumerating deployments when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_original_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation_policy.apim_policy_openai_original_get_deployment_by_name
  ]

  operation_id        = "list-deployments"
  api_name            = azurerm_api_management_api.openai_original.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "List Deployments"
  method              = "GET"
  url_template        = "/deployments"
}

## Create an policy for the list deployments operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_original_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_original_list_deployments_by_name
  ]

  api_name            = azurerm_api_management_api.openai_original.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_original_list_deployments_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Azure Resource Manager-->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

## Create an operation to support enumerating deployments when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_v1_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api.openai_v1
  ]

  operation_id        = "get-deployment-by-name"
  api_name            = azurerm_api_management_api.openai_v1.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "Get Deployment by Name"
  method              = "GET"
  url_template        = "/deployments/{deploymentName}"

  template_parameter {
    name     = "deploymentName"
    required = true
    type     = "string"
  }
}

## Create an policy for the get deployment by name operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_v1_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_v1_get_deployment_by_name
  ]

  api_name            = azurerm_api_management_api.openai_v1.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_v1_get_deployment_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments/{deploymentName}?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Azure Resource Manager-->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

## Create an operation to support enumerating deployments when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_v1_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation_policy.apim_policy_openai_v1_get_deployment_by_name
  ]

  operation_id        = "list-deployments"
  api_name            = azurerm_api_management_api.openai_v1.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "List Deployments"
  method              = "GET"
  url_template        = "/deployments"
}

## Create an policy for the list deployments operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_v1_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_v1_list_deployments_by_name
  ]

  api_name            = azurerm_api_management_api.openai_v1.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_v1_list_deployments_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Azure Resource Manager-->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

## Create an operation to support enumerating deployments when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_model_gateway_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api.openai_model_gateway
  ]

  operation_id        = "get-deployment-by-name"
  api_name            = azurerm_api_management_api.openai_model_gateway.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "Get Deployment by Name"
  method              = "GET"
  url_template        = "/deployments/{deploymentName}"

  template_parameter {
    name     = "deploymentName"
    required = true
    type     = "string"
  }
}

## Create an policy for the get deployment by name operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_model_gateway_get_deployment_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_model_gateway_get_deployment_by_name
  ]

  api_name            = azurerm_api_management_api.openai_model_gateway.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_model_gateway_get_deployment_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments/{deploymentName}?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Azure Resource Manager-->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

## Create an operation to support enumerating deployments when using the Foundry APIM connection
##
resource "azurerm_api_management_api_operation" "apim_operation_openai_model_gateway_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation_policy.apim_policy_openai_model_gateway_get_deployment_by_name
  ]

  operation_id        = "list-deployments"
  api_name            = azurerm_api_management_api.openai_model_gateway.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  display_name        = "List Deployments"
  method              = "GET"
  url_template        = "/deployments"
}

## Create an policy for the list deployments operation to route to the Foundry APIM connection
##
resource "azurerm_api_management_api_operation_policy" "apim_policy_openai_model_gateway_list_deployments_by_name" {
  depends_on = [
    azurerm_api_management_api_operation.apim_operation_openai_model_gateway_list_deployments_by_name
  ]

  api_name            = azurerm_api_management_api.openai_model_gateway.name
  operation_id        = azurerm_api_management_api_operation.apim_operation_openai_model_gateway_list_deployments_by_name.operation_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  xml_content = <<XML
    <policies>
      <inbound>
        <authentication-managed-identity resource="https://management.azure.com/" />
        <rewrite-uri template="/deployments?api-version=${local.ai_services_arm_api_version}" copy-unmatched-params="false" />
        <!--Azure Resource Manager-->
        <set-backend-service base-url="https://management.azure.com${azurerm_cognitive_account.ai_foundry_accounts[keys(local.ai_foundry_regions)[0]].id}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

########### Create A records for the API Management instance in the Private DNS Zone
###########
###########

## Create A record for the API Management gateway custom domain in the Private DNS Zone
##
resource "azurerm_private_dns_a_record" "dns_a_record_apim_gateway" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_apim
  ]

  name                = "apim-example${var.random_string}"
  zone_name           = azurerm_private_dns_zone.private_dns_zone_apim.name
  resource_group_name = var.resource_group_dns
  ttl                 = 10

  records = [
    azurerm_api_management.apim.private_ip_addresses[0]
  ]
}

## Create A record for the API Management management custom domain in the Private DNS Zone
##
resource "azurerm_private_dns_a_record" "dns_a_record_apim_management" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_apim
  ]

  count = var.apim_generation_v2 ? 0 : 1

  name                = "apim-example${var.random_string}.management"
  zone_name           = azurerm_private_dns_zone.private_dns_zone_apim.name
  resource_group_name = var.resource_group_dns
  ttl                 = 10

  records = [
    azurerm_api_management.apim.private_ip_addresses[0]
  ]
}

## Create A record for the API Management developer portal custom domain in the Private DNS Zone
##
resource "azurerm_private_dns_a_record" "dns_a_record_apim_developer_portal" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_apim
  ]

  name                = "apim-example${var.random_string}.developer"
  zone_name           = azurerm_private_dns_zone.private_dns_zone_apim.name
  resource_group_name = var.resource_group_dns
  ttl                 = 10

  records = [
    azurerm_api_management.apim.private_ip_addresses[0]
  ]
}

## Create A record for the API Management source control manager custom domain in the Private DNS Zone
##
resource "azurerm_private_dns_a_record" "dns_a_record_apim_source_control_manager" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_apim
  ]

  count = var.apim_generation_v2 ? 0 : 1

  name                = "apim-example${var.random_string}.scm"
  zone_name           = azurerm_private_dns_zone.private_dns_zone_apim.name
  resource_group_name = var.resource_group_dns
  ttl                 = 10

  records = [
    azurerm_api_management.apim.private_ip_addresses[0]
  ]
}

## Create A record for the API Management split brain DNS zone to support use of the default name
## Only required if you care about that
resource "azurerm_private_dns_a_record" "dns_a_record_apim_split_brain" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_apim
  ]

  name                = "apim-example${var.random_string}${var.region_code}"
  zone_name           = "azure-api.net"
  resource_group_name = var.resource_group_dns
  ttl                 = 10

  records = [
    azurerm_api_management.apim.private_ip_addresses[0]
  ]
}

########### Create non-human role assignments
###########
###########

## Create Azure RBAC Role assignment granting the API Management managed identity
## the Azure OpenAI User role on the AI Foundry accounts. This can be used to demonstrate
## authentication offloading at the API Management layer.
resource "azurerm_role_assignment" "apim_perm_aifoundry_accounts_openai_user" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                 = uuidv5("dns", "${azurerm_api_management.apim.identity[0].principal_id}${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}openaiuser")
  scope                = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

## Create Azure RBAC Role assignment granting the API Management managed identity
## the Cognitive Services User role on the AI Foundry accounts. This is required to 
## list the deployments of the models to supoort the added operations for the APIM connection
resource "azurerm_role_assignment" "apim_perm_aifoundry_accounts_cognitive_services_user" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                 = uuidv5("dns", "${azurerm_api_management.apim.identity[0].principal_id}${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}cognitiveservicesuser")
  scope                = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

## Create Azure RBAC Role assignment granting the user provided service principal
## the Azure OpenAI User role on the AI Foundry accounts. This is only needed if 
## you are mucking with OBO and have created the appropriate app registration
resource "azurerm_role_assignment" "sp_perm_aifoundry_accounts_openai_user" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                 = uuidv5("dns", "${var.service_principal_object_id}${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}openaiuser")
  scope                = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.service_principal_object_id
}


########### Create human role-assignments
###########
###########

## Create Azure RBAC Role assignment granting the user the Azure OpenAI User role
## on the AI Foundry accounts. This can be used to demonstrate the OAuth On-Behalf-Of flow
resource "azurerm_role_assignment" "user_perm_aifoundry_accounts_openai_user" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = local.ai_foundry_regions

  name                 = uuidv5("dns", "${var.user_object_id}${azurerm_cognitive_account.ai_foundry_accounts[each.key].name}openaiuser")
  scope                = azurerm_cognitive_account.ai_foundry_accounts[each.key].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.user_object_id
}
