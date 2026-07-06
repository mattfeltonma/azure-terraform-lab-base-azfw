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

## Create a Log Analytics Workspace where diagnostic logs and metrics for the resources deployed in this workload will be sent to
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawmsf${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags

  sku               = "PerGB2018"
  retention_in_days = 30

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create a Network Security Perimeter to protect service-to-service traffic between the Microsoft Foundry resource, AI Search, Azure Storage Account, and optionally Key Vault
##########
##########

## Create Network Security Perimeter that will contain the Foundry resource, AI Search service, Storage Account, and optional Key Vaults for CMK and secrets if provisioned
## 
resource "azurerm_network_security_perimeter" "nsp_ai_resources" {
  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "nspai${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = var.tags

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
    azurerm_network_security_perimeter.nsp_ai_resources,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_network_security_perimeter.nsp_ai_resources.id
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

## !BYOKEYVAULT
## !AGENTS
## Create the Network Security Perimeter profile which will contain the Azure Key Vault used to store
## connection secrets for the Foundry resource
resource "azurerm_network_security_perimeter_profile" "profile_nsp_foundry_key_vault_secrets" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_resources
  ]

  name                          = "pkvfoundrysecrets"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_ai_resources.id
}

## !LAB
## !BYOKEYVAULT
## !AGENTS
## Create a Network Security Perimeter access rule to allow my lab IP address access to the Key Vault data plane
##
resource "azurerm_network_security_perimeter_access_rule" "access_rule_foundry_key_vault_secrets_ipprefix" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_secrets
  ]

  name                                  = "arfoundrysecretsip"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_secrets[0].id
  direction                             = "Inbound"
  address_prefixes = [
    "${var.trusted_ip}/32"
  ]
}

## !CMK
## Create a Network Security Perimeter profile which will contain the Azure Key Vault used to store the CMK when CMK encryption
## is used for the Foundry resource
##
resource "azurerm_network_security_perimeter_profile" "profile_nsp_foundry_key_vault_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_resources
  ]

  name                          = "pkvfoundrycmk"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_ai_resources.id
}

## !CMK
## Create a Network Security Perimeter access rule to allow resources in the subscription access to the Key Vault. 
## This is required to instantiate the resource with CMK during creation
##
resource "azurerm_network_security_perimeter_access_rule" "access_rule_foundry_key_vault_cmk_subscription" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_cmk
  ]

  name                                  = "arfoundrycmksub"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_cmk[0].id
  direction                             = "Inbound"
  subscription_ids = [
    "/subscriptions/${var.subscription_id_infrastructure}"
  ]

}

## !LAB
## !CMK
## Create a Network Security Perimeter access rule to allow the trusted IP access to the Key Vault data plane for terraform redeploys
##
resource "azurerm_network_security_perimeter_access_rule" "access_rule_foundry_key_vault_cmk_ipprefix" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_cmk_subscription
  ]

  name                                  = "arfoundrycmkip"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_cmk[0].id
  direction                             = "Inbound"
  address_prefixes = [
    "${var.trusted_ip}/32"
  ]
}

## TODO: 6/2026 CosmosDB support is still in public preview so it isn't added to this profile; remove this comment when it goes GA
## !CONTENTUNDERSTANDING
## !AGENTS
## Create a Network Security Perimeter profile which will contain the Foundry resource, AI Search instance, CosmosDB instance (agents), and Azure Storage Account (agents)
##
resource "azurerm_network_security_perimeter_profile" "profile_nsp_foundry_ai_resources" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_resources
  ]

  name                          = "pairesources"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_ai_resources.id
}

## Create a Network Security Perimeter profile which will contain the Foundry resource
## 
resource "azurerm_network_security_perimeter_profile" "profile_nsp_foundry_ms_foundry" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_resources
  ]

  name                          = "pmsfoundryres"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_ai_resources.id
}

########## Create user-assigned managed identities for Foundry resource and AI Search
########## 
##########

## !UMI
## Create a user-assigned managed identity that will be assigned to the Foundry resource
## This identity will be used in instances like CMK encryption or accessing secrets with the BYO Key Vault for connection secret feature
##
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

## !CONTENTUNDERSTANDING
## !AGENTS
## TODO: 6/2026 Remove this comment when the UMI restrictions are lifted. Restrictions includes inability to use UMI to interact with storage account in same region. 
## TODO: 6/2026 See this link: https://learn.microsoft.com/en-us/azure/search/search-how-to-managed-identities?tabs=portal-sys%2Cportal-user#supported-scenarios
## Create a user-assigned managed identity that will be assigned to the AI Search instance
## This identity will be used to access models within the Foundry resource when using specific features in
## AI Search such as creating embeddings as part of the Knowledge Sources feature
##
resource "azurerm_user_assigned_identity" "umi_ai_search" {
  count = var.deploy_content_understanding_resources || var.agents ? 1 : 0

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

## !UMI
## !CONTENTUNDERSTANDING
## !AGENTS
## Sleep for 15 seconds to ensure the user-assigned managed identity replicates through Entra ID
##
resource "time_sleep" "wait_umi_foundry_resource" {
  count = var.deploy_content_understanding_resources || var.agents || var.resource_managed_identity_type == "umi" ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_foundry_resource,
    azurerm_user_assigned_identity.umi_ai_search
  ]
  create_duration = "15s"
}

########## Create resources to support BYO Key Vault for connection secrets
########## 
##########

