########## Create a resource group for the AML Registries
########## 
##########

## Create resource group where resources in this template will be deployed to
##
resource "azurerm_resource_group" "rg_ai_gateway" {
  provider = azurerm.subscription_workload_production

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

## Create a Private DNS Zone that be the namespace for the API Management instance
##
resource "azurerm_private_dns_zone" "zone" {
  depends_on = [
    rg_ai_gateway
  ]

  name                = var.apim_private_dns_zone_name
  resource_group_name = rg_ai_gateway.name
  tags                = var.tags

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

########### Create the API Management instance and its dependent resources
###########
###########

## Create a public IP address for API Management instance if customer wishes to manage it in their subscription.
## Otherwise the public IP is managed by Microsoft and is not visible in the subscription.
resource "azurerm_public_ip" "pip_apim" {
  count = var.customer_managed_public_ip ? 1 : 0

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
  for_each = var.customer_managed_public_ip ? { for idx, region in var.regions_additional : region.region => region } : {}

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
##
resource "azurerm_api_management" "apim" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_application_insights.appins_api_management,
    azurerm_public_ip.pip_apim,
    azurerm_public_ip.pip_apim_additional_regions
  ]
  name                = "apim${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = var.tags

  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email
  sku_name        = var.sku

  # Assign a customer-managed public IP if requested, otherwise leave null to have Microsoft manage the public IP
  public_ip_address_id = var.customer_managed_public_ip ? azurerm_public_ip.pip_apim[0].id : null

  # Create an internal-mode API Management instance
  virtual_network_type = "Internal"

  # Create multi-region API Management Gateways if additional regions have been specified
  dynamic "additional_location" {
    for_each = var.regions_additional != null ? var.regions_additional : []
    content {
      location             = each.value.region
      public_ip_address_id = var.customer_managed_public_ip ? azurerm_public_ip.pip_apim_additional_regions[each.value.region].id : null
      virtual_network_configuration {
        subnet_id = each.value.subnet_id
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

  name                       = "diag-base"
  target_resource_id         = azurerm_api_management.apim.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

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
##
resource "azurerm_api_management_custom_domain" "apim_custom_domains" {
  depends_on = [
    time_sleep.sleep_apim_rbac
  ]

  api_management_id = azurerm_api_management.apim.id

  gateway {
    host_name                = "apim${var.random_string}.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }

  management {
    host_name                = "apim${var.random_string}.management.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }

  scm {
    host_name                = "apim${var.random_string}.scm.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }

  developer_portal {
    host_name                = "apim${var.random_string}.developer.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }
}

########### Create the API Management backends with circuit breakers and backend pools
###########
###########

## Create circuit breaker backends for AI Foundry instances
##
module "backend_circuit_breaker_aifoundry_instance" {
  depends_on = [
    azurerm_api_management.apim
  ]

  for_each = {
    for foundry_name in var.ai_foundry_instances :
    foundry_name => {
      name = "foundry-backend-${foundry_name}"
    }
  }

  source       = "./modules/backend-circuit-breaker"
  apim_id      = azurerm_api_management.apim.id
  backend_name = each.value.name
  url          = "https://${each.value.name}.openai.azure.com/openai"
}

## Create backend pool with AI Foundry backends
##
module "backend_pool_aifoundry_instances" {
  depends_on = [
    module.backend_circuit_breaker_aifoundry_instance
  ]

  source    = "./modules/backend-pool"
  pool_name = "foundry-pool"
  apim_id   = azurerm_api_management.apim.id

  backends = [
    for foundry_backend in module.backend_circuit_breaker_aifoundry_instance :
    {
      id       = foundry_backend.id
      priority = 1
    }
  ]
}

########### Create an APIs in the API Management instance to expose the AI Foundry backends
###########
###########

## Create an API for the 2024-10-21 OpenAI Inferencing API
##
resource "azurerm_api_management_api" "example" {
  depends_on = [
    module.backend_pool_aifoundry_instances
  ]

  name                = "azure-openai-original"
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Azure OpenAI Inferencing and Authoring API"
  path                = "openai"
  protocols           = ["https"]
  import {
    content_format = "swagger-link-json"
    content_value  = "https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/refs/heads/main/internal/services/apimanagement/testdata/api_management_api_schema_swagger.json"
  }
}