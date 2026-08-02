########## Create base resources
##########
##########

## Use time_static to generate a timestamp which will be used in created_date tag. Use this instead of timestamp
## so Terraform doesn't freak out every time apply is run again
##
resource "time_static" "created" {}

########## Create the Entra ID application and service principal that will be used by the Function App
##########
##########

## Create the Entra ID application object
##
resource "azuread_application" "app_reg_function" {
  display_name = "FunctionApp${var.region_code}${var.random_string}"

  # Set the owner to the identity context that deployed the resources
  owners = [
    data.azuread_client_config.current.object_id
  ]
  # Deploy as single tenant
  sign_in_audience = "AzureADMyOrg"

  # Deploy the app registration with an OAuth scope that can be requested in the access token for the app
  api {
    requested_access_token_version = 2

    # Standard impersonation scope where both the user can consent for themselves or the admin can consent on behalf of all users
    oauth2_permission_scope {
      id                         = "00000000-0000-0000-0000-000000000001"
      admin_consent_description  = "Allow the app to call the function on behalf of the signed-in user"
      admin_consent_display_name = "Access function app"
      user_consent_description   = "Allow the app to call the function on your behalf"
      user_consent_display_name  = "Access function app"
      value                      = "user_impersonation"
      type                       = "User"
      enabled                    = true
    }
  }

  # Don't remove the identifier URI on re-apply because it's managed
  # down below with the azuread_application_identifier_uri resource
  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

## Create the Entra ID service principal for the app registration
##
resource "azuread_service_principal" "sp_function" {
  depends_on = [
    azuread_application.app_reg_function
  ]

  client_id                    = azuread_application.app_reg_function.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_function" {
  name     = "rgfunc${var.region_code}${var.random_string}"
  location = var.region
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Log Analytics Workspace that all resources specific to this workload will
## write configured resource logs and metrics to
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawfunc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########## Create Network Security Perimeters that will be used to restrict access to the resources
########## that support the Azure Functions instance
##########

## Create a Network Security Perimeter that will be used to restrict access to resources that support
## the Azure Functions instance
resource "azurerm_network_security_perimeter" "nsp_function_resources" {
  depends_on = [
    azurerm_resource_group.rg_function,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "nspfuncres${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_function.name
  location            = var.region
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }

}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_function_resources" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_function_resources
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_network_security_perimeter.nsp_function_resources.id
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

## Create a Network Security Perimeter profile that will be associated with the Azure Storage Account
## that backs the Azure Functions instance
resource "azurerm_network_security_perimeter_profile" "profile_nsp_storage_account_function" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_function_resources
  ]

  name                          = "pstorageaccount"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_function_resources.id
}

## Create an access rule to allow the machine deploying the Terraform resources data plane access to the storage account
## Only required for my shitty lab
resource "azurerm_network_security_perimeter_access_rule" "access_rule_storage_account_function_env_ipprefix" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_storage_account_function
  ]

  name                                  = "arsafunctrustedips"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_storage_account_function.id
  direction                             = "Inbound"
  address_prefixes = [
    "${var.trusted_ip}/32"
  ]
}

## Create a Network Security Perimeter profile that will be associated with the Azure Key Vault
## that is used for secure secrets storate by the Function
resource "azurerm_network_security_perimeter_profile" "profile_nsp_key_vault_function" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_function_resources
  ]

  name                          = "pkeyvault"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_function_resources.id
}

## Create an access rule to allow the machine deploying the Terraform resources data plane access to the Key Vault
## Only required for my shitty lab
resource "azurerm_network_security_perimeter_access_rule" "access_rule_key_vault_function_env_ipprefix" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_storage_account_function
  ]

  name                                  = "arsafunctrustedips"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_storage_account_function.id
  direction                             = "Inbound"
  address_prefixes = [
    "${var.trusted_ip}/32"
  ]
}