## !BYOKEYVAULT
## !AGENTS
## Create an Azure Key Vault to store secrets for connections created within Foundry that use key-based authentication
##
resource "azurerm_key_vault" "key_vault_foundry_secrets" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_secrets_ipprefix
  ]

  name                = "kvmsfsec${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name

  # !LAB
  tags = merge(var.tags, { SecurityControl = "Ignore" })

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  # Configure vault to support Azure RBAC-based authorization of data-plane
  rbac_authorization_enabled = true

  # !LAB
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # TODO: 6/2026 Set public network access to false and remove the network_acls section once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  public_network_access_enabled = true
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []
    # !LAB
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

## !BYOKEYVAULT
## !AGENTS
## Create diagnostic settings for the Key Vault used to store secrets for connections created within Foundry
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_foundry_secrets" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_secrets
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_foundry_secrets[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## !BYOKEYVAULT
## !AGENTS
## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Microsoft Foundry resource
## the Key Vault Secrets Officer role on the Key Vault to allow management of secrets
##
resource "azurerm_role_assignment" "umi_foundry_resource_secrets_key_vault_secrets_officer" {
  count = var.resource_managed_identity_type == "umi" && var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    time_sleep.wait_umi_foundry_resource
  ]

  scope                = azurerm_key_vault.key_vault_foundry_secrets[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.umi_foundry_resource[0].principal_id
}

## !BYOKEYVAULT
## !AGENTS
## Associate the Key Vault used to store secrets for connections with the Network Security Perimeter profile
##
resource "azurerm_network_security_perimeter_association" "assoc_foundry_key_vault_secrets" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0
  depends_on = [
    azurerm_key_vault.key_vault_foundry_secrets
  ]

  name = "rapkvfoundrysecrets"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_secrets[0].id
  resource_id                           = azurerm_key_vault.key_vault_foundry_secrets[0].id
}

## !BYOKEYVAULT
## !AGENTS
## Sleep for 120 seconds to allow the Azure RBAC permissions to replicate across Azure
##
resource "time_sleep" "wait_key_vault_secrets_umi_rbac_replication" {
  count = var.resource_managed_identity_type == "umi" && var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_foundry_resource_secrets_key_vault_secrets_officer
  ]

  create_duration = "120s"
}

########## Create resources to support Foundry resource CMK encryption
########## 
##########

## !CMK
## Create Azure Key Vault to store the CMK used to encrypt the Foundry instance
##
resource "azurerm_key_vault" "key_vault_foundry_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_cmk,
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_cmk_ipprefix
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
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # TODO: 6/2026 Set public network access to false and remove the network_acls section once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  public_network_access_enabled = true
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []
    # !LAB
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

## !CMK
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

## !CMK
## Associate the Key Vault used to store the CMK with the Network Security Perimeter profile
## 
resource "azurerm_network_security_perimeter_association" "assoc_foundry_key_vault_cmk" {
  count = var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk
  ]

  name                                  = "rapkvfoundrycmk"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_key_vault_cmk[0].id
  resource_id                           = azurerm_key_vault.key_vault_foundry_cmk[0].id
}

## !UMI
## !CMK
## Create an Azure RBAC role assignment granting the Microsoft Foundry user-assigned managed identity 
## the Key Vault Crypto User role on the Key Vault to allow use of the CMK
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

## !UMI
## !CMK
## Sleep for 120 seconds to allow the Azure RBAC permissions to replicate across Azure
##
resource "time_sleep" "wait_key_vault_cmk_umi_rbac_replication" {
  count = var.resource_managed_identity_type == "umi" && var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_cmk,
    azurerm_role_assignment.umi_foundry_resource_cmk_key_vault_crypto_user,
    azurerm_network_security_perimeter_association.assoc_foundry_key_vault_cmk
  ]

  create_duration = "120s"
}

## !CMK
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
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "verify", "wrapKey", "unwrapKey"]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create Application Insights instance for agent tracing
########## 
##########

## !AGENTS
## Create Application Insights instance that will be used by all projects in the Foundry resource for agent tracing
##
resource "azurerm_application_insights" "appins_foundry" {
  count = var.agents ? 1 : 0

  name                = "appinsmsf${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  application_type    = "web"
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## !AGENTS
## Pause for 60 seconds to allow creation of Application Insights resource to replicate
## Application Insight instances created and integrated with Log Analytics can take time to replicate the resource
##
resource "time_sleep" "wait_appins" {
  count = var.agents ? 1 : 0

  depends_on = [
    azurerm_application_insights.appins_foundry
  ]
  create_duration = "60s"
}

########## Create Grounding with Bing Custom Search resoure to support advanced WebSearch use cases
########## with Foundry agents like domain filtering
##########

## !AGENTS
## Create a Grounding with Bing Custom Search resource
##
resource "azapi_resource" "bing_grounding_custom_search_foundry" {
  count = var.agents ? 1 : 0

  type                      = "Microsoft.Bing/accounts@2020-06-10"
  name                      = "bingmsf${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_foundry.id
  location                  = "global"
  schema_validation_enabled = false

  body = {
    sku = {
      name = "G2"
    }
    kind = "Bing.GroundingCustomSearch"
  }
}

######### Create Private Endpoints for optional Key Vault resources used to store CMK and connection secrets
#########
#########

## !BYOKEYVAULT
## !AGENTS
## Create Private Endpoint for the Key Vault used to store secrets for connections created within Foundry
## 
##
resource "azurerm_private_endpoint" "pe_key_vault_secrets_foundry" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_secrets
  ]

  name                          = "pe${azurerm_key_vault.key_vault_foundry_secrets[0].name}kv"
  location                      = var.region
  resource_group_name           = azurerm_resource_group.rg_foundry.name
  tags                          = var.tags
  subnet_id                     = var.subnet_id_private_endpoints
  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_foundry_secrets[0].name}kv"
  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_foundry_secrets[0].name}kv"
    private_connection_resource_id = azurerm_key_vault.key_vault_foundry_secrets[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_foundry_secrets[0].name}kv"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }
}

