########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_foundry" {
  name     = "rgmsf${var.region_code}${var.random_string}"
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
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags = var.tags

  sku               = "PerGB2018"
  retention_in_days = 30

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create a Network Security Perimeter to protect service-to-service traffic between the Foundry resource, AI Search, Azure Storage Account, and optionally Key Vault
##########
##########

## Create Network Security Perimeter that will contain the Foundry resource, AI Search service, Storage Account, and optional Key Vaults for CMK
## 
resource "azapi_resource" "nsp_ai_resources" {
  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspai${var.region_code}${var.random_string}"
  location  = var.region
  parent_id = azurerm_resource_group.rg_foundry.id
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
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_ai_resources" {
  depends_on = [
    azapi_resource.nsp_ai_resources
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_ai_resources.id
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

## Create a Network Security Perimeter profile which will contain the Azure Key Vault used to store the CMK used to encrypt the Foundry instance if CMK encryption is used
##
resource "azapi_resource" "profile_nsp_foundry_key_vault_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azapi_resource.nsp_ai_resources
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pkvfoundrycmk"
  location  = var.region
  parent_id = azapi_resource.nsp_ai_resources.id
}

## Create an access rule to allow resources in the subscription access to the Key Vault. This is required to instantiate the resource with CMK during creation
##
resource "azapi_resource" "access_rule_foundry_key_vault_cmk_subscription" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azapi_resource.profile_nsp_foundry_key_vault_cmk
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arfoundrycmksub"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_foundry_key_vault_cmk[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      subscriptions = [
        {
          id = data.azurerm_subscription.current.id
        }
      ]
    }
  }
}

## LAB ONLY: Create an access rule to allow the trusted IP access to the data plane to validate the existance of the CMK
##
resource "azapi_resource" "access_rule_foundry_key_vault_cmk_ipprefix" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azapi_resource.access_rule_foundry_key_vault_cmk_subscription
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arfoundrycmkip"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_foundry_key_vault_cmk[0].id
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

## Create a Network Security Perimeter profile which will contain the Foundry resource. The AI Search service and Storage Account will be added to this profile if var.rag_pattern is true
##
resource "azapi_resource" "profile_nsp_foundry_ai_resources" {
  depends_on = [
    azapi_resource.nsp_ai_resources
  ]
  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pairesources"
  location  = var.region
  parent_id = azapi_resource.nsp_ai_resources.id
}

## LAB ONLY: Create an access rule to allow the trusted IP access to the data plane to validate the exist of the data container that is created
##
resource "azapi_resource" "access_rule_foundry_ai_resources_ipprefix" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azapi_resource.profile_nsp_foundry_ai_resources
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arairesourcesip"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_foundry_ai_resources.id
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

########## Create user-assigned managed identities for Foundry resource and AI Search
########## 
##########

## Create a user-assigned managed identity that will be assigned to the Foundry resource
## This identity will be used when accessing the Key Vault when using a CMK for encryption of the Foundry resource 
resource "azurerm_user_assigned_identity" "umi_foundry_resource" {
  count = var.resource_managed_identity_type == "umi" ? 1 : 0

  name                = "umimsf${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a user-assigned managed identity that will be assigned to the AI Search instance
## This identity will be used to access models within the Foundry resource, when using skillsets,
## to connect to Cognitive Services APIs and storage accounts in other regions (not within same region)
## TODO: 12/2025 The above comment should be edited to also specify all region when that limitation is lifted. Right now it requires an SMI to do this.
resource "azurerm_user_assigned_identity" "umi_ai_search" {
  count = var.rag_pattern ? 1 : 0

  name                = "umiais${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Sleep for 15 seconds to ensure the user-assigned managed identities replicate through Entra ID
##
resource "time_sleep" "wait_umi_foundry_resource" {
  count = var.resource_managed_identity_type == "umi" ? 1 : 0 || var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_foundry_resource,
    azurerm_user_assigned_identity.umi_ai_search
  ]
  create_duration = "15s"
}

########## Create optional Azure Key Vault and RSA key to support CMK encryption of the Foundry resource
########## if var.encryption is set to "cmk"
##########

## Create Azure Key Vault to store the CMK used to encrypt the Foundry instance
##
resource "azurerm_key_vault" "key_vault_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azapi_resource.profile_nsp_foundry_key_vault_cmk,
    azapi_resource.access_rule_foundry_key_vault_cmk_subscription,
    azapi_resource.access_rule_foundry_key_vault_cmk_ipprefix
  ]

  name                = "kvfoundrycmk${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  # Configure vault to support Azure RBAC-based authorization of data-plane
  rbac_authorization_enabled = true

  # Purge protection is required when storing CMKs
  purge_protection_enabled = true
  soft_delete_retention_days = 7

  # Configure network controls to block all public network access and restrict to Private Endpoints only. Network Security Perimeter will control access over Microsoft public backbone
  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Key Vault used to store the CMK
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_foundry_cmk[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Associate the Foundry resource with the Network Security Perimeter profile which includes the AI resources
##
resource "azapi_resource" "assoc_foundry_key_vault_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rafoundrykeyvaultcmk"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_ai_resources.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_key_vault.key_vault_foundry_cmk[0].id
      }
      profile = {
        id = azapi_resource.profile_nsp_foundry_key_vault_cmk[0].id
      }
    }
  }
}

