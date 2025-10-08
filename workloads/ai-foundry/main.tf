########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_aifoundry" {
  name     = "rgaif${var.region_code}${var.random_string}"
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
  name                = "law${var.purpose}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name

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

##########  Create resources required by the AI Foundry resource to support Standard Agents with Virtual Network Injection
##########
##########

## Create Cosmos DB account to store agent threads.
## DB account will support DocumentDB API and will have diagnostic settings enabled
## Deployed to one region with no failover to reduce costs
resource "azurerm_cosmosdb_account" "cosmosdb_aifoundry" {
  name                = "cosaif${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags                = var.tags

  # General settings
  offer_type        = "Standard"
  kind              = "GlobalDocumentDB"
  free_tier_enabled = false

  # Set security-related settings
  local_authentication_disabled = true
  public_network_access_enabled = false

  # Set high availability and failover settings
  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false

  # Configure consistency settings
  consistency_policy {
    consistency_level = "Session"
  }

  # Configure single location with no zone redundancy to reduce costs
  geo_location {
    location          = var.region
    failover_priority = 0
    zone_redundant    = false
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Cosmos DB account
##
resource "azurerm_monitor_diagnostic_setting" "diag_cosmosdb" {
  depends_on = [
    azurerm_cosmosdb_account.cosmosdb_aifoundry
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_cosmosdb_account.cosmosdb_aifoundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "MongoRequests"
  }

  enabled_log {
    category = "QueryRuntimeStatistics"
  }

  enabled_log {
    category = "PartitionKeyStatistics"
  }

  enabled_log {
    category = "PartitionKeyRUConsumption"
  }

  enabled_log {
    category = "ControlPlaneRequests"
  }

  enabled_log {
    category = "CassandraRequests"
  }

  enabled_log {
    category = "GremlinRequests"
  }

  enabled_log {
    category = "TableApiRequests"
  }
}

## Create an AI Search service where vector stores can be created if using the chat with your data workload in 
## AI Foundry to ingest data into AI Search
resource "azapi_resource" "ai_search_aifoundry" {
  type                      = "Microsoft.Search/searchServices@2024-03-01-preview"
  name                      = "aisaif${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aifoundry.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    sku = {
      name = "standard"
    }

    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # Search-specific properties
      replicaCount   = 1
      partitionCount = 1
      hostingMode    = "default"
      semanticSearch = "standard"

      # Identity-related controls
      disableLocalAuth = false
      authOptions = {
        aadOrApiKey = {
          aadAuthFailureMode = "http401WithBearerChallenge"
        }
      }
      # Networking-related controls
      publicNetworkAccess = "disabled"
      networkRuleSet = {
        bypass = "AzureServices"
      }
    }
    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Azure AI Search service
##
resource "azurerm_monitor_diagnostic_setting" "diag_ai_search" {
  depends_on = [
    azapi_resource.ai_search_aifoundry
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.ai_search_aifoundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "OperationLogs"
  }
}

## Create a storage account which will store any files uploaded by developers or end users for flows which
## allow for uploaded data
resource "azurerm_storage_account" "storage_account_aifoundry" {
  name                = "staif${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  location            = var.region
  tags                = var.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"

    # Configure bypass if bypass isn't an empty list
    bypass = ["AzureServices", "Metrics", "Logging"]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Configure diagnostic settings for blob, file, queue, and table services to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_aifoundry_blob" {

  depends_on = [
    azurerm_storage_account.storage_account_aifoundry
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aifoundry.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aifoundry_file" {
  depends_on = [
    azurerm_storage_account.storage_account_aifoundry,
    azurerm_monitor_diagnostic_setting.diag_storage_aifoundry_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aifoundry.id}/fileServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aifoundry_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_aifoundry,
    azurerm_monitor_diagnostic_setting.diag_storage_aifoundry_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aifoundry.id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aifoundry_table" {

  depends_on = [
    azurerm_storage_account.storage_account_aifoundry,
    azurerm_monitor_diagnostic_setting.diag_storage_aifoundry_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aifoundry.id}/tableServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

########## Create optional Azure Key Vault and RSA key to support CMK encryption of the AI Foundry resource
########## if var.encryption is set to "cmk"
########## As of 10/2025 Foundry does not support UMI-based access of CMK so SMI must be used

## Create Azure Key Vault to store the CMK used to encrypt the Foundry instance
##
resource "azurerm_key_vault" "key_vault_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  name                = "kvfoundrycmk${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags = var.tags

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  # Configure vault to support Azure RBAC-based authorization of data-plane
  rbac_authorization_enabled = true

  soft_delete_retention_days  = 7
  # Purge protection is required when storing CMKs
  purge_protection_enabled    = true

  network_acls {
    default_action = "Deny"
    # Azure Trusted Services bypass is required for consumption of CMK
    bypass         = "AzureServices"
    # Allow Terraform deployment server IP network access to data plane. Only required for this lab
    ip_rules       = [
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

## Create RSA key in the Key Vault to be used as the CMK for the Foundry instance
##
resource "azurerm_key_vault_key" "key_foundry_cmk" {
  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk
  ]

  count = var.foundry_encryption == "cmk" ? 1 : 0

  name         = "foundrycmk"
  key_vault_id = azurerm_key_vault.key_vault_foundry_cmk[0].id
  key_type     = "RSA"
  # As of 10/2025 Foundry only supports 2048 bit keys
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "verify", "wrapKey", "unwrapKey"]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create optional resources to support the AI Foundry resource and Standard Agents
##########
##########

## Create Application Insights instance to be used by the AI Foundry resource
##
resource "azurerm_application_insights" "appins_foundry" {
  name                = "appinsaif${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
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

## Create Grounding Search with Bing
##
resource "azapi_resource" "bing_grounding_search_foundry" {
  type                      = "Microsoft.Bing/accounts@2020-06-10"
  name                      = "bingaif${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aifoundry.id
  location                  = "global"
  schema_validation_enabled = false

  body = {
    sku = {
      name = "G1"
    }
    kind = "Bing.Grounding"
  }
}

########## Create Private Endpoints for BYO Standard Agent resources
##########
##########

## Create Private Endpoint for the AI Foundry CosmosDB account used for the standard agent configuration
##
resource "azurerm_private_endpoint" "pe_cosmosdb_aifoundry" {
  depends_on = [
    azurerm_cosmosdb_account.cosmosdb_aifoundry
  ]

  name                = "pe${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}cosmossql"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}cosmossql"

  private_service_connection {
    name                           = "peconn${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}cosmossql"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmosdb_aifoundry.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}cosmossql"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Private Endpoint for the AI Foundry AI Search instance used for the standard agent configuration
##
resource "azurerm_private_endpoint" "pe_aisearch_aifoundry" {
  depends_on = [
    azurerm_private_endpoint.pe_cosmosdb_aifoundry,
    azapi_resource.ai_search_aifoundry
  ]

  name                = "pe${azapi_resource.ai_search_aifoundry.name}searchservice"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.ai_search_aifoundry.name}searchservice"

  private_service_connection {
    name                           = "peconn${azapi_resource.ai_search_aifoundry.name}searchservice"
    private_connection_resource_id = azapi_resource.ai_search_aifoundry.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.ai_search_aifoundry.name}searchservice"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Private Endpoint for the AI Foundry storage account used for the standard agent configuration
##
resource "azurerm_private_endpoint" "pe_storage_blob_aifoundry" {
  depends_on = [
    azurerm_private_endpoint.pe_aisearch_aifoundry,
    azurerm_storage_account.storage_account_aifoundry
  ]

  name                = "pe${azurerm_storage_account.storage_account_aifoundry.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_aifoundry.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_aifoundry.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_aifoundry.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_aifoundry.name}blob"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 60 seconds to allow creation of Application Insights resource to replicate
## Application Insight instances created and integrated with Log Analytics can take time to replicate the resource
resource "time_sleep" "wait_appins" {
  depends_on = [
    azurerm_application_insights.appins_foundry
  ]
  create_duration = "60s"
}

######### Create the Azure AI Foundry deployment that supports Standard Agents
#########
#########

## Create the Azure Foundry account and configure it to use VNet injection to support BYO VNet
##
resource "azapi_resource" "ai_foundry_account" {
  depends_on = [
    azapi_resource.bing_grounding_search_foundry,
    azurerm_private_endpoint.pe_aisearch_aifoundry,
    azurerm_private_endpoint.pe_cosmosdb_aifoundry,
    azurerm_private_endpoint.pe_storage_blob_aifoundry,
    azurerm_key_vault_key.key_foundry_cmk,
    time_sleep.wait_appins
  ]

  type                      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name                      = "aif${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aifoundry.id
  location                  = var.region
  tags                      = var.tags
  schema_validation_enabled = false

  body = {
    kind = "AIServices",
    sku = {
      name = "S0"
    }

    # Assign a system-assigned managed identity to the AI Foundry account. 
    # 9/2025 User-assigned managed identities are pretty useless because they're not yet supported for CMK access
    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # This property specifies the creation of an AI Foundry account vs an AI Services account
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = "aif${var.region_code}${var.random_string}"

      # Network-related controls
      # Disable public access but allow Trusted Azure Services exception
      publicNetworkAccess = "Disabled"
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
      }

      # Enable VNet injection for Standard Agents
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = var.subnet_id_agent
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  # Output the principalId of the managed identity and custom subdomain of the AI Foundry account
  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AI Foundry resource
##
resource "azurerm_monitor_diagnostic_setting" "diag_foundry_resource" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]

  name                       = "diag"
  target_resource_id         = azapi_resource.ai_foundry_account.id
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

## Wait 10 seconds for the creation of the AI Foundry managed identity to replicate through Entra ID
##
resource "time_sleep" "wait_foundry_identity" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]
  create_duration = "10s"
}

## Create a role assignment granting the AI Foundry account managed identity the Key Vault Crypto User role which will allow the Foundry account
## to access the CMK in the Key Vault if var.foundry_encryption is set to "cmk"
##
resource "azurerm_role_assignment" "foundry_key_vault_crypto_user" {
  depends_on = [
    time_sleep.wait_foundry_identity
  ]

  count = var.foundry_encryption == "cmk" ? 1 : 0

  principal_id   = azapi_resource.ai_foundry_account.output.identity.principalId
  role_definition_name = "Key Vault Crypto User"
  scope          = azurerm_key_vault.key_vault_foundry_cmk[0].id
}

## Wait 120 seconds for the role assignment to replicate through Azure RBAC
##
resource "time_sleep" "wait_foundry_account_rbac" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.foundry_key_vault_crypto_user
  ]
  create_duration = "120s"
}

## Modify the Azure AI Foundry account to use a CMK in Key Vault if var.foundry_encryption is set to "cmk"
##
resource "azurerm_cognitive_account_customer_managed_key" "ai_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    time_sleep.wait_foundry_account_rbac
  ]

  cognitive_account_id = azapi_resource.ai_foundry_account.id
  key_vault_key_id     = azurerm_key_vault_key.key_foundry_cmk[0].id
}

# Create a deployment for OpenAI's GPT-4o if var.external_openai is not set
##
resource "azurerm_cognitive_deployment" "deployment_gpt_4o" {
  depends_on = [
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk
  ]

  count = var.external_openai != null ? 0 : 1

  name                 = "gpt-4o"
  cognitive_account_id = azapi_resource.ai_foundry_account.id

  sku {
    name     = "GlobalStandard"
    capacity = 100
  }

  model {
    format = "OpenAI"
    name   = "gpt-4o"
  }
}

## Create a deployment for the text-embedding-3-large embededing model if var.external_openai is not set
##
resource "azurerm_cognitive_deployment" "deployment_text_embedding_3_large" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt_4o
  ]

  count = var.external_openai != null ? 0 : 1

  name                 = "text-embedding-3-large"
  cognitive_account_id = azapi_resource.ai_foundry_account.id

  sku {
    name     = "GlobalStandard"
    capacity = 50
  }

  model {
    format = "OpenAI"
    name   = "text-embedding-3-large"
  }
}