## !CMK
## Create Private Endpoint for the Key Vault used to store the CMK for Foundry encryption
##
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

######### Create Foundry resource, diagnostic settings, and associate with Network Security Perimeter
######### 
######### TODO: 6/2026 Switch to azurerm when it fully supports all required options

## Create the Microsoft Foundry resource/account
## 
resource "azapi_resource" "foundry_resource" {
  depends_on = [
    # Wait for user-assigned managed identity creation and permissioning
    time_sleep.wait_umi_foundry_resource,
    time_sleep.wait_key_vault_secrets_umi_rbac_replication,
    time_sleep.wait_key_vault_cmk_umi_rbac_replication,
    ## Wait for creation of optional Private Endpoints if using CMK or BYO Key Vault
    azurerm_private_endpoint.pe_key_vault_cmk_foundry,
    azurerm_private_endpoint.pe_key_vault_secrets_foundry,
    ## Wait for creation of optional resources used to support agent tool usage and tracing
    time_sleep.wait_appins,
    azapi_resource.bing_grounding_custom_search_foundry,
    ## Wait for creation of optional Key Vaults and CMK if configured
    azurerm_key_vault.key_vault_foundry_secrets,
    azurerm_key_vault.key_vault_foundry_cmk,
    azurerm_network_security_perimeter_association.assoc_foundry_key_vault_secrets,
    azurerm_network_security_perimeter_association.assoc_foundry_key_vault_cmk,
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_secrets_ipprefix,
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_cmk_ipprefix,
    azurerm_network_security_perimeter_access_rule.access_rule_foundry_key_vault_cmk_subscription
  ]

  type                      = "Microsoft.CognitiveServices/accounts@2026-05-01"
  name                      = "msf${var.region_code}${var.random_string}"
  location                  = var.region
  parent_id                 = azurerm_resource_group.rg_foundry.id
  schema_validation_enabled = false

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    # !UMI
    # Configure UMI or SMI for the Foundry resource based on the variable value
    identity = var.resource_managed_identity_type == "umi" ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.umi_foundry_resource[0].id) = {}
      }
      } : {
      type                   = "SystemAssigned"
      userAssignedIdentities = null
    }
    properties = {

      # Specify this is an MS Foundry resource
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = "msf${var.region_code}${var.random_string}"

      # !CMK
      # Set encryption with CMK if configured otherwise use a PMK
      encryption = var.foundry_encryption == "cmk" && var.resource_managed_identity_type == "umi" ? {
        keySource = "Microsoft.KeyVault"
        keyVaultProperties = {
          keyName          = azurerm_key_vault_key.key_foundry_cmk[0].name
          keyVaultUri      = azurerm_key_vault.key_vault_foundry_cmk[0].vault_uri
          keyVersion       = azurerm_key_vault_key.key_foundry_cmk[0].version
          identityClientId = azurerm_user_assigned_identity.umi_foundry_resource[0].client_id
        }
      } : null

      # Network-related controls

      # TODO: 6/2026 Set public network access to Disabled and remove the network_acls section once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
      publicNetworkAccess = "Enabled"
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
        ipRules = []
        virtualNetworkRules = []
      }

      # !VNETINJECTION
      # !MANAGEDVNET
      # For Standard Agents either configure VNet injection or managed virtual network
      networkInjections = var.agent_service_outbound_networking.type != "none" ? [
        {
          scenario                   = "agent"
          subnetArmId                = var.agent_service_outbound_networking.type == "vnet_injection" ? var.agent_service_outbound_networking.subnet_id : null
          useMicrosoftManagedNetwork = var.agent_service_outbound_networking.type == "managed_virtual_network" ? true : false
        }
      ] : null
    }
    # !LAB
    tags = merge(var.tags, { SecurityControl = "Ignore" })
  }

  lifecycle {
    ignore_changes = [
      body["properties"]["tags"]["created_date"],
      body["properties"]["tags"]["created_by"]
    ]
  }
}

## Create diagnostic settings for the Microsoft Foundry resource
##
resource "azurerm_monitor_diagnostic_setting" "diag_foundry_resource" {
  depends_on = [
    azapi_resource.foundry_resource
  ]

  name                       = "diag"
  target_resource_id         = azapi_resource.foundry_resource.id
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

## Associate the Microsoft Foundry resource with the Network Security Perimeter profile
##

resource "azurerm_network_security_perimeter_association" "assoc_foundry_resource" {
  depends_on = [
    azapi_resource.foundry_resource,
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_ms_foundry
  ]

  name = "assocfoundryresource"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_ms_foundry.id
  resource_id                           = azapi_resource.foundry_resource.id
}

######### Create additional role assignments for the Foundry resource system-assigned managed identity if a 
######### user-assigned managed identity isn't used.
#########
######### Enable CMK after Foundry resource is created if using a system-assigned managed identity. This can't be done
######### beforehand unless using a user-assigned managed identity
#########

## !SMI
## Wait 10 seconds for the creation of the Microsoft Foundry resource system-managed identity to replicate through Entra ID 
##
resource "time_sleep" "wait_smi_foundry" {
  count = var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azapi_resource.foundry_resource
  ]
  create_duration = "10s"
}

## !SMI
## !AGENTS
## Create an Azure RBAC role assignment granting the system-assigned managed identity for the Microsoft Foundry resource
## the Key Vault Secrets Officer role on the Key Vault to allow management of secrets
##
resource "azurerm_role_assignment" "smi_foundry_secrets_key_vault_secrets_officer" {
  count = var.resource_managed_identity_type == "smi" && var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    time_sleep.wait_smi_foundry
  ]

  scope                = azurerm_key_vault.key_vault_foundry_secrets[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azapi_resource.foundry_resource.output.identity.principalId
}

