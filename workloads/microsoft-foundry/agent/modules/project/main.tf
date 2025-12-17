########## Create Foundry Project
##########
##########

## Create the Foundry project
##
resource "azapi_resource" "foundry_project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview"
  name                      = "sampleproject${var.project_number}"
  parent_id                 = var.foundry_resource_id
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
      displayName = "Sample Project ${var.project_number}"
      description = "This is sample AI Foundry project"
    }
  }

  # Output the principalId of the managed identity and internalId (which is the workspace ID behind the scenes) of the AI Foundry project
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
## This is only required if using system-assigned managed identity for the project
resource "time_sleep" "wait_project_identities" {
  count = var.project_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azapi_resource.foundry_project
  ]
  create_duration = "10s"
}

########## Create Foundry resource-level connections. This is only required if using BYOK and should be removed in the future
########## because it is required due to a bug in the service requiring a project be created before creating
########## the connection to the BYOK. This is only performed when the first_project variable is set to true
########## TODO: 12/2025 Move this to main Foundry resource template once PG fixes the issue

## Create a Foundry resource connection to the Key Vault used to store secrets for connections created within Foundry
## This is only required if var.byo_key_vault is set to true
resource "azapi_resource" "conn_resource_key_vault_secrets" {
  count = var.byo_key_vault && var.first_project == true ? 1 : 0

  depends_on = [
    azapi_resource.foundry_project
  ]

  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name                      = "${local.resource_byo_key_vault_name}1"
  parent_id                 = var.foundry_resource_id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "AzureKeyVault"
      isSharedToAll = true
      target   = "https://${local.resource_byo_key_vault_name}.vault.azure.net/"
      authType = "AccountManagedIdentity"
      credentials = {}
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_byo_key_vault_resource_id
        Location   = var.region
      }
    }
  }
}

## Create a Foundry resoure connection to the Application Insights instance to support tracing. This must be created after the connection to the Key Vault if using BYO Key Vault for secrets
##
resource "azapi_resource" "conn_resource_appins_foundry" {
  count = var.first_project == true ? 1 : 0

  depends_on = [
    azapi_resource.conn_resource_key_vault_secrets
  ]
    
  type                      = "Microsoft.CognitiveServices/accounts/connections@2025-10-01-preview"
  name                      = "${local.resource_app_insights_name}1"
  parent_id                 = var.foundry_resource_id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "AppInsights"
      isSharedToAll = true
      target   = var.shared_app_insights_resource_id
      authType = "ApiKey"

      credentials = {
        key = var.shared_app_insights_connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_app_insights_resource_id
      }
    }
  }
}

########## Create Foundry project-level connections to support the project capability host
##########
##########

## Create the Foundry project connection to CosmosDB
##
resource "azapi_resource" "conn_project_cosmosdb_foundry" {
  depends_on = [
    time_sleep.wait_project_identities,
    azapi_resource.conn_resource_key_vault_secrets
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.agent_cosmosdb_account_name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    name = local.agent_cosmosdb_account_name
    properties = {
      category = "CosmosDb"
      target   = var.shared_agent_cosmosdb_account_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_agent_cosmosdb_account_resource_id
        location   = var.region
      }
    }
  }
}