## Create Private Endpoint for AI Foundry account
##
resource "azurerm_private_endpoint" "pe_aifoundry_account" {
  depends_on = [
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk,
    azurerm_cognitive_deployment.deployment_text_embedding_3_large
  ]

  name                = "pe${azapi_resource.ai_foundry_account.name}account"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.ai_foundry_account.name}account"

  private_service_connection {
    name                           = "peconn${azapi_resource.ai_foundry_account.name}account"
    private_connection_resource_id = azapi_resource.ai_foundry_account.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.ai_foundry_account.name}account"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create AI Foundry Project, connections to CosmosDB, AI Search, Storage Account, Grounding Search with Bing, and Application Insights
##########
##########

## Create the AI Foundry project
##
resource "azapi_resource" "ai_foundry_project" {
  depends_on = [
    azurerm_private_endpoint.pe_aifoundry_account
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name                      = "sampleproject1"
  parent_id                 = azapi_resource.ai_foundry_account.id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {
      displayName = "Sample Project 1"
      description = "This is sample AI Foundry project"
    }
  }

  # Output the principalId of the managed identity and internalId (which is the workspace ID behind the scenes) of the AI Foundry project
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the AI Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
resource "time_sleep" "wait_project_identities" {
  depends_on = [
    azapi_resource.ai_foundry_project
  ]
  create_duration = "10s"
}

## Create the AI Foundry project connection to CosmosDB
##
resource "azapi_resource" "conn_cosmosdb_aifoundry" {
  depends_on = [
    time_sleep.wait_project_identities
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "conn-${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    name = azurerm_cosmosdb_account.cosmosdb_aifoundry.name
    properties = {
      category = "CosmosDB"
      target   = azurerm_cosmosdb_account.cosmosdb_aifoundry.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.cosmosdb_aifoundry.id
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the AI Foundry project connection to Azure Storage Account
##
resource "azapi_resource" "conn_storage_aifoundry" {
  depends_on = [
    time_sleep.wait_project_identities
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "conn-${azurerm_storage_account.storage_account_aifoundry.name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    name = azurerm_storage_account.storage_account_aifoundry.name
    properties = {
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.storage_account_aifoundry.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.storage_account_aifoundry.id
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the AI Foundry project connection to AI Search
##
resource "azapi_resource" "conn_aisearch_aifoundry" {
  depends_on = [
    time_sleep.wait_project_identities
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "conn-${azapi_resource.ai_search_aifoundry.name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    name = azapi_resource.ai_search_aifoundry.name
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azapi_resource.ai_search_aifoundry.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-05-01-preview"
        ResourceId = azapi_resource.ai_search_aifoundry.id
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the AI Foundry project connection to the Bing Grounding Search instance
##
resource "azapi_resource" "conn_bing_grounding_search_aifoundry" {
  depends_on = [
    time_sleep.wait_project_identities
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "conn-${azapi_resource.bing_grounding_search_foundry.name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    name = azapi_resource.bing_grounding_search_foundry.name
    properties = {
      category = "GroundingWithBingSearch"
      target   = "https://api.bing.microsoft.com/"
      authType = "ApiKey"
      credentials = {
        key = data.azapi_resource_action.bing_api_keys.output.key1
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.bing_grounding_search_foundry.id
        type = "bing_grounding"
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}
  
## Create the AI Foundry project connection to the external Azure OpenAI Service or Foundry instance if that is specified in the external_openai variable
##
resource "azapi_resource" "conn_external_openai_aifoundry" {
  depends_on = [
    time_sleep.wait_project_identities,
  ]

  count = var.external_openai != null ? 1 : 0
  

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "conn-${var.external_openai.name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    name = var.external_openai.name
    properties = {
      category = "AzureOpenAI"
      target   = var.external_openai.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.external_openai.resource_id
        # As of 10/2025 the Azure OpenAI Service must be in the same region as the AI Foundry resource
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

########## Create required non-human role assignments for the AI Foundry project managed identity to provision the project capability host
##########
##########

## Create a role assignment granting the CosmosDB Operator RBAC role on the CosmosDB account to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "cosmosdb_operator_ai_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}cosmosdboperator")
  scope                = azurerm_cosmosdb_account.cosmosdb_aifoundry.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Create a role assignment granting the Storage Blob Data Contributor RBAC role on the Storage Account to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aifoundry.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Create a role assignment granting the Search Index Data Contributor RBAC role on the AI Search instance to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "search_index_data_contributor_ai_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_search_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}searchindexdatacontributor")
  scope                = azapi_resource.ai_search_aifoundry.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Create a role assignment granting the Search Service Contributor RBAC role on the AI Search instance to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "search_service_contributor_ai_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_search_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}searchservicecontributor")
  scope                = azapi_resource.ai_search_aifoundry.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Wait 60 seconds for the prior role assignments to be created and to replicate through Entra ID
##
resource "time_sleep" "wait_rbac" {
  depends_on = [
    azurerm_role_assignment.cosmosdb_operator_ai_foundry_project,
    azurerm_role_assignment.storage_blob_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_index_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_service_contributor_ai_foundry_project,
    azapi_resource.conn_aisearch_aifoundry,
    azapi_resource.conn_cosmosdb_aifoundry,
    azapi_resource.conn_storage_aifoundry,
    azapi_resource.conn_external_openai_aifoundry,
    azapi_resource.conn_bing_grounding_search_aifoundry
  ]
  create_duration = "120s"
}

########## Create the AI Foundry project capability host to support the standard agent deployment
##########
##########

## Create the AI Foundry project capability host
##
resource "azapi_resource" "ai_foundry_project_capability_host" {
  depends_on = [
    time_sleep.wait_rbac
  ]
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = "caphostproj"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      vectorStoreConnections = [
        azapi_resource.conn_aisearch_aifoundry.name
      ]
      storageConnections = [
        azapi_resource.conn_storage_aifoundry.name
      ]
      threadStorageConnections = [
        azapi_resource.conn_cosmosdb_aifoundry.name
      ]

      # If using an external OpenAI resource, add that connection to the capability host
      aiServicesConnections = var.external_openai != null ? azapi_resource.conn_external_openai_aifoundry[0].name: null
    }
  }
}

########## Create the required non-human role assignments for the AI Foundry project managed identity to access the CosmosDB account and Azure Storage data plane
########## 
##########

## Create the necessary data plane role assignments to the CosmosDb databases created by the AI Foundry Project
##
resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_user_thread_message_store" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                = uuidv5("dns", "${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}userthreadmessage_dbsqlrole")
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  account_name        = azurerm_cosmosdb_account.cosmosdb_aifoundry.name
  scope               = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/dbs/enterprise_memory/colls/${local.formatted_guid}-thread-message-store"
  role_definition_id  = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_system_thread_name" {
  depends_on = [
    azurerm_cosmosdb_sql_role_assignment.cosmosdb_db_sql_role_aifp_user_thread_message_store
  ]
  name                = uuidv5("dns", "${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}systemthread_dbsqlrole")
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  account_name        = azurerm_cosmosdb_account.cosmosdb_aifoundry.name
  scope               = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/dbs/enterprise_memory/colls/${local.formatted_guid}-system-thread-message-store"
  role_definition_id  = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_entity_store_name" {
  depends_on = [
    azurerm_cosmosdb_sql_role_assignment.cosmosdb_db_sql_role_aifp_system_thread_name
  ]
  name                = uuidv5("dns", "${azurerm_cosmosdb_account.cosmosdb_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}entitystore_dbsqlrole")
  resource_group_name = azurerm_resource_group.rg_aifoundry.name
  account_name        = azurerm_cosmosdb_account.cosmosdb_aifoundry.name
  scope               = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/dbs/enterprise_memory/colls/${local.formatted_guid}-agent-entity-store"
  role_definition_id  = "${azurerm_cosmosdb_account.cosmosdb_aifoundry.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Create the necessary data plane role assignments to the Azure Storage Account containers created by the AI Foundry Project
##
resource "azurerm_role_assignment" "storage_blob_data_owner_ai_foundry_project" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aifoundry.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_resource_group.rg_aifoundry.name}storageblobdataowner")
  scope                = azurerm_storage_account.storage_account_aifoundry.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
  condition_version    = "2.0"
  condition            = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) 
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) 
    ) 
    OR 
    (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.formatted_guid}' 
    AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent')
  )
  EOT
}

########## Create required human role assignments to allow a user to perform commmon operations in AI Foundry
##########
##########

## Create a role assignment granting a user the Azure AI User role which will allow the user
## the ability to utilize the sample AI Foundry project
resource "azurerm_role_assignment" "ai_foundry_user" {
  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azapi_resource.ai_foundry_account.name}${azapi_resource.ai_foundry_project.name}user")
  scope                = azapi_resource.ai_foundry_project.id
  role_definition_name = "Azure AI User"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Cognitive Services User role which will allow the user
## to use the various Playgrounds such as the Speech Playground
resource "azurerm_role_assignment" "cognitive_services_user" {
  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azapi_resource.ai_foundry_account.name}${azapi_resource.ai_foundry_project.name}cognitiveservicesuser")
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.user_object_id
}

########## Create optional non-human and non-human role assignments to support import and vectorize feature of AI Search
########## This won't work out of the box if you try to do this with the GUI because the GUI is customized to
########## only support Azure OpenAI Resources. The skillset JSON needs to be modified to support AI Foundry

## Create a role assignment granting the AI Search service managed identity the Cognitive Services OpenAI User role which will allow the AI Search service
## to call the OpenAI models deployed in the AI Foundry account to vectorize data
##
resource "azurerm_role_assignment" "cognitive_services_openai_contributor_ai_search_service" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_search_aifoundry.output.identity.principalId}${azapi_resource.ai_foundry_account.name}openaiuser")
  scope                = azapi_resource.ai_foundry_account.id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = azapi_resource.ai_search_aifoundry.output.identity.principalId
}

## Create a role assignment granting the AI Search service the Storage Blob Data Contributor role which will allow the AI Search service
## to read files from the storage account used by the AI Foundry project
## This is required to support the import and vectorize feature of AI Search
resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_search_service" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${azapi_resource.ai_search_aifoundry.output.identity.principalId}${azurerm_storage_account.storage_account_aifoundry.name}blobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aifoundry.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.ai_search_aifoundry.output.identity.principalId
}