## !SMI
## !CMK
## Create an Azure RBAC role assignment granting the Microsoft Foundry system-assigned managed identity 
## the Key Vault Crypto User role on the Key Vault to allow use of the CMK.
##
resource "azurerm_role_assignment" "smi_foundry_cmk_key_vault_crypto_user" {
  count = var.resource_managed_identity_type == "smi" && var.foundry_encryption == "cmk" ? 1 : 0

  depends_on = [
    time_sleep.wait_smi_foundry
  ]

  scope                = azurerm_key_vault.key_vault_foundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azapi_resource.foundry_resource.output.identity.principalId
}

## !SMI
## Sleep for 120 seconds to allow the Azure RBAC permissions to replicate across Azure
##
resource "time_sleep" "wait_key_vault_secrets_smi_rbac_replication" {
  count = var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.smi_foundry_secrets_key_vault_secrets_officer,
    azurerm_role_assignment.smi_foundry_cmk_key_vault_crypto_user
  ]

  create_duration = "120s"
}

## !SMI
## !CMK
## Switch the Microsoft Foundry resource to use CMK if the Foundry resource is using a system-assigned managed identity
##
resource "azurerm_cognitive_account_customer_managed_key" "foundry_cmk" {
  count = var.foundry_encryption == "cmk" && var.resource_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    time_sleep.wait_key_vault_secrets_smi_rbac_replication
  ]

  cognitive_account_id = azapi_resource.foundry_resource.id
  key_vault_key_id     = azurerm_key_vault_key.key_foundry_cmk[0].id
}

######### Create some model deployments to muck around with
#########
#########

## Create a deployment for OpenAI's GPT-5.1
##
resource "azurerm_cognitive_deployment" "deployment_gpt_5_1" {
  depends_on = [
    azapi_resource.foundry_resource,
    azurerm_cognitive_account_customer_managed_key.foundry_cmk
  ]

  name                 = "gpt-5.1"
  cognitive_account_id = azapi_resource.foundry_resource.id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    # Using global for maximum TPM; DataZone should be used for regulated customers
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-5.1"
    version = "2025-11-13"
  }
}

######### Create deployments required to use Content Understanding
#########
#########

## !CONTENTUNDERSTANDING
## Create a deployment for OpenAI's GPT-4.1
##
resource "azurerm_cognitive_deployment" "deployment_gpt_41" {
  count = var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt_5_1
  ]

  name                 = "gpt-4.1"
  cognitive_account_id = azapi_resource.foundry_resource.id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-4.1"
    version = "2025-04-14"
  }
}

## !CONTENTUNDERSTANDING
## Create a deployment for OpenAI's GPT-4.1-mini
##
resource "azurerm_cognitive_deployment" "deployment_gpt_41_mini" {
  count = var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt_41
  ]

  name                 = "gpt-4.1-mini"
  cognitive_account_id = azapi_resource.foundry_resource.id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-4.1-mini"
    version = "2025-04-14"
  }
}

## !CONTENTUNDERSTANDING
## Create a deployment for the text-embedding-3-large embededing model
##
resource "azurerm_cognitive_deployment" "deployment_text_embedding_3_large" {
  count = var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt_41_mini
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azapi_resource.foundry_resource.id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = 1
  }
}

######### Create Private Endpoint for Foundry resource
#########
#########

## Create Private Endpoint for Foundry resource
##
resource "azurerm_private_endpoint" "pe_foundry_resource" {
  depends_on = [
    azapi_resource.foundry_resource,
    azurerm_cognitive_account_customer_managed_key.foundry_cmk,
    azurerm_cognitive_deployment.deployment_text_embedding_3_large
  ]

  name                = "pe${azapi_resource.foundry_resource.name}resource"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.foundry_resource.name}resource"

  private_service_connection {
    name                           = "peconn${azapi_resource.foundry_resource.name}resource"
    private_connection_resource_id = azapi_resource.foundry_resource.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.foundry_resource.name}account"
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

########## Create the resources required to support the Bring-your-own resources use case for Foundry agents
########## AI Search and Azure Storage Account will be created when using Content Understanding even if not using agents
##########

