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

## Create a Private DNS Zone that be the namespace for the API Management instance
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

########### Create the AI Foundry Accounts and deploy the gpt4-o model
###########
###########

## Create AI Foundry accounts to act as the backends for the API Management instance
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
  tags = var.tags

  # Create an AI Foundry Account to support Foundry Projects
  kind = "AIServices"
  sku_name = "S0"
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

## Deploy GPT 4.1 model to the Foundry accounts
##
resource "azurerm_cognitive_deployment" "gpt4o_chat_model_deployments" {
  depends_on = [
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = azurerm_cognitive_account.ai_foundry_accounts

  name                 = "gpt-4o"
  cognitive_account_id = each.value.id

  sku {
    name     = "GlobalStandard"
    capacity = 100
  }

  model {
    format = "OpenAI"
    name   = "gpt-4o"
  }
}

## Create a diagnostic setting for the AI Foundry accounts to send logs to the Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aifoundry_accounts" {
  depends_on = [
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = azurerm_cognitive_account.ai_foundry_accounts

  name                       = "diag-base"
  target_resource_id         = each.value.id
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

  for_each = azurerm_cognitive_account.ai_foundry_accounts

  name                = "pe${each.value.name}account"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${each.value.name}account"

  private_service_connection {
    name                           = "peconn${each.value.name}account"
    private_connection_resource_id = each.value.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${each.value.name}account"
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
## This resource creation takes about 40 minutes
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
## This resource creation takes about 20 minutes
resource "azurerm_api_management_custom_domain" "apim_custom_domains" {
  depends_on = [
    time_sleep.sleep_apim_rbac
  ]

  api_management_id = azurerm_api_management.apim.id

  gateway {
    host_name                = "apim-example.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
    default_ssl_binding      = true
  }

  management {
    host_name                = "apim-example.management.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }

  scm {
    host_name                = "apim-example.scm.${var.apim_private_dns_zone_name}"
    key_vault_certificate_id = var.key_vault_secret_id_versionless
  }

  developer_portal {
    host_name                = "apim-example.developer.${var.apim_private_dns_zone_name}"
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
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = azurerm_cognitive_account.ai_foundry_accounts

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

########### Create an APIs in the API Management instance to expose the AI Foundry backends
###########
###########

## Create an API for the 2024-10-21 OpenAI Inferencing API
##
resource "azurerm_api_management_api" "openai_original" {
  depends_on = [
    azurerm_api_management_custom_domain.apim_custom_domains,
    module.backend_pool_aifoundry_instances
  ]

  name                = "azure-openai-original"
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Azure OpenAI Inferencing and Authoring API"
  path                = "openai"
  api_type            = "http"
  protocols           = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/api-specs/2024-10-21-openai-inference.json")
  }
}

## Create diagnostic setting for the OpenAI original API for Application Insights
##
resource "azurerm_api_management_api_diagnostic" "diag_openai_original_api_appinsights" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.rg_ai_gateway.name
  api_management_name      = azurerm_api_management.apim.name
  api_name                 = azurerm_api_management_api.openai_original.name
  api_management_logger_id = azurerm_api_management_logger.apim_logger_appinsights.id

  sampling_percentage = 100
  always_log_errors   = true
  log_client_ip       = true
  verbosity           = "information"
  http_correlation_protocol = "W3C"
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
      loggerId = "${azurerm_api_management.apim.id}/loggers/azuremonitor"
      alwaysLog = "allErrors"
      verbosity = "information"
      logClientIp = true
      sampling = {
        percentage = 100.0
        samplingType = "fixed"
      }
      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 262144
          messages = "all"
        }
        responses = {
          maxSizeInBytes = 262144
          messages = "all"
        }
      }
    }
  }
}

## Create an API for the v1 OpenAI API
##
resource "azurerm_api_management_api" "openai_v1" {
  depends_on = [
    azurerm_api_management_api.openai_original
  ]

  name                = "azure-openai-v1"
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Azure OpenAI v1 API"
  path                = "openai-v1"
  api_type            = "http"
  protocols           = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/api-specs/v1-azure-openai.json")
  }
}