## Create an Azure RBAC role assignment granting the AI Foundry user-assigned managed identity 
## the Key Vault Crypto User role on the Key Vault to allow use of the CMK. This is only required if 
## the managed identity type is 'umi' and encryption is set to 'cmk'
## TODO: 12/2025 Remove the first half of this condition once UMI with CMK is supported across all Azure regions
resource "azurerm_role_assignment" "umi_foundry_resource_cmk_key_vault_crypto_user" {
  count = var.resource_managed_identity_type == "umi" && var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk,
    time_sleep.wait_umi_foundry_resource
  ]

  scope                = azurerm_key_vault.key_vault_foundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.umi_foundry_resource[0].principal_id
}

## Sleep for 120 seconds to allow the Azure RBAC permissions to replicate across Azure
## This is only required if the managed identity type is 'umi' and encryption is set to 'cmk'
## TODO: 12/2025 Remove the first half of this condition once UMI with CMK is supported across all Azure regions
resource "time_sleep" "wait_key_vault_cmk_umi_rbac_replication" {
  count = var.resource_managed_identity_type == "umi" && var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk,
    azurerm_role_assignment.umi_foundry_resource_cmk_key_vault_crypto_user,
    azapi_resource.assoc_foundry_key_vault_cmk
  ]

  create_duration = "120s"
}

## Create RSA key in the Key Vault to be used as the CMK for the Foundry instance
##
resource "azurerm_key_vault_key" "key_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    time_sleep.wait_key_vault_cmk_umi_rbac_replication
  ]

  name         = "foundrycmk"
  key_vault_id = azurerm_key_vault.key_vault_foundry_cmk[0].id
  key_type     = "RSA"
  # As of 10/2025 Foundry only supports 2048 bit keys
  key_size = 2048
  key_opts = ["decrypt", "encrypt", "sign", "verify", "wrapKey", "unwrapKey"]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

######### Create Private Endpoints for optional Key Vault resource used to store CMK and Key Vault resource to store secrets for connections
#########
#########

## Create Private Endpoint for the Key Vault used to store the CMK for Foundry encryption
## This is only required if var.encryption is set to "cmk"
resource "azurerm_private_endpoint" "pe_key_vault_cmk_foundry" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk
  ]

  name                          = "pe${azurerm_key_vault.key_vault_foundry_cmk[0].name}kv"
  location                      = var.region
  resource_group_name           = azurerm_resource_group.rg_foundry.name
  tags                          = var.tags
  subnet_id                     = var.subnet_id_private_endpoints
  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_foundry_cmk[0].name}kv"
  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_foundry_cmk[0].name}kv"
    private_connection_resource_id = azurerm_key_vault.key_vault_foundry_cmk[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_foundry_cmk[0].name}kv"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }
}

######### Create the Foundry resource that will host models and other Cognitive Services only
#########
#########