## TODO: 6/2026 Add this to a Network Security Perimeter once Cosmos Network Security Perimeter integration is GA
## !AGENTS
## Create Cosmos DB account to store messages/responses, conversation history, agent metadata
##
resource "azurerm_cosmosdb_account" "cosmosdb_foundry" {
  count = var.agents ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "cosdbmsf${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags

  # General settings
  offer_type        = "Standard"
  kind              = "GlobalDocumentDB"
  free_tier_enabled = false

  # Set security-related settings
  local_authentication_enabled = false

  # Access to Cosmos by agents will be done through Private Endpoint
  public_network_access_enabled = false

  # Set high availability and failover settings to cheapo mode. Do not use for production
  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false

  # Configure consistency settings
  consistency_policy {
    consistency_level = "Session"
  }

  # Configure single location with no zone redundancy to reduce costs. Do not use for production
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

## !AGENTS
## Create diagnostic settings for the CosmosDB account
##
resource "azurerm_monitor_diagnostic_setting" "diag_cosmosdb" {
  count = var.agents ? 1 : 0

  depends_on = [
    azurerm_cosmosdb_account.cosmosdb_foundry
  ]

  name                           = "diag-base"
  target_resource_id             = azurerm_cosmosdb_account.cosmosdb_foundry[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  log_analytics_destination_type = "Dedicated"

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

## !AGENTS
## !CONTENTUNDERSTANDING
## Create an AI Search service where vector stores created by Foundry agents will be stored
## This can also be used for general search use cases in this lab environment
##
resource "azurerm_search_service" "ai_search_foundry" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    # Wait on user-assigned managed identity creation and replication
    azurerm_user_assigned_identity.umi_ai_search,
    time_sleep.wait_umi_foundry_resource,
    # Wait on Network Security Perimeter resources
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_ai_resources
  ]

  name                = "aismsf${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = var.tags

  # TODO: 6/2026 Change this to use an UMI only once the search limitations are lifted
  # Use both a system-assigned managed identity and user-assigned managed identity to support
  # the limitations documented https://learn.microsoft.com/en-us/azure/search/search-security-managed-identity?tabs=portal#limitations
  #
  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_ai_search[0].id
    ]
  }

  # Use Standard SKU to support most popular features
  sku                 = "standard"
  hosting_mode        = "default"
  replica_count       = 1
  partition_count     = 1
  semantic_search_sku = "standard"

  # Support both Entra ID authentication and API authentication
  local_authentication_enabled = true
  authentication_failure_mode  = "http401WithBearerChallenge"

  # Disable public network access and rely on Private Endpoints and firewall exception or NSP
  public_network_access_enabled = false
  # TODO: 6/2026 Remove the network_rule_bypass_option section once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  network_rule_bypass_option = "AzureServices"

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## !AGENTS
## !CONTENTUNDERSTANDING
## Create diagnostic settings for the Azure AI Search service
##
resource "azurerm_monitor_diagnostic_setting" "diag_ai_search" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

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

## !AGENTS
## !CONTENTUNDERSTANDING
## Associate the Search Service to the Network Security Perimeter profile
##
resource "azurerm_network_security_perimeter_association" "assoc_foundry_ai_search" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_search_service.ai_search_foundry
  ]

  name = "assocfoundryaisearch"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_ai_resources[0].id
  resource_id                           = azurerm_search_service.ai_search_foundry[0].id
}

## !AGENTS
## !CONTENTUNDERSTANDING
## Create a storage account which will store any files uploaded to Foundry by users
##
resource "azurerm_storage_account" "storage_account_foundry" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    # Wait on Network Security Perimeter resources
    azurerm_network_security_perimeter_profile.profile_nsp_foundry_ai_resources
  ]

  name                = "stmsf${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = merge(var.tags, { SecurityControl = "Ignore" })

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  # TODO: 6/2026 Remove network_acls section and set public access to false to rely on NSP rules once cross NSP links are supported to address the issue of diagnostic settings delivery of signals being blocked by NSP
  public_network_access_enabled = true

  network_rules {
    default_action = "Deny"
    # !LAB
    ip_rules = [
      var.trusted_ip
    ]
    bypass = ["AzureServices"]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## !AGENTS
## !CONTENTUNDERSTANDING
## Configure diagnostic settings for blob, file, queue, and table services to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_foundry_blob" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

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
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

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
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

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
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

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

## !AGENTS
## !CONTENTUNDERSTANDING
## Associate the Storage Account to the Network Security Perimeter profile
##
resource "azurerm_network_security_perimeter_association" "assoc_foundry_storage_account" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_foundry,
    azurerm_monitor_diagnostic_setting.diag_storage_foundry_table,
    azurerm_network_security_perimeter_association.assoc_foundry_ai_search
  ]

  name = "assocfoundrystorageaccount"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_foundry_ai_resources[0].id
  resource_id                           = azurerm_storage_account.storage_account_foundry[0].id
}