## Create the Foundry project connection to Azure Storage Account
##
resource "azapi_resource" "conn_project_storage_foundry" {
  depends_on = [
    time_sleep.wait_project_identities,
    azapi_resource.conn_resource_key_vault_secrets
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.agent_storage_account_name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    name = local.agent_storage_account_name
    properties = {
      category = "AzureStorageAccount"
      target   = var.shared_agent_storage_account_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_agent_storage_account_resource_id
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the Foundry project connection to AI Search
##
resource "azapi_resource" "conn_project_ai_search_foundry" {
  depends_on = [
    time_sleep.wait_project_identities,
    azapi_resource.conn_resource_key_vault_secrets
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.agent_ai_search_name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    name = local.agent_ai_search_name
    properties = {
      category = "CognitiveSearch"
      target   = "https://${local.agent_ai_search_name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-05-01-preview"
        ResourceId = var.shared_agent_ai_search_resource_id
        location   = var.region
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create a Foundry resource connection to the external Azure OpenAI Service or Foundry instance if that is specified in the external_openai variable
##
resource "azapi_resource" "conn_project_external_openai_foundry" {
  count = var.shared_external_openai != null ? 1 : 0

  depends_on = [
    azapi_resource.conn_resource_key_vault_secrets
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = var.shared_external_openai.name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    name = var.shared_external_openai.name
    properties = {
      category = "AzureOpenAI"
      isSharedToAll = true
      target   = var.shared_external_openai.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_external_openai.resource_id
        # As of 12/2025 the Azure OpenAI Service must be in the same region as the Foundry resource
        location = var.region
      }
    }
  }
}

########## Create Foundry project-level connections to support some of the built-in tools
##########
##########

## Create a Foundry project connection to the Bing Grounding Search instance
##
resource "azapi_resource" "conn_project_bing_grounding_search_foundry" {
  depends_on = [
    time_sleep.wait_project_identities,
    azapi_resource.conn_resource_key_vault_secrets
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = local.agent_bing_grounding_search_name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    name = local.agent_bing_grounding_search_name
    properties = {
      category = "GroundingWithBingSearch"
      target   = "https://api.bing.microsoft.com/"
      authType = "ApiKey"
      credentials = {
        key = var.shared_bing_grounding_search_api_key
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.shared_bing_grounding_search_resource_id
        type       = "bing_grounding"
      }
    }
  }
}

########## Create required non-human role assignments for the Foundry project system-managed identity to provision the project capability host
##########
##########

## Create a role assignment granting the CosmosDB Operator RBAC role on the CosmosDB account to the Foundry project system-managed identity
##
resource "azurerm_role_assignment" "cosmosdb_operator_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${local.agent_cosmosdb_account_name}${azapi_resource.foundry_project.output.identity.principalId}cosmosdboperator")
  scope                = var.shared_agent_cosmosdb_account_resource_id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.foundry_project.output.identity.principalId
}

## Create a role assignment granting the Storage Blob Data Contributor RBAC role on the Storage Account to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "storage_blob_data_contributor_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${local.agent_storage_account_name}${azapi_resource.foundry_project.output.identity.principalId}storageblobdatacontributor")
  scope                = var.shared_agent_storage_account_resource_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.foundry_project.output.identity.principalId
}

## Create a role assignment granting the Search Index Data Contributor RBAC role on the AI Search instance to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "search_index_data_contributor_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${local.agent_ai_search_name}${azapi_resource.foundry_project.output.identity.principalId}searchindexdatacontributor")
  scope                = var.shared_agent_ai_search_resource_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.foundry_project.output.identity.principalId
}

## Create a role assignment granting the Search Service Contributor RBAC role on the AI Search instance to the AI Foundry project managed identity
##
resource "azurerm_role_assignment" "search_service_contributor_foundry_project" {
  depends_on = [
    time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${local.agent_ai_search_name}${azapi_resource.foundry_project.output.identity.principalId}searchservicecontributor")
  scope                = var.shared_agent_ai_search_resource_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.foundry_project.output.identity.principalId
}

## Wait 120 seconds for the prior role assignments to be created and to replicate through Entra ID
##
resource "time_sleep" "wait_rbac" {
  depends_on = [
    ## The role assignments created for the system-assigned identity associated to the Foundry project
    azurerm_role_assignment.cosmosdb_operator_foundry_project,
    azurerm_role_assignment.storage_blob_data_contributor_foundry_project,
    azurerm_role_assignment.search_index_data_contributor_foundry_project,
    azurerm_role_assignment.search_service_contributor_foundry_project,
    ## The connection resources created for the Foundry project
    azapi_resource.conn_project_ai_search_foundry,
    azapi_resource.conn_project_cosmosdb_foundry,
    azapi_resource.conn_project_storage_foundry,
    azapi_resource.conn_project_bing_grounding_search_foundry
  ]
  create_duration = "120s"
}

########## Create the Foundry project capability host to support the standard agent deployment
##########
##########

## Create the Foundry project capability host
##
resource "azapi_resource" "foundry_project_capability_host" {
  depends_on = [
    # Wait for RBAC role assignments to propagate
    time_sleep.wait_rbac,
    # Wait for project-level connections
    azapi_resource.conn_project_ai_search_foundry,
    azapi_resource.conn_project_storage_foundry,
    azapi_resource.conn_project_cosmosdb_foundry,
    azapi_resource.conn_project_external_openai_foundry,
    azapi_resource.conn_project_bing_grounding_search_foundry,
    # Wait for resource-level connections
    azapi_resource.conn_resource_appins_foundry,
    azapi_resource.conn_resource_key_vault_secrets
  ]
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = "caphostproj"
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      vectorStoreConnections = [
        azapi_resource.conn_project_ai_search_foundry.name
      ]
      storageConnections = [
        azapi_resource.conn_project_storage_foundry.name
      ]
      threadStorageConnections = [
        azapi_resource.conn_project_cosmosdb_foundry.name
      ]

      # If using an external OpenAI resource, add that connection to the capability host
      aiServicesConnections = var.shared_external_openai != null ? azapi_resource.conn_project_external_openai_foundry[0].name : null
    }
  }
}

########## Create the required non-human role assignments for the AI Foundry project managed identity to access the CosmosDB account and Azure Storage data plane
########## 
##########

## Create an Azure RBAC role assignment granting the project system-managed identity the CosmosDB Built-in Data Contributor role
## on the CosmosDB account to allow data plane access
resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_account" {
  depends_on = [
    azapi_resource.foundry_project_capability_host
  ]
  name                = uuidv5("dns", "${local.agent_cosmosdb_account_name}${azapi_resource.foundry_project.output.identity.principalId}cosmosdbdatacontributor")
  resource_group_name = local.agent_cosmosdb_account_resource_group_name
  account_name        = local.agent_cosmosdb_account_name
  scope               = var.shared_agent_cosmosdb_account_resource_id
  role_definition_id  = "${var.shared_agent_cosmosdb_account_resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.foundry_project.output.identity.principalId
}

## Create the necessary data plane role assignments to the Azure Storage Account containers created by the AI Foundry Project
##
resource "azurerm_role_assignment" "storage_blob_data_owner_foundry_project" {
  depends_on = [
    azapi_resource.foundry_project_capability_host
  ]
  name                 = uuidv5("dns", "${local.agent_storage_account_name}${azapi_resource.foundry_project.output.identity.principalId}storageblobdataowner")
  scope                = var.shared_agent_storage_account_resource_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.foundry_project.output.identity.principalId
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

########## Create the required human role assignments to allow the user to perform common tasks within the Foundry project
########## 
##########

## Create a role assignment granting a user the Azure AI User role which will allow the user
## the ability to utilize the sample Foundry project
resource "azurerm_role_assignment" "foundry_user" {
  depends_on = [
    azapi_resource.foundry_project
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${local.foundry_resource_name}${azapi_resource.foundry_project.name}user")
  scope                = azapi_resource.foundry_project.id
  role_definition_name = "Azure AI User"
  principal_id         = var.user_object_id
}