## Create the Foundry account and configure it to use VNet injection to support BYO VNet
##
resource "azurerm_cognitive_account" "foundry_resource" {
  depends_on = [
    # Wait for user-assigned managed identity creation and permissioning
    time_sleep.wait_umi_foundry_resource,
    time_sleep.wait_key_vault_cmk_umi_rbac_replication,
    ## Wait for creation of optional Key Vault if using CMK
    azurerm_key_vault.key_vault_foundry_cmk,
    azurerm_key_vault_key.key_foundry_cmk,
    azapi_resource.assoc_foundry_key_vault_cmk,
    ## Wait for creation of optional Private Endpoint for Key Vault if using CMK
    azurerm_private_endpoint.pe_key_vault_cmk_foundry
  ]

  name                = "msf${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = merge(var.tags, { SecurityControl = "Ignore" })

  # Create an AI Foundry resource
  kind                       = "AIServices"
  sku_name                   = "S0"
  project_management_enabled = true
 
  # Ensure local authentication is still enabled to support features such as AI Search embeddings skillset
  local_auth_enabled = true

  # Assigned a system-assigned managed identity or user-assigned managed identity based on variable
  identity {
    type = var.resource_managed_identity_type == "umi" ? "UserAssigned" : "SystemAssigned"
    identity_ids = var.resource_managed_identity_type == "umi" ? [
      azurerm_user_assigned_identity.umi_foundry_resource[0].id
    ] : null
  }

  # Set the Foundry resource to use a CMK if the var.foundry_encryption is set to "cmk"
  # TODO: 12/2025 Remove the second half of this condition once UMI with CMK is supported across all Azure regions
  dynamic "customer_managed_key" {
    for_each = var.foundry_encryption == "cmk" && var.resource_managed_identity_type == "umi" ? [1] : []

    content {
      key_vault_key_id   = azurerm_key_vault_key.key_foundry_cmk[0].id
      identity_client_id = azurerm_user_assigned_identity.umi_foundry_resource[0].client_id
    }
  }

  # Set custom subdomain name for DNS names created for this Foundry resource
  custom_subdomain_name = "msf${var.region_code}${var.random_string}"

  # Configure network controls to block all public network access and restrict to Private Endpoints only. Network Security Perimeter will control access over Microsoft public backbone
  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"],
      #TODO: 12/2025 Remove the following line once UMI with CMK is supported across all Azure regions because it is only necessary working around SMI usage
      customer_managed_key
    ]
  }
}

## Create diagnostic settings for AI Foundry resource
##
resource "azurerm_monitor_diagnostic_setting" "diag_foundry_resource" {
  depends_on = [
    azurerm_cognitive_account.foundry_resource
  ]

  name                       = "diag"
  target_resource_id         = azurerm_cognitive_account.foundry_resource.id
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

## Associate the Foundry resource with the Network Security Perimeter profile which includes the AI resources
##
resource "azapi_resource" "assoc_foundry_resource" {
  depends_on = [
    azurerm_cognitive_account.foundry_resource,
    azapi_resource.profile_nsp_foundry_ai_resources
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rafoundryresource"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_ai_resources.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_cognitive_account.foundry_resource.id
      }
      profile = {
        id = azapi_resource.profile_nsp_foundry_ai_resources.id
      }
    }
  }
}

######### Create additional role assignments for the Foundry SMI when the managed identity type is 'smi'
######### and enable CMK when var.foundry_encryption is set to 'cmk'
######### TODO: 12/2025 Remove this section once UMI with CMK is supported across all Azure regions

## Wait 10 seconds for the creation of the AI Foundry resource system-managed identity to replicate through Entra ID 
##
resource "time_sleep" "wait_smi_foundry" {
  count = var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azurerm_cognitive_account.foundry_resource
  ]
  create_duration = "10s"
}

## Create an Azure RBAC role assignment granting the AI Foundry system-assigned managed identity 
## the Key Vault Crypto User role on the Key Vault to allow use of the CMK.
##
resource "azurerm_role_assignment" "smi_foundry_cmk_key_vault_crypto_user" {
  count = var.resource_managed_identity_type == "smi" && var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    time_sleep.wait_smi_foundry
  ]

  scope                = azurerm_key_vault.key_vault_foundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_cognitive_account.foundry_resource.identity[0].principal_id
}

## Sleep for 120 seconds to allow the Azure RBAC permissions to replicate across Azure
##
resource "time_sleep" "wait_key_vault_cmk_smi_rbac_replication" {
  count = var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.smi_foundry_cmk_key_vault_crypto_user
  ]

  create_duration = "120s"
}