## !AGENTS
## Create Azure Container Registry to store container images for Foundry hosted agents
##
resource "azurerm_container_registry" "acr_foundry" {
  count = var.agents ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_foundry,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "acrmsf${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_foundry.name
  location            = var.region
  tags                = var.tags

  # Use Premium SKU to support Private Endpoints
  sku           = "Premium"
  admin_enabled = false

  # TODO: 6/2026 Modify this to disabled once hosted agents supports a private ACR
  public_network_access_enabled = true

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## !AGENTS
## Create diagnostic settings for the Container Registry
##
resource "azurerm_monitor_diagnostic_setting" "diag_acr_foundry" {
  count = var.agents ? 1 : 0
  depends_on = [
    azurerm_container_registry.acr_foundry
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr_foundry[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

########## Create Private Endpoints for resources used for Foundry Standard Agents with Bring-your-own resources
########## Private Endpoint for AI Search and Azure Storage is created when using Content Understanding even if not using agents
##########

## !AGENTS
## Create Private Endpoint for the CosmosDB account used for the standard agent configuration
##
resource "azurerm_private_endpoint" "pe_cosmosdb_foundry" {
  count = var.agents ? 1 : 0

  depends_on = [
    azurerm_cosmosdb_account.cosmosdb_foundry,
    azurerm_private_endpoint.pe_foundry_resource
  ]

  name                = "pe${azurerm_cosmosdb_account.cosmosdb_foundry[0].name}cosmossql"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_cosmosdb_account.cosmosdb_foundry[0].name}cosmossql"
  private_service_connection {
    name                           = "peconn${azurerm_cosmosdb_account.cosmosdb_foundry[0].name}cosmossql"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmosdb_foundry[0].id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_cosmosdb_account.cosmosdb_foundry[0].name}cosmossql"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## !AGENTS
## !CONTENTUNDERSTANDING
## Create Private Endpoint for the AI Foundry AI Search instance used standard agent or RAG demo
##
resource "azurerm_private_endpoint" "pe_aisearch_foundry" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_cosmosdb_foundry,
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

## !AGENTS
## !CONTENTUNDERSTANDING
## Create Private Endpoint for the AI Foundry storage account used for the standard agent configuration
##
resource "azurerm_private_endpoint" "pe_storage_blob_foundry" {
  count = var.agents || var.deploy_content_understanding_resources ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_aisearch_foundry,
    azurerm_storage_account.storage_account_foundry,
    azurerm_network_security_perimeter_association.assoc_foundry_storage_account
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

########## Create Private Endpoint for Azure Container Registry used for Foundry hosted agents
########## 
##########

## !AGENTS
## Create Private Endpoint for the Azure Container Registry used for hosted agents
##
resource "azurerm_private_endpoint" "pe_acr_foundry" {
  count = var.agents ? 1 : 0
  depends_on = [
    azurerm_container_registry.acr_foundry
  ]

  name                = "pe${azurerm_container_registry.acr_foundry[0].name}acr"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_foundry.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_container_registry.acr_foundry[0].name}acr"
  private_service_connection {
    name                           = "peconn${azurerm_container_registry.acr_foundry[0].name}acr"
    private_connection_resource_id = azurerm_container_registry.acr_foundry[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_container_registry.acr_foundry[0].name}acr"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

######### Create role assignments to support Foundry agent deployment that will use managed virtual network
######### This accounts for both user-assigned managed identity and system-assigned managed identity scenarios
#########

## !UMI
## !AGENTS
## !MANAGEDVNET
## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Microsoft Foundry resource
## the Azure AI Enterprise Network Connection Approver role on the resource group to allow approval of private endpoints created in the
## managed virtual network. The managed identity will need this permission over any resource that you want to add
## as a managed private endpoint in the managed virtual network
##
resource "azurerm_role_assignment" "umi_foundry_resource_azure_ai_enterprise_network_connection_approver" {
  count = var.resource_managed_identity_type == "umi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry
  ]

  scope                = azurerm_resource_group.rg_foundry.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.umi_foundry_resource[0].principal_id
}

## TODO: 6/2026 Remove this once the Azure AI Enterprise Network Connection Approver role is updated to include the Microsoft.ContainerRegistry/registries/read permission
## !UMI
## !AGENTS
## !MANAGEDVNET
## Create an Azure RBAC role assignment granting the Foundry resource's user-assigned managed identity the Reader role on the 
## Azure Container Registry to allow reading of the resource before creating the managed private endpoint. 
## The Azure AI Enterprise Network Connection Approver role lacks the Microsoft.ContainerRegistry/registries/read permission 
## which is required in order to read the resource
##
resource "azurerm_role_assignment" "umi_foundry_resource_reader_container_registry" {
  count = var.resource_managed_identity_type == "umi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry
  ]

  scope                = azurerm_container_registry.acr_foundry[0].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.umi_foundry_resource[0].principal_id
}

## !UMI
## !AGENTS
## !MANAGEDVNET
## !BYOMODEL
## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Microsoft Foundry resource
## the Azure AI Enterprise Network Connection Approver role on the API Management instance to allow approval of private endpoints created in the
## managed virtual network.
##
resource "azurerm_role_assignment" "umi_foundry_resource_azure_ai_enterprise_network_connection_approver_byo_model" {
  count = var.resource_managed_identity_type == "umi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents && var.apim_ai_gateway != null ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry
  ]

  scope                = var.apim_ai_gateway[0].apim_resource_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.umi_foundry_resource[0].principal_id
}

## !SMI
## !AGENTS
## !MANAGEDVNET
## Create an Azure RBAC role assignment granting the system-assigned managed identity for the Foundry
## resource the Azure AI Enterprise Network Connection Approver role on the resource group to allow approval of private endpoints created in the
## managed virtual network. The managed identity will need this permission over any resource that you want to add
## as a managed private endpoint in the managed virtual network
##
resource "azurerm_role_assignment" "smi_foundry_azure_ai_enterprise_network_connection_approver" {
  count = var.resource_managed_identity_type == "smi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry,
    time_sleep.wait_smi_foundry
  ]

  scope                = azurerm_resource_group.rg_foundry.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azapi_resource.foundry_resource.output.identity.principalId
}

## TODO: 6/2026 Remove this once the Azure AI Enterprise Network Connection Approver role is updated to include the Microsoft.ContainerRegistry/registries/read permission
## !SMI
## !AGENTS
## !MANAGEDVNET
## Create an Azure RBAC role assignment granting the Foundry resource's system-assigned managed identity the Reader role on the 
## Azure Container Registry to allow reading of the resource before creating the managed private endpoint. 
## The Azure AI Enterprise Network Connection Approver role lacks the Microsoft.ContainerRegistry/registries/read permission 
## which is required in order to read the resource
##
resource "azurerm_role_assignment" "smi_foundry_reader_container_registry" {
  count = var.resource_managed_identity_type == "smi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry,
    time_sleep.wait_smi_foundry
  ]

  scope                = azurerm_container_registry.acr_foundry[0].id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.foundry_resource.output.identity.principalId
}


## !UMI
## !AGENTS
## !MANAGEDVNET
## !BYOMODEL
## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Microsoft Foundry resource
## the Azure AI Enterprise Network Connection Approver role on the API Management instance to allow approval of private endpoints created in the
## managed virtual network.
##
resource "azurerm_role_assignment" "smi_foundry_resource_azure_ai_enterprise_network_connection_approver_byo_model" {
  count = var.resource_managed_identity_type == "smi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents && var.apim_ai_gateway != null ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_acr_foundry,
    time_sleep.wait_smi_foundry
  ]

  scope                = var.apim_ai_gateway[0].apim_resource_id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azapi_resource.foundry_resource.output.identity.principalId
}