########## Create an Azure Storage Account and its private endpoints
########## The storage account is used for Azure Functions to store code packages, logs, and other files
##########

## Create the storage account that will be used to 
##
resource "azurerm_storage_account" "storage_account_function" {
  depends_on = [
    azurerm_resource_group.rg_function,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "stfunc${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_function.name
  location            = var.region
  # TODO: 5/2026 This additional tag can be removed when NSPs support NSP link.
  # used specifically for my lab where I have some policies enforcing no public access 
  # to the storage account
  tags = merge(local.tags, { SecurityControl = "Ignore" })

  # Create a system-assigned managed identity to the storage account to support CMK in the future if needed
  identity {
    type = "SystemAssigned"
  }

  account_kind = "StorageV2"
  account_tier = "Standard"
  # LRS to save costs since this is lab
  account_replication_type = "LRS"

  # Disable key-based access preventing use of SAK/SAS
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  # TODO: 6/2026 Set public network access to false and remove the network_acls section once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  # This is a unique requirement for my lab
  public_network_access_enabled = true
  network_rules {
    default_action = "Deny"
    ip_rules = [
      var.trusted_ip
    ]
    bypass = ["AzureServices"]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Azure Functions storage account for blob, file, queue, and table services to 
## send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_storage_function_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_function
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_function.id}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_function_file" {
  depends_on = [
    azurerm_storage_account.storage_account_function,
    azurerm_monitor_diagnostic_setting.diag_storage_function_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_function.id}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_function_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_function,
    azurerm_monitor_diagnostic_setting.diag_storage_function_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_function.id}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_function_table" {
  depends_on = [
    azurerm_storage_account.storage_account_function,
    azurerm_monitor_diagnostic_setting.diag_storage_function_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_function.id}/tableServices/default"
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

## Create the blob container used for code deployment
##
resource "azurerm_storage_container" "container_deployment" {
  depends_on = [
    azurerm_storage_account.storage_account_function
  ]

  name                  = "function-deployment"
  storage_account_id    = azurerm_storage_account.storage_account_function.id
  container_access_type = "private"
}

## Create the blob containers for web jobs
##
resource "azurerm_storage_container" "container_webjobs_hosts" {
  depends_on = [
    azurerm_storage_account.storage_account_function
  ]

  name                  = "azure-webjobs-hosts"
  storage_account_id    = azurerm_storage_account.storage_account_function.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "container_webjobs_secrets" {
  depends_on = [
    azurerm_storage_account.storage_account_function
  ]

  name                  = "azure-webjobs-secrets"
  storage_account_id    = azurerm_storage_account.storage_account_function.id
  container_access_type = "private"
}

## Create a Network Security Perimeter resource assocation to associate the Storage Accounts to the NSP
##
resource "azurerm_network_security_perimeter_association" "assoc_storage_account_function" {
  depends_on = [
    azurerm_storage_account.storage_account_function,
    azurerm_storage_container.container_deployment,
    azurerm_storage_container.container_webjobs_hosts,
    azurerm_storage_container.container_webjobs_secrets,
    azurerm_network_security_perimeter_access_rule.access_rule_storage_account_function_env_ipprefix
  ]

  name = "rastorageaccount"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_storage_account_function.id
  resource_id                           = azurerm_storage_account.storage_account_function.id
}

## Create a Private Endpoint for Function Storage Account for blob endpoint
## 
resource "azurerm_private_endpoint" "private_endpoint_storage_account_blob_function" {
  depends_on = [
    azurerm_network_security_perimeter_association.assoc_storage_account_function
  ]

  name                = "pestacctfuncblob${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "pestacctfuncblob${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.storage_account_function.id
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_function.name}blob"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for Function Storage Account for table endpoint
## 
resource "azurerm_private_endpoint" "private_endpoint_storage_account_table_function" {
  depends_on = [
    azurerm_private_endpoint.private_endpoint_storage_account_blob_function
  ]

  name                = "pestacctfunctable${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "pestacctfunctable${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.storage_account_function.id
    subresource_names              = ["table"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_function.name}table"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    ]
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for Function Storage Account for queue endpoint
## 
resource "azurerm_private_endpoint" "private_endpoint_storage_account_queue_function" {
  depends_on = [
    azurerm_private_endpoint.private_endpoint_storage_account_table_function
  ]

  name                = "pestacctfuncqueue${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "pestacctfuncqueue${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.storage_account_function.id
    subresource_names              = ["queue"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_function.name}queue"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    ]
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########## Create a Key Vault instance and its private endpoint for secrets storage of the Azure Function
##########
##########

## Create Key Vault that will store secrets for the Azure Function
##
resource "azurerm_key_vault" "key_vault_function" {
  depends_on = [
    azurerm_resource_group.rg_function,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_storage_account.storage_account_function
  ]

  name                = "kvfunc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  # TODO: 5/2026 This additional tag can be removed when NSPs support NSP link.
  # used specifically for my lab where I have some policies enforcing no public access 
  # to the Key Vault
  tags = merge(local.tags, { SecurityControl = "Ignore" })

  sku_name = "standard"

  # Enabled for RBAC authorization
  rbac_authorization_enabled = true

  # Turn off purge protection so that Vault can be immediately purged
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Not required for this implementation
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  # TODO: 5/2026 - Remove this section once NSPs support NSP links to resolve the diagnostic settings issues
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []
    # Only required for my lab environment based on its configuration
    ip_rules = [
      var.trusted_ip
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Function Key Vault to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_function" {
  depends_on = [
    azurerm_key_vault.key_vault_function
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_function.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create a Network Security Perimeter resource assocation to associate the Key Vault to the NSP
##
resource "azurerm_network_security_perimeter_association" "assoc_key_vault_function" {
  depends_on = [
    azurerm_key_vault.key_vault_function,
    azurerm_network_security_perimeter_access_rule.access_rule_key_vault_function_env_ipprefix
  ]

  name = "rakeyvault"
  # TODO: 6/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_key_vault_function.id
  resource_id                           = azurerm_key_vault.key_vault_function.id
}

## Create a Private Endpoint for the Azure Key Vault used for secret storage by the Azure Function
## 
resource "azurerm_private_endpoint" "private_endpoint_key_vault_function" {
  depends_on = [
    azurerm_network_security_perimeter_association.assoc_key_vault_function
  ]

  name                = "pekvfunc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "pekvfunc${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.key_vault_function.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_function.name}"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########## Create an Application Insights instance for the Azure Function
##########
##########

## Create Application Insights instance for the Azure Function
##
resource "azurerm_application_insights" "app_insights_function" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "appins${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  application_type = "web"
  workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  local_authentication_enabled = false

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Add 30 second sleep to allow for Application Insights 
## instance to be provisioned and key ready to use
resource "time_sleep" "wait_for_app_insights_func" {
  depends_on = [
    azurerm_application_insights.app_insights_function
  ]
  create_duration = "30s"
}

########## Create the user-assigned managed identity and relevant RBAC role assignments
##########
##########

## Create the user-assigned managed for the Function app
##
resource "azurerm_user_assigned_identity" "umi_function" {
  depends_on = [
    azurerm_resource_group.rg_function,
    time_sleep.wait_for_app_insights_func
  ]

  name                = "umifunc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Sleep for 10 seconds to allow the user-assigned managed identity to replicate through Entra ID
##
resource "time_sleep" "wait_umi_function" {

  depends_on = [
    azurerm_user_assigned_identity.umi_function
  ]
  create_duration = "10s"
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Storage Account Contributor role on the Azure Storage account used by the Azure Function.
## This is required for the Azure Blobs trigger
resource "azurerm_role_assignment" "umi_function_storage_account_contributor" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_storage_account.storage_account_function
  ]

  scope                = azurerm_storage_account.storage_account_function.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Storage Blob Data Owner role on the Azure Storage account used by the Azure Function
## This is required for all use cases
resource "azurerm_role_assignment" "umi_function_storage_blob_data_owner" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_storage_account.storage_account_function,
    azurerm_role_assignment.umi_function_storage_account_contributor
  ]

  scope                = azurerm_storage_account.storage_account_function.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Storage Queue Data Contributor role on the Azure Storage account used by the Azure Function
## This is required for the Azure Blobs trigger
resource "azurerm_role_assignment" "umi_function_storage_queue_data_contributor" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_storage_account.storage_account_function,
    azurerm_role_assignment.umi_function_storage_blob_data_owner
  ]

  scope                = azurerm_storage_account.storage_account_function.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Storage Queue Data Message Processor role on the Azure Storage account used by the Azure Function
## This is required to support the MCP Server extension if using SSE transport
resource "azurerm_role_assignment" "umi_function_storage_queue_data_message_processor" {
  count = var.mcp_server_enabled ? 1 : 0

  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_storage_account.storage_account_function,
    azurerm_role_assignment.umi_function_storage_queue_data_contributor
  ]

  scope                = azurerm_storage_account.storage_account_function.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Storage Table Data Contributor role on the Azure Storage account used by the Azure Function
## This is required for all use cases and supports diagnostic events
resource "azurerm_role_assignment" "umi_function_storage_table_data_contributor" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_storage_account.storage_account_function,
    azurerm_role_assignment.umi_function_storage_queue_data_message_processor
  ]

  scope                = azurerm_storage_account.storage_account_function.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Key Vault Secrets Officer role on the Azure Key Vault used by the Azure Function
## This allows the function to pull secrets for Key Vault references and store WebJobs secrets in the Key Vault
resource "azurerm_role_assignment" "umi_function_key_vault_secrets_officer" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_key_vault.key_vault_function,
    azurerm_role_assignment.umi_function_storage_table_data_contributor
  ]

  scope                = azurerm_key_vault.key_vault_function.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for the Function App
## the Monitoring Metrics Publisher role on the Application Insights used by the Azure Function
## This allows the function to deliver logs and metrics to Application Insights
resource "azurerm_role_assignment" "umi_function_app_insights_metrics_publisher" {
  depends_on = [
    time_sleep.wait_umi_function,
    azurerm_application_insights.app_insights_function,
    azurerm_role_assignment.umi_function_key_vault_secrets_officer
  ]
  scope                = azurerm_application_insights.app_insights_function.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.umi_function.principal_id
}

## Sleep for 120 seconds to allow the replication of the RBAC role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_function_permissions" {
  depends_on = [
    azurerm_role_assignment.umi_function_storage_account_contributor,
    azurerm_role_assignment.umi_function_storage_blob_data_owner,
    azurerm_role_assignment.umi_function_storage_table_data_contributor,
    azurerm_role_assignment.umi_function_storage_queue_data_contributor,
    azurerm_role_assignment.umi_function_key_vault_secrets_officer,
    azurerm_role_assignment.umi_function_app_insights_metrics_publisher
  ]
  create_duration = "120s"
}

########## Create the Function App Plan and Function App
##########
##########

## Create the Function App Plan that will host the Function App
##
resource "azurerm_service_plan" "function_app_plan" {
  depends_on = [
    azurerm_resource_group.rg_function
  ]

  name                = "funcappplan${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name
  # Create a Linux-based plan
  os_type  = "Linux"
  sku_name = var.function_plan_sku

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create the Function App as a Flex Consumption App if the SKU is set to FC1
##
resource "azurerm_function_app_flex_consumption" "function_app_flex_consumption" {
  count = var.function_plan_sku == "FC1" ? 1 : 0

  depends_on = [
    azurerm_service_plan.function_app_plan,
    azurerm_storage_account.storage_account_function,
    azurerm_key_vault.key_vault_function,
    azurerm_storage_container.container_deployment,
    azurerm_storage_container.container_webjobs_hosts,
    azurerm_storage_container.container_webjobs_secrets,
    azurerm_user_assigned_identity.umi_function,
    time_sleep.wait_umi_function_permissions,
    azurerm_application_insights.app_insights_function,
    time_sleep.wait_for_app_insights_func,
    azurerm_private_endpoint.private_endpoint_storage_account_blob_function,
    azurerm_private_endpoint.private_endpoint_storage_account_table_function,
    azurerm_private_endpoint.private_endpoint_storage_account_queue_function,
    azurerm_private_endpoint.private_endpoint_key_vault_function
  ]

  name                = "funcapp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name
  service_plan_id     = azurerm_service_plan.function_app_plan.id

  # Disable basic authN for deployments
  webdeploy_publish_basic_authentication_enabled = false

  # Identity-based access to storage account
  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.storage_account_function.primary_blob_endpoint}${azurerm_storage_container.container_deployment.name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.umi_function.id

  # Setup runtime
  runtime_name           = "python"
  runtime_version        = var.python_version
  maximum_instance_count = 10
  instance_memory_in_mb  = 2048

  # Setup networking
  https_only                    = true
  public_network_access_enabled = false
  virtual_network_subnet_id     = var.subnet_id_vint

  # Setup identity settings
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_function.id
    ]
  }

  site_config {
    minimum_tls_version = "1.2"

    # Route all traffic through customer network
    vnet_route_all_enabled = true

    # Configure app insights
    application_insights_connection_string = azurerm_application_insights.app_insights_function.connection_string
  }

  # Section which configures function to support Entra ID authentication
  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "Return401"
    # Not really needed but sets default provider if multiple were defined 
    default_provider = "azureactivedirectory"
    require_https    = true

    # Configure Entra ID IDP
    active_directory_v2 {
      client_id            = azuread_application.app_reg_function.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"

      # Don't use a client a secret, instead use the user-assigned managed identity associated with this function app
      # as a federated identity credential
      client_secret_setting_name = "OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID"

      # Limit the audiences that the authentication extension will accept
      allowed_audiences = [
        "api://${azuread_application.app_reg_function.client_id}/user_impersonation"
      ]
      # Limit the applications that can authenticate directly to this app or on behalf of the user
      # You will need to modify this to allow apps other than the function app's own SP
      allowed_applications = []

      www_authentication_disabled = false
    }

    # This is an API so token store isn't required
    login {
      token_store_enabled = false
    }
  }

  app_settings = {
    # Configure the function to use Entra ID auth to App Insights
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${azurerm_user_assigned_identity.umi_function.client_id}"

    # The azurerm provider automatically creates this app setting and tries to set it to the storage account connection string
    # which breaks Entra auth using managed identity to storage account. Setting to empty string prevents this
    AzureWebJobsStorage = ""

    # This setup will force the function to use its user-assigned managed identity to authenticate to the
    # storage account
    AzureWebJobsStorage__accountName               = azurerm_storage_account.storage_account_function.name
    AzureWebJobsStorage__credential                = "managedidentity"
    AzureWebJobsStorage__managedIdentityResourceId = azurerm_user_assigned_identity.umi_function.id

    # This setup will store function access keys in Key Vault instead of Azure Storage
    AzureWebJobsSecretStorageType = "keyvault"
    AzureWebJobsSecretStorageKeyVaultUri = azurerm_key_vault.key_vault_function.vault_uri
    AzureWebJobsSecretStorageKeyVaultClientId = azurerm_user_assigned_identity.umi_function.client_id

    # This tells the function to use its managed identity as a federated credential when acting as a confidential client to Entra to support Entra
    # ID authentication when the function exchanges an authorization code or refresh token for an access token
    OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID = azurerm_user_assigned_identity.umi_function.client_id

    # TODO: 5/2026 - Remove the mention of preview when this feature goes GA
    # This application setting is required to support the MCP Server extension for Azure Functions. It publishes
    # OAuth 2.0 protected resource metadata that helps MCP clients understand
    # how to interact with the MCP Server. Specifically, we publish the scopes 
    # defined for the app registration used by the function
    WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES = var.mcp_server_enabled ? "api://${azuread_application.app_reg_function.client_id}/user_impersonation" : ""
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create the Function App as a Elastic Premium App if the SKU is set to EP1
## You'll need to manually upload the zip package to the blob container and set
## WEBSITE_RUN_FROM_PACKAGE app setting to the blob URL of the zip package to deploy code to the function app
resource "azurerm_linux_function_app" "function_app_premium_plan" {
  count = var.function_plan_sku == "EP1" ? 1 : 0

  depends_on = [
    azurerm_service_plan.function_app_plan,
    azurerm_storage_account.storage_account_function,
    azurerm_user_assigned_identity.umi_function,
    time_sleep.wait_umi_function_permissions,
    azurerm_application_insights.app_insights_function,
    time_sleep.wait_for_app_insights_func,
    azurerm_private_endpoint.private_endpoint_storage_account_blob_function,
    azurerm_private_endpoint.private_endpoint_storage_account_table_function,
    azurerm_private_endpoint.private_endpoint_storage_account_queue_function,
    azurerm_private_endpoint.private_endpoint_key_vault_function
  ]

  name                = "funcapp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name
  service_plan_id     = azurerm_service_plan.function_app_plan.id

  # Disable basic authN for deployments
  webdeploy_publish_basic_authentication_enabled = false
  ftp_publish_basic_authentication_enabled       = false

  # Identity-based access to storage account
  storage_account_name          = azurerm_storage_account.storage_account_function.name
  storage_uses_managed_identity = true

  # Setup networking
  https_only                    = true
  public_network_access_enabled = false
  virtual_network_subnet_id     = var.subnet_id_vint

  # Configure the user-assigned managed identity to use to connect to Key Vault
  key_vault_reference_identity_id = azurerm_user_assigned_identity.umi_function.id

  # Setup identity settings
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_function.id
    ]
  }

  site_config {
    # Configure runtime stack to use Python
    application_stack {
      python_version = var.python_version
    }

    # Setup scaling
    elastic_instance_minimum  = 1
    pre_warmed_instance_count = 1

    # Set minimum TLS version
    minimum_tls_version = "1.2"

    # Route all traffic through customer network
    vnet_route_all_enabled = true

    # Configure app insights
    application_insights_connection_string = azurerm_application_insights.app_insights_function.connection_string
  }

  # Section which configures function to support Entra ID authentication
  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "Return401"
    # Not really needed but sets default provider if multiple were defined 
    default_provider = "azureactivedirectory"
    require_https    = true

    # Configure Entra ID IDP
    active_directory_v2 {
      client_id            = azuread_application.app_reg_function.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"

      # Don't use a client a secret, instead use the user-assigned managed identity associated with this function app
      # as a federated identity credential
      client_secret_setting_name = "OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID"

      # Limit the audiences that the authentication extension will accept
      allowed_audiences = [
        "api://${azuread_application.app_reg_function.client_id}/user_impersonation"
      ]
      # Limit the applications that can authenticate directly to this app or on behalf of the user
      # You will need to modify this to allow apps other than the function app's own SP
      allowed_applications = null

      www_authentication_disabled = false
    }

    # This is an API so token store isn't required
    login {
      token_store_enabled = false
    }
  }

  app_settings = {
    # Configure the function to use Entra ID auth to App Insights
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${azurerm_user_assigned_identity.umi_function.client_id}"

    # This tells the function app to use it's user-assigned managed identity to fetch the zip package from blob
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = azurerm_user_assigned_identity.umi_function.id

    # This setup will force the function to use its user-assigned managed identity to authenticate to the
    # storage account
    AzureWebJobsStorage__accountName               = azurerm_storage_account.storage_account_function.name
    AzureWebJobsStorage__credential                = "managedidentity"
    AzureWebJobsStorage__managedIdentityResourceId = azurerm_user_assigned_identity.umi_function.id

    # This setup will store function access keys in Key Vault instead of Azure Storage
    AzureWebJobsSecretStorageType = "keyvault"
    AzureWebJobsSecretStorageKeyVaultUri = azurerm_key_vault.key_vault_function.vault_uri
    AzureWebJobsSecretStorageKeyVaultClientId = azurerm_user_assigned_identity.umi_function.client_id

    # This tells the function to use its managed identity as a federated credential when acting as a confidential client to Entra to support Entra
    # ID authentication when the function exchanges an authorization code or refresh token for an access token
    OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID = azurerm_user_assigned_identity.umi_function.client_id

    # TODO: 5/2026 - Remove the mention of preview when this feature goes GA
    # This application setting is required to support the MCP Server extension for Azure Functions. It publishes
    # OAuth 2.0 protected resource metadata that helps MCP clients understand
    # how to interact with the MCP Server. Specifically, we publish the scopes 
    # defined for the app registration used by the function
    WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES = "api://${azuread_application.app_reg_function.client_id}/user_impersonation"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"],
      app_settings["WEBSITE_RUN_FROM_PACKAGE"]
    ]
  }
}

## Enable diagnostic settings for the Function App to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_function_app" {
  depends_on = [
    azurerm_function_app_flex_consumption.function_app_flex_consumption,
    azurerm_linux_function_app.function_app_premium_plan
  ]

  name                       = "diag"
  target_resource_id         = var.function_plan_sku == "FC1" ? azurerm_function_app_flex_consumption.function_app_flex_consumption[0].id : azurerm_linux_function_app.function_app_premium_plan[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "FunctionAppLogs"
  }

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }

  enabled_log {
    category = "AppServiceAuthenticationLogs"
  }
}

## Create Private Endpoint for Function App
##
resource "azurerm_private_endpoint" "private_endpoint_function_app" {
  depends_on = [
    azurerm_function_app_flex_consumption.function_app_flex_consumption,
    azurerm_linux_function_app.function_app_premium_plan
  ]

  name                = "pefuncapp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_function.name

  subnet_id = var.subnet_id_app

  private_service_connection {
    name                           = "pefuncapp${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = var.function_plan_sku == "FC1" ? azurerm_function_app_flex_consumption.function_app_flex_consumption[0].id : azurerm_linux_function_app.function_app_premium_plan[0].id
    subresource_names              = [
      "sites"]
  }

  private_dns_zone_group {
    name = "zoneconn${var.function_plan_sku == "FC1" ? azurerm_function_app_flex_consumption.function_app_flex_consumption[0].name : azurerm_linux_function_app.function_app_premium_plan[0].name}"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
    ]
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########## Finalize settings on the app registration
##########
##########

## Add an identifier URI (essentially the aud claim) to the app registration
##
resource "azuread_application_identifier_uri" "function_app_uri" {
  application_id = azuread_application.app_reg_function.id
  identifier_uri = "api://${azuread_application.app_reg_function.client_id}"
}

## Add a federated identity credential to the app registration to avoid using a client secret and instead
## exchange the token from the user-assigned managed identity for the Function App
resource "azuread_application_federated_identity_credential" "function_app_fic" {
  application_id = azuread_application.app_reg_function.id
  display_name   = "function_umi"
  description    = "Federated credential associated to user-assigned managed identity assigned to Azure Function"
  issuer         = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
  subject        = azurerm_user_assigned_identity.umi_function.principal_id
  audiences      = ["api://AzureADTokenExchange"]
}