## Modify the Foundry resource to use a CMK in Key Vault if var.foundry_encryption is set to "cmk"
##
resource "azurerm_cognitive_account_customer_managed_key" "foundry_cmk" {
  count = var.foundry_encryption == "cmk" && var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    time_sleep.wait_key_vault_cmk_smi_rbac_replication
  ]

  cognitive_account_id = azurerm_cognitive_account.foundry_resource.id
  key_vault_key_id     = azurerm_key_vault_key.key_foundry_cmk[0].id
}

######### Create deployments of models in the Foundry resource
#########
#########

# Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "deployment_gpt_4o" {
  depends_on = [
    azurerm_cognitive_account.foundry_resource,
    azurerm_cognitive_account_customer_managed_key.foundry_cmk
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.foundry_resource.id

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

## Create a deployment for the text-embedding-ada-002 embededing model
##
resource "azurerm_cognitive_deployment" "deployment_text-embedding-ada-002" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt_4o
  ]

  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.foundry_resource.id

  sku {
    name     = "GlobalStandard"
    capacity = 300
  }

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = 2
  }
}

## Create a deployment for the text-embedding-3-large embededing model
##
resource "azurerm_cognitive_deployment" "deployment_text_embedding_3_large" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_text-embedding-ada-002
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.foundry_resource.id

  sku {
    name     = "GlobalStandard"
    capacity = 400
  }

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = 1
  }
}

## Create Private Endpoint for Foundry resource
##
resource "azurerm_private_endpoint" "pe_foundry_resource" {
  depends_on = [
    azurerm_cognitive_account.foundry_resource,
    azurerm_cognitive_account_customer_managed_key.foundry_cmk,
    azurerm_cognitive_deployment.deployment_text_embedding_3_large
  ]

  name                = "pe${azurerm_cognitive_account.foundry_resource.name}resource"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_cognitive_account.foundry_resource.name}resource"

  private_service_connection {
    name                           = "peconn${azurerm_cognitive_account.foundry_resource.name}resource"
    private_connection_resource_id = azurerm_cognitive_account.foundry_resource.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_cognitive_account.foundry_resource.name}account"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create additional AI Search and Azure Storage Account to support chat with your data use cases
########## 
##########

## Create an AI Search service where vector stores can be created if using the chat with your data workload in 
## Foundry to ingest data into AI Search
resource "azurerm_search_service" "ai_search_foundry" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    # Wait on user-assigned managed identity creation and replication
    azurerm_user_assigned_identity.umi_ai_search,
    time_sleep.wait_umi_foundry_resource,
    # Wait on Network Security Perimeter resources
    azapi_resource.profile_nsp_foundry_ai_resources
  ]

  name                = "aismsf${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = var.tags

  # Associate the AI Search instance with the user-assigned managed identity created earlier
  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_ai_search[0].id
    ]
  }

  # Use Standard SKU to support most popular features
  sku             = "standard"
  hosting_mode    = "default"
  replica_count   = 1
  partition_count = 1
  semantic_search_sku = "standard"

  # Support both Entra ID authentication and API authentication
  local_authentication_enabled = true
  authentication_failure_mode  = "http401WithBearerChallenge"

  # Disable public access and restrict to Private Endpoints only. Network Security Perimeter will control access over Microsoft public backbone
  public_network_access_enabled = false

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
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_search_service.ai_search_foundry
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_search_service.ai_search_foundry[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "OperationLogs"
  }
}

## Associate the AI Search service which is used to create indexes to the Network Security Perimeter
##
resource "azapi_resource" "assoc_foundry_ai_search" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_search_service.ai_search_foundry
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raaisearchfoundry"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_ai_resources.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_search_service.ai_search_foundry[0].id
      }
      profile = {
        id = azapi_resource.profile_nsp_foundry_ai_resources.id
      }
    }
  }

}