## !AGENTS
## !MANAGEDVNET
## Sleep for 120 seconds to allow the Application Insights resource to be fully available
##
resource "time_sleep" "wait_managed_vnet_permissions_replication" {
  count = var.resource_managed_identity_type == "umi" && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.agents ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_foundry_resource_azure_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.umi_foundry_resource_reader_container_registry,
    azurerm_role_assignment.umi_foundry_resource_azure_ai_enterprise_network_connection_approver_byo_model,
    azurerm_role_assignment.smi_foundry_azure_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.smi_foundry_reader_container_registry,
    azurerm_role_assignment.smi_foundry_resource_azure_ai_enterprise_network_connection_approver_byo_model
  ]
  create_duration = "120s"
}

########## Create a managed virtual network and common outbound rules
##########
##########

## !MANAGEDVNET
## !AGENTS
## Create a managed virtual network where Foundry agents will be deployed to
##
resource "azapi_resource" "foundry_managed_virtual_network" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    # Wait for creation of Foundry resource
    azapi_resource.foundry_resource,
    azurerm_private_endpoint.pe_foundry_resource,
    azurerm_network_security_perimeter_association.assoc_foundry_resource,
    # Wait for creation of resources required for standard agent with bring-your-own resources
    azurerm_cosmosdb_account.cosmosdb_foundry,
    azurerm_search_service.ai_search_foundry,
    azurerm_storage_account.storage_account_foundry,
    azurerm_private_endpoint.pe_aisearch_foundry,
    azurerm_private_endpoint.pe_cosmosdb_foundry,
    azurerm_private_endpoint.pe_storage_blob_foundry,
    # Wait for Azure Container Registry used for Foundry hosted agents
    azurerm_container_registry.acr_foundry,
    azurerm_private_endpoint.pe_acr_foundry,
    # Wait for permissions required for managed virtual network to be replicated across Azure
    time_sleep.wait_managed_vnet_permissions_replication
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks@2026-05-15-preview"
  name                      = "default"
  parent_id                 = azapi_resource.foundry_resource.id
  schema_validation_enabled = false

  body = {
    properties = {
      managedNetwork = {
        # Ensure use of v2 managed virtual network
        managedNetworkKind = "V2"

        # Restrict all outbound access unless excplicitly allowed via outbound rules
        isolationMode = "AllowOnlyApprovedOutbound"

        # Use Standard SKU if there is a use case for FQDN rule; keeping disabled because I'm cheap
        #firewallSku = "Standard"

        # Create the managed virtual network immediately
        provisionNetworkNow = true
      }
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule to create the managed private endpoint for the Foundry resource in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_foundry_resource" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.foundry_managed_virtual_network
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowFoundryResource"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azapi_resource.foundry_resource.id
        subresourceTarget = "account"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule to create the managed private endpoint for the Storage Account for blob endpoint in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_storage_account_blob" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_foundry_resource
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowStorageAccountBlob"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_storage_account.storage_account_foundry[0].id
        subresourceTarget = "blob"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule to create the managed private endpoint for the CosmosDB account in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_cosmosdb_account_sql" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_storage_account_blob
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowCosmosDBAccountSQL"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_cosmosdb_account.cosmosdb_foundry[0].id
        subresourceTarget = "Sql"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule to create the managed private endpoint for the AI Search instance in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_ai_search" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_cosmosdb_account_sql
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowAISearch"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_search_service.ai_search_foundry[0].id
        subresourceTarget = "searchService"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule to create the managed private endpoint for the Azure Container Registry in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_acr" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_ai_search
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowACR"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = azurerm_container_registry.acr_foundry[0].id
        subresourceTarget = "registry"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule for the Azure Monitor service tag to support access to Application Insights
## If you're using an AMPLS you'll need the appropriate Private Endpoint rule for that.
## Reference https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/18-managed-virtual-network/modules-network-secured/managed-network.bicep
##
resource "azapi_resource" "managed_vnet_outbound_rule_service_tag_azure_monitor" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_acr
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowAgentAzureMonitor"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "ServiceTag"
      destination = {
        action          = "Allow"
        addressPrefixes = []
        serviceTag      = "AzureMonitor"
        protocol        = "TCP"
        portRanges      = "80, 443"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## Create outbound rule for the AzureFrontDoor.Frontend service tag to support access to
## the Agent 365 observability/tracing endpoint agent365.svc.cloud.microsoft.com. If you find this too permissive,
## you can create an FQDN rule instead but you'll then need a Standard SKU Azure Firewall in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_service_tag_azure_frontdoor_frontend" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_service_tag_azure_monitor
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowAgent365FrontdoorRule"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "ServiceTag"
      destination = {
        action          = "Allow"
        addressPrefixes = []
        serviceTag      = "AzureFrontDoor.Frontend"
        protocol        = "TCP"
        portRanges      = "443"
      }
      category = "UserDefined"
    }
  }
}

## !MANAGEDVNET
## !AGENTS
## !BYOMODEL
## Create outbound rule to create the managed private endpoint for the API Management AI Gateway in the managed virtual network
##
resource "azapi_resource" "managed_vnet_outbound_rule_private_endpoint_apim" {
  count = var.agents && var.agent_service_outbound_networking.type == "managed_virtual_network" && var.apim_ai_gateway != null ? 1 : 0

  depends_on = [
    azapi_resource.managed_vnet_outbound_rule_service_tag_azure_frontdoor_frontend
  ]

  type                      = "Microsoft.CognitiveServices/accounts/managedNetworks/outboundRules@2026-05-15-preview"
  name                      = "AllowAIGateway"
  parent_id                 = azapi_resource.foundry_managed_virtual_network[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
        serviceResourceId = var.apim_ai_gateway[0].apim_resource_id
        subresourceTarget = "Gateway"
      }
      category = "UserDefined"
    }
  }
}