## Create diagnostic setting for the OpenAI v1 API for Application Insights
##
resource "azurerm_api_management_api_diagnostic" "diag_openai_v1_api_appinsights" {
  depends_on = [
    azurerm_api_management_api.openai_v1
  ]

  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.rg_ai_gateway.name
  api_management_name      = azurerm_api_management.apim.name
  api_name                 = azurerm_api_management_api.openai_v1.name
  api_management_logger_id = azurerm_api_management_logger.apim_logger_appinsights.id

  sampling_percentage = 100
  always_log_errors   = true
  log_client_ip       = true
  verbosity           = "information"
  http_correlation_protocol = "W3C"
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
      loggerId = "${azurerm_api_management.apim.id}/loggers/azuremonitor"
      alwaysLog = "allErrors"
      verbosity = "information"
      logClientIp = true
      sampling = {
        percentage = 100.0
        samplingType = "fixed"
      }
      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 262144
          messages = "all"
        }
        responses = {
          maxSizeInBytes = 262144
          messages = "all"
        }
      }
    }
  }
}

########### Create an API Management Policies
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
          <set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("Authorization",string.Empty).Split(' ').Last().AsJwt().Claims.GetValueOrDefault("appid", "00000000-0000-0000-0000-000000000000"))" />
          <!-- Extract the deployment name from the uri path -->
          <set-variable name="uriPath" value="@(context.Request.OriginalUrl.Path)" />
          <set-variable name="deploymentName" value="@(System.Text.RegularExpressions.Regex.Match((string)context.Variables["uriPath"], "/deployments/([^/]+)").Groups[1].Value)" />
          <!-- Set the X-Entra-App-ID header to the Entra ID application ID from the JWT -->
          <set-header name="X-Entra-App-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("appId"))</value>
          </set-header>
          <!-- If the request is a ChatCompletion request validate that it contains UserSecurityContext. If it doesn't reject it with status code 400 -->
          <choose>
            <when condition="@(context.Operation.Id.ToLower() == "chatcompletions_create" &&
        (
          context.Request.Body?.As<JObject>(true)?["user_security_context"] == null ||
          context.Request.Body?.As<JObject>(true)?["user_security_context"]["end_user_id"] == null
        )
      )">
                  <return-response>
                      <set-status code="400" reason="Bad Request" />
                      <set-body>@("UserSecurityContext property is required for this operation.")</set-body>
                  </return-response>
              </when>
          </choose>
          <!-- Throttle token usage based on the appid -->
          <llm-token-limit counter-key="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
          <!-- Emit token metrics to Application Insights -->
          <llm-emit-token-metric namespace="openai-metrics">
              <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
              <dimension name="client_ip" value="@(context.Request.IpAddress)" />
              <dimension name="appId" value="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" />
          </llm-emit-token-metric>
          <set-backend-service backend-id="${module.backend_pool_aifoundry_instances.name}" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <base />
      </outbound>
      <!-- Handle exceptions and customize error responses  -->
      <on-error>
          <base />
          <set-header name="X-OperationName" exists-action="override">
              <value>@( context.Operation.Name )</value>
          </set-header>
          <set-header name="X-OperationMethod" exists-action="override">
              <value>@( context.Operation.Method )</value>
          </set-header>
          <set-header name="X-OperationUrl" exists-action="override">
              <value>@( context.Operation.UrlTemplate )</value>
          </set-header>
          <set-header name="X-ApiName" exists-action="override">
              <value>@( context.Api.Name )</value>
          </set-header>
          <set-header name="X-ApiPath" exists-action="override">
              <value>@( context.Api.Path )</value>
          </set-header>
          <set-header name="X-LastErrorMessage" exists-action="override">
              <value>@( context.LastError.Message )</value>
          </set-header>
          <set-header name="X-Entra-Id" exists-action="override">
              <value>@( context.Variables.GetValueOrDefault<string>("appId") )</value>
          </set-header>
      </on-error>
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
          <set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("Authorization",string.Empty).Split(' ').Last().AsJwt().Claims.GetValueOrDefault("appid", "00000000-0000-0000-0000-000000000000"))" />
          <!-- Extract the deployment name from the uri path -->
          <set-variable name="uriPath" value="@(context.Request.OriginalUrl.Path)" />
          <set-variable name="deploymentName" value="@(System.Text.RegularExpressions.Regex.Match((string)context.Variables["uriPath"], "/deployments/([^/]+)").Groups[1].Value)" />
          <!-- Set the X-Entra-App-ID header to the Entra ID application ID from the JWT -->
          <set-header name="X-Entra-App-ID" exists-action="override">
              <value>@(context.Variables.GetValueOrDefault<string>("appId"))</value>
          </set-header>
          <!-- If the request is a ChatCompletion request validate that it contains UserSecurityContext. If it doesn't reject it with status code 400 -->
          <choose>
              <when condition="@(context.Operation.Id.ToLower() == "createChatCompletion" &&
        (
          context.Request.Body?.As<JObject>(true)?["user_security_context"] == null ||
          context.Request.Body?.As<JObject>(true)?["user_security_context"]["end_user_id"] == null
        )
      )">
                  <return-response>
                      <set-status code="400" reason="Bad Request" />
                      <set-body>@("UserSecurityContext property is required for this operation.")</set-body>
                  </return-response>
              </when>
          </choose>
          <!-- Throttle token usage based on the appid -->
          <llm-token-limit counter-key="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" estimate-prompt-tokens="true" tokens-per-minute="10000" remaining-tokens-header-name="x-apim-remaining-token" tokens-consumed-header-name="x-apim-tokens-consumed" />
          <!-- Emit token metrics to Application Insights -->
          <llm-emit-token-metric namespace="openai-metrics">
              <dimension name="model" value="@(context.Variables.GetValueOrDefault<string>("deploymentName","None"))" />
              <dimension name="client_ip" value="@(context.Request.IpAddress)" />
              <dimension name="appId" value="@(context.Variables.GetValueOrDefault<string>("appId","00000000-0000-0000-0000-000000000000"))" />
          </llm-emit-token-metric>
          <set-backend-service backend-id="${module.backend_pool_aifoundry_instances.name}" />
      </inbound>
      <backend>
          <forward-request />
      </backend>
      <outbound>
          <base />
      </outbound>
      <!-- Handle exceptions and customize error responses  -->
      <on-error>
          <base />
          <set-header name="X-OperationName" exists-action="override">
              <value>@( context.Operation.Name )</value>
          </set-header>
          <set-header name="X-OperationMethod" exists-action="override">
              <value>@( context.Operation.Method )</value>
          </set-header>
          <set-header name="X-OperationUrl" exists-action="override">
              <value>@( context.Operation.UrlTemplate )</value>
          </set-header>
          <set-header name="X-ApiName" exists-action="override">
              <value>@( context.Api.Name )</value>
          </set-header>
          <set-header name="X-ApiPath" exists-action="override">
              <value>@( context.Api.Path )</value>
          </set-header>
          <set-header name="X-LastErrorMessage" exists-action="override">
              <value>@( context.LastError.Message )</value>
          </set-header>
          <set-header name="X-Entra-Id" exists-action="override">
              <value>@( context.Variables.GetValueOrDefault<string>("appId") )</value>
          </set-header>
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

  name                = "apim-example"
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

  name                = "apim-example.management"
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

  name                = "apim-example.developer"
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

  name                = "apim-example.scm"
  zone_name           = azurerm_private_dns_zone.private_dns_zone_apim.name
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

  for_each = azurerm_cognitive_account.ai_foundry_accounts

  name                 = uuidv5("dns", "${azurerm_api_management.apim.identity[0].principal_id}${each.value.name}openaiuser")
  scope                = each.value.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