## Create a storage account which will store any files uploaded by developers or end users for flows which
## allow for uploaded data
resource "azurerm_storage_account" "storage_account_foundry" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    # Wait on Network Security Perimeter resources
    azapi_resource.profile_nsp_foundry_ai_resources
  ]

  name                = "stmsf${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = var.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  # Disable public access and restrict to Private Endpoints only. Network Security Perimeter will control access over Microsoft public backbone
  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Configure diagnostic settings for blob, file, queue, and table services to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_foundry_blob" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_foundry[0].id}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_foundry_file" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azurerm_monitor_diagnostic_setting.diag_storage_foundry_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_foundry[0].id}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_foundry_queue" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azurerm_monitor_diagnostic_setting.diag_storage_foundry_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_foundry[0].id}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_foundry_table" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azurerm_monitor_diagnostic_setting.diag_storage_foundry_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_foundry[0].id}/tableServices/default"
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

## Associate the Key Vault used to store secrets for connections with the Network Security Perimeter profile
##
resource "azapi_resource" "assoc_foundry_storage_account" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azapi_resource.assoc_foundry_ai_search
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rastorageaccountfoundry"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_ai_resources.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_storage_account.storage_account_foundry[0].id
      }
      profile = {
        id = azapi_resource.profile_nsp_foundry_ai_resources.id
      }
    }
  }
}

## Sleep for 30 seconds to allow the Network Security Perimeter assocation to take effect
##
resource "time_sleep" "wait_nsp_assoc_foundry_storage_account" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azapi_resource.assoc_foundry_storage_account
  ]

  create_duration = "30s"
}

## Create a container in the storage account to hold blobs that will be used to demonstrate the AI Search skillsets
##
resource "azurerm_storage_container" "container_foundry_ai_search_skillsets" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    time_sleep.wait_nsp_assoc_foundry_storage_account,
    azapi_resource.assoc_foundry_storage_account
  ]

  name                  = "data"
  storage_account_id    = azurerm_storage_account.storage_account_foundry[0].id
  container_access_type = "private"
}

########## Create Private Endpoints for Foundry Standard Agent resources
##########
##########

## Create Private Endpoint for the AI Foundry AI Search instance used for the chat with your data workload
##
resource "azurerm_private_endpoint" "pe_aisearch_foundry" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_search_service.ai_search_foundry
  ]

  name                = "pe${azurerm_search_service.ai_search_foundry[0].name}searchservice"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_search_service.ai_search_foundry[0].name}searchservice"

  private_service_connection {
    name                           = "peconn${azurerm_search_service.ai_search_foundry[0].name}searchservice"
    private_connection_resource_id = azurerm_search_service.ai_search_foundry[0].id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_search_service.ai_search_foundry[0].name}searchservice"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Private Endpoint for the AI Foundry storage account used for the chat with your data workload
##
resource "azurerm_private_endpoint" "pe_storage_blob_foundry" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_aisearch_foundry,
    azurerm_storage_account.storage_account_foundry
  ]

  name                = "pe${azurerm_storage_account.storage_account_foundry[0].name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_foundry[0].name}blob"
  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_foundry[0].name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_foundry[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_foundry[0].name}blob"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Non-human role assignments
########## Create the necessary role assignments to support using skill sets in AI Search in combination with embedding models in Foundry
##########

## Create an Azure RBAC role assignment on the Foundry resource granting the AI Search service user-assigned managed identity the Cognitive Services OpenAI User role
## This allows it to call the embedding models to vectorize the data when using AI Search skillset to build and maintain indexes
##
resource "azurerm_role_assignment" "cognitive_services_openai_user_ai_search_service" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_cognitive_account.foundry_resource,
    azurerm_search_service.ai_search_foundry
  ]
  name                 = uuidv5("dns", "${azurerm_search_service.ai_search_foundry[0].identity[0].principal_id}${azurerm_cognitive_account.foundry_resource.name}openaiuser")
  scope                = azurerm_cognitive_account.foundry_resource.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_search_service.ai_search_foundry[0].identity[0].principal_id
}

## Create an Azure RBAC role assignment on the Foundry resourc granting the AI Search user-assigned managed identity the Cognitive Services User role 
## This allows it to call other Cognitive Services APIs if needed when using AI Search skillsets
##
resource "azurerm_role_assignment" "cognitive_services_user_ai_search_service" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_cognitive_account.foundry_resource,
    azurerm_role_assignment.cognitive_services_openai_user_ai_search_service,
    azurerm_search_service.ai_search_foundry
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_ai_search[0].principal_id}${azurerm_cognitive_account.foundry_resource.name}cogservicesuser")
  scope                = azurerm_cognitive_account.foundry_resource.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.umi_ai_search[0].principal_id
}