## Create a role assignment granting a user the Search Service Contributor role which will allow the user
## to create and manage indexes in the AI Search Service
resource "azurerm_role_assignment" "aisearch_user_service_contributor" {
  depends_on = [
    azapi_resource.ai_search_aifoundry
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azapi_resource.ai_search_aifoundry.name}servicecont")
  scope                = azapi_resource.ai_search_aifoundry.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Search Index Data Contributor role which will allow the user
## to create new records in existing indexes in an AI Search Service
resource "azurerm_role_assignment" "aisearch_user_data_contributor" {
  depends_on = [
    azurerm_role_assignment.aisearch_user_service_contributor
  ]
  name                 = uuidv5("dns", "${var.user_object_id}${azapi_resource.ai_search_aifoundry.name}datacont")
  scope                = azapi_resource.ai_search_aifoundry.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.user_object_id
}

########## Extra code that can help to purge the AI Foundry account during destroy. The AzApi provider doesn't
########## support purging the AI Foundry account during destroy operations
##########

## Added AI Foundry account purger to avoid running into InUseSubnetCannotBeDeleted-lock caused by the agent subnet delegation.
## The azapi_resource_action.purge_ai_foundry (only gets executed during destroy) purges the AI foundry account removing /subnets/snet-agent/serviceAssociationLinks/legionservicelink so the agent subnet can get properly removed.
## Credit for this to Sebastian Graf
resource "azapi_resource_action" "purge_ai_foundry" {
  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.region}/resourceGroups/${azurerm_resource_group.rg_aifoundry.name}/deletedAccounts/aifoundry${var.random_string}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"
}