## !BYOKEYVAULT
## !AGENTS
## Create a Foundry resource connection to the Key Vault used to store secrets for connections created within Foundry
## This is only required if var.deploy_key_vault_connection_secrets is set to true
resource "azapi_resource" "conn_resource_key_vault_secrets" {
  count = var.deploy_key_vault_connection_secrets && var.agents ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_foundry_secrets,
    azurerm_private_endpoint.pe_key_vault_secrets_foundry,
    time_sleep.wait_key_vault_secrets_umi_rbac_replication,
    time_sleep.wait_key_vault_secrets_smi_rbac_replication,
    azapi_resource.foundry_resource
  ]

  type                      = "Microsoft.CognitiveServices/accounts/connections@2026-05-01"
  name                      = azurerm_key_vault.key_vault_foundry_secrets[0].name
  parent_id                 = azapi_resource.foundry_resource.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AzureKeyVault"
      isSharedToAll = true
      target        = "https://${azurerm_key_vault.key_vault_foundry_secrets[0].name}.vault.azure.net/"
      authType      = "AccountManagedIdentity"
      credentials   = {}
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_key_vault.key_vault_foundry_secrets[0].id
        Location   = var.region
      }
    }
  }
}

########## Create the Foundry project using the module
##########
##########

## !AGENTS
## Create a Foundry project for the purposes of creating Foundry agents
##
module "foundry_project_agents" {
  count = var.agents ? 1 : 0

  depends_on = [
    # Wait for creation of Foundry resource
    azapi_resource.foundry_resource,
    azurerm_private_endpoint.pe_foundry_resource,
    azurerm_network_security_perimeter_association.assoc_foundry_resource,
    # Wait for creation of resources required for standard agent with bring-your-own resources
    azurerm_cosmosdb_account.cosmosdb_foundry,
    azurerm_search_service.ai_search_foundry,
    azurerm_storage_account.storage_account_foundry,
    azurerm_container_registry.acr_foundry,
    azurerm_private_endpoint.pe_aisearch_foundry,
    azurerm_private_endpoint.pe_cosmosdb_foundry,
    azurerm_private_endpoint.pe_storage_blob_foundry,
    azurerm_private_endpoint.pe_acr_foundry,
    azapi_resource.bing_grounding_custom_search_foundry,
    azurerm_application_insights.appins_foundry,
    # Wait for managed VNet and outbound rules to be created
    azapi_resource.foundry_managed_virtual_network,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_foundry_resource,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_storage_account_blob,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_cosmosdb_account_sql,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_ai_search,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_acr,
    azapi_resource.managed_vnet_outbound_rule_service_tag_azure_monitor,
    azapi_resource.managed_vnet_outbound_rule_service_tag_azure_frontdoor_frontend,
    azapi_resource.managed_vnet_outbound_rule_private_endpoint_apim,
    # Wait for conditional resources
    azurerm_cognitive_deployment.deployment_text_embedding_3_large,
    azurerm_key_vault.key_vault_foundry_cmk,
    azapi_resource.conn_resource_key_vault_secrets,
    azurerm_private_endpoint.pe_key_vault_secrets_foundry,
    time_sleep.wait_key_vault_secrets_umi_rbac_replication,
    time_sleep.wait_key_vault_secrets_smi_rbac_replication
  ]

  source                             = "./modules/project"
  foundry_resource_id                = azapi_resource.foundry_resource.id
  foundry_resource_resource_group_id = azurerm_resource_group.rg_foundry.id
  region                             = var.region
  #first_project                      = true
  project_number                     = 1

  # Basic settings
  agents                        = var.agents ? true : false
  project_managed_identity_type = var.project_managed_identity_type

  ## Support CMK
  foundry_cmk_enabled = var.foundry_encryption == "cmk" ? true : false
  foundry_cmk_key_vault_resource_id = var.foundry_encryption == "cmk" ? azurerm_key_vault.key_vault_foundry_cmk[0].id : null

  ## Required info for project-level connections
  shared_agent_ai_search_resource_id          = azurerm_search_service.ai_search_foundry[0].id
  shared_agent_cosmosdb_account_resource_id   = azurerm_cosmosdb_account.cosmosdb_foundry[0].id
  shared_agent_cosmosdb_account_endpoint      = azurerm_cosmosdb_account.cosmosdb_foundry[0].endpoint
  shared_agent_storage_account_resource_id    = azurerm_storage_account.storage_account_foundry[0].id
  shared_agent_storage_account_blob_endpoint  = azurerm_storage_account.storage_account_foundry[0].primary_blob_endpoint
  shared_agent_container_registry_resource_id = azurerm_container_registry.acr_foundry[0].id
  shared_bing_grounding_search_resource_id    = azapi_resource.bing_grounding_custom_search_foundry[0].id
  shared_bing_grounding_search_api_key        = data.azapi_resource_action.bing_api_keys[0].output.key1
  shared_app_insights_resource_id       = azurerm_application_insights.appins_foundry[0].id
  shared_app_insights_connection_string = azurerm_application_insights.appins_foundry[0].connection_string
  shared_external_openai                      = var.external_openai

  ## Optional info for project-level connections
  apim_ai_gateway       = var.apim_ai_gateway
  model_gateway         = var.model_gateway
  model_gateway_api_key = var.model_gateway_api_key

  # User object id to grant permissions over project
  user_object_id = var.user_object_id
}