## Create Azure RBAC Role assignment granting the user provided service principal
## the Azure OpenAI User role on the AI Foundry accounts. This can be used to demonstrate
## the OAuth client credentials flow
resource "azurerm_role_assignment" "sp_perm_aifoundry_accounts_openai_user" {
  depends_on = [
    azurerm_api_management.apim,
    azurerm_cognitive_account.ai_foundry_accounts
  ]

  for_each = azurerm_cognitive_account.ai_foundry_accounts

  name                 = uuidv5("dns", "${var.service_principal_object_id}${each.value.name}openaiuser")
  scope                = each.value.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.service_principal_object_id
}

########### Create human role-assignments
###########
###########

## Create Azure RBAC Role assignment graintg the user the Azure OpenAI User role
## on the AI Foundry accounts. This can be used to demonstrate the OAuth On-Behalf-Of flow
resource "azurerm_role_assignment" "user_perm_aifoundry_accounts_openai_user" {
    depends_on = [
      azurerm_api_management.apim,
      azurerm_cognitive_account.ai_foundry_accounts
    ]
  
    for_each = azurerm_cognitive_account.ai_foundry_accounts
  
    name                 = uuidv5("dns", "${var.user_object_id}${each.value.name}openaiuser")
    scope                = each.value.id
    role_definition_name = "Cognitive Services OpenAI User"
    principal_id         = var.user_object_id
  }