## Create an Azure RBAC role assignment on the Storage Account granting the AI Search service system-assigned managed identity the Storage Blob Data Reader role
## TODO: 12/2025: Switch this to UMI once the limitation of using SMIs for a storage account in the same region is lifted
##
resource "azurerm_role_assignment" "storage_blob_data_reader_ai_search_service" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azurerm_search_service.ai_search_foundry
  ]

  name                 = uuidv5("dns", "${azurerm_search_service.ai_search_foundry[0].identity[0].principal_id}${azurerm_storage_account.storage_account_foundry[0].name}blobdatareader")
  scope                = azurerm_storage_account.storage_account_foundry[0].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.ai_search_foundry[0].identity[0].principal_id
}

########## Create a project for the use of the chat playground and other playgrounds. This is not suited for agents
##########
##########
module "foundry_project" {
  depends_on = [
    # Wait for creation of Foundry resource
    azurerm_cognitive_account.foundry_resource,
    azurerm_private_endpoint.pe_foundry_resource,
    # Wait for creation of standard agent resource
    azurerm_search_service.ai_search_foundry,
    azurerm_storage_account.storage_account_foundry,
    azurerm_private_endpoint.pe_aisearch_foundry,
    azurerm_private_endpoint.pe_storage_blob_foundry,
    # Wait for conditional resources
    azurerm_private_endpoint.pe_key_vault_cmk_foundry,
    time_sleep.wait_key_vault_cmk_smi_rbac_replication
  ]

  source              = "./modules/project"
  foundry_resource_id = azurerm_cognitive_account.foundry_resource.id
  foundry_resource_resource_group_id   = azurerm_resource_group.rg_foundry.id
  region              = var.region
  project_number      = 1

  # User object id to grant permissions over project
  user_object_id = var.user_object_id
}

########## Create human role assignments
########## Create the necessary role assignments to support the Foundry Chat Playground and AI Search skillsets to build indexes
########## This includes building indexes with AI Search or with the Foundry chat playground

## Create an Azure RBAC role assignment on the AI Search service granting a user the Search Service Contributor role
## This allows the user to create, delete, and managed indexes in AI Search. This is used for both building the indexes
## in the Foundry chat playground or using AI Search skillsets to build indexes interactively
resource "azurerm_role_assignment" "aisearch_user_service_contributor" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_search_service.ai_search_foundry
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azurerm_search_service.ai_search_foundry[0].name}servicecont")
  scope                = azurerm_search_service.ai_search_foundry[0].id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.user_object_id
}

## Create an Azure RBAC role assignment on the AI Search service granting a user the Search Index Data Contributor role
## This allows the user to create, modify, and delete documents in indexes in AI Search. This is used for both building the indexes
## in the Foundry chat playground or using AI Search skillsets to build indexes interactively
resource "azurerm_role_assignment" "aisearch_user_data_contributor" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_role_assignment.aisearch_user_service_contributor
  ]
  name                 = uuidv5("dns", "${var.user_object_id}${azurerm_search_service.ai_search_foundry[0].name}datacont")
  scope                = azurerm_search_service.ai_search_foundry[0].id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.user_object_id
}

## Create an Azure RBAC role assignment on the Storage Account granting a user the Storage Blob Data Contributor role
## This allows the user to read and write data to the storage account. This is used for both building the indexes
## in the Foundry chat playground or using AI Search skillsets to build indexes interactively
resource "azurerm_role_assignment" "storage_blob_data_contributor_user" {
  count = var.rag_pattern ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azurerm_storage_account.storage_account_foundry[0].name}blobdatacontributor")
  scope                = azurerm_storage_account.storage_account_foundry[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}

## Create an Azure RBAC role assignment on the Foundry resource granting a user the Cognitive Services User role
## This allows the user to use other Cognitive Services such as the Speech API
resource "azurerm_role_assignment" "cognitive_services_user" {
  depends_on = [
    azurerm_cognitive_account.foundry_resource
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${azurerm_cognitive_account.foundry_resource.name}cognitiveservicesuser")
  scope                = azurerm_cognitive_account.foundry_resource.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.user_object_id
}
