########## Create resources required for tag data
##########
##########

## Use time_static to generate a timestamp which will be used in created_date tag. Use this instead of timestamp
## so Terraform doesn't freak out every time apply is run again
##
resource "time_static" "created" {}

########## Create core resources
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_aml_workspace" {
  name     = "rgamlws${var.region_code}${var.random_string}"
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
  depends_on = [
    azurerm_resource_group.rg_aml_workspace
  ]

  name                = "lawamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Wait 60 seconds to ensure that the Log Analytics Workspace is fully provisioned to avoid errors
## when creating Application Insights
resource "time_sleep" "wait_log_analytics_workspace" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  create_duration = "60s"
}

########## Create network security perimeter resources to restrict public inbound and outbound access
########## for AML workspace resources
##########

## Create a Network Security Perimeter that will be used to restrict access to resources that support
## the AML workspace
resource "azurerm_network_security_perimeter" "nsp_aml_resources" {
  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "nspamlres${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
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
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_aml_resources" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_network_security_perimeter.nsp_aml_resources.id
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
## to store the secrets for connections in the AML workspace
resource "azurerm_network_security_perimeter_profile" "profile_nsp_aml_key_vault_secrets" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  name                          = "pkvamlsec"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_aml_resources.id
}

## Create an access rule to allow the AML workspace to access the Key Vault instance to store and retrieve
## secrets for workspace connections. This traffic occurs over the Microsoft public backbone
resource "azurerm_network_security_perimeter_access_rule" "access_rule_key_vault_aml_secrets_sub_id" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_secrets
  ]

  name                                  = "aramlkvsectrustedsubs"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_secrets.id
  direction                             = "Inbound"
  subscription_ids                        = [
    data.azurerm_subscription.current.id
  ]
}

## Create a Network Security Perimeter profile that will be associated with the storage account
## used as the default storage account for the AML workspace
resource "azurerm_network_security_perimeter_profile" "profile_nsp_aml_storage_default" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  name                          = "pstdef"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_aml_resources.id
}

## Create an access rule to allow the AML workspace to access the default storage account
## for the workspace which stores job logs, user profiles, and other AML artifacts. This traffic
## occurs over the Microsoft public backbone
resource "azurerm_network_security_perimeter_access_rule" "access_rule_aml_storage_default_sub_id" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_default
  ]

  name                                  = "arstdeftrustedsubs"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_default.id
  direction                             = "Inbound"
  subscription_ids                        = [
    data.azurerm_subscription.current.id
  ]
}

## Create a Network Security Perimeter profile that will be associated with the Azure Container
## Registry instance used by the AML workspace. The registry is used to store custom container images
## for custom enivronments
resource "azurerm_network_security_perimeter_profile" "profile_nsp_aml_acr" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  name                          = "pamlacr"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_aml_resources.id
}

## Create a Network Security Perimeter profile that will be associated with the storage account
## used to store data for the workspace to test AML functionality
resource "azurerm_network_security_perimeter_profile" "profile_nsp_aml_storage_data" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  name                          = "pstdata"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_aml_resources.id
}

## Create an access rule to allow the AML workspace to access the storage account that will
## be used as a data storage location for testing AML functionality. Preview of this data
## from the workspace flows over the Microsoft public backbone
resource "azurerm_network_security_perimeter_access_rule" "access_rule_aml_storage_data_sub_id" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_data
  ]

  name                                  = "arstdatatrustedsubs"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_data.id
  direction                             = "Inbound"
  subscription_ids                        = [
    data.azurerm_subscription.current.id
  ]
}

## Create a Network Security Perimeter profile that will be associated with the Key Vault
## instance used to store the key for CMK used to encrypt the workspace
resource "azurerm_network_security_perimeter_profile" "profile_nsp_aml_key_vault_cmk" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_aml_resources
  ]

  count = var.workspace_encryption == "cmk" ? 1 : 0

  name                          = "pkvamlcmk"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_aml_resources.id
}

## Create an access rule to allow the AML workspace to access the storage account that will
## be used as a data storage location for testing AML functionality. Preview of this data
## from the workspace flows over the Microsoft public backbone
resource "azurerm_network_security_perimeter_access_rule" "access_rule_aml_key_vault_cmk_sub_id" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_cmk[0]
  ]

  count = var.workspace_encryption == "cmk" ? 1 : 0

  name                                  = "arkvcmktrustedsubs"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_cmk[0].id
  direction                             = "Inbound"
  subscription_ids                        = [
    data.azurerm_subscription.current.id
  ]
}

########## Create dependent resources required by Azure Machine Learning Workspace
##########
##########

## Create Application Insights instance. This will be used by the AML Workspace
## to collect metrics and logs
resource "azurerm_application_insights" "appins_aml_workspace" {
  depends_on = [
    time_sleep.wait_log_analytics_workspace
  ]

  name                = "appinsamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  application_type    = "other"
  tags                = local.tags

  # Disable access keys and restrict to Entra ID authentication
  local_authentication_enabled = false

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create Azure Storage account which will be used as the default storage account for the AML workspace
##
resource "azurerm_storage_account" "storage_account_default_aml_workspace" {
  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "stamlws${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region
  # Add an additional tag specific to my environment
  tags = merge(local.tags, { SecurityControl = "Ignore" })

  ## Create a system-assigned managed identity for the storage account which is used to access the CMK
  ## from the AML Workspace from Key Vault if the workspace is encrypted with a CMK
  identity {
    type = "SystemAssigned"
  }

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  # TODO: 8/2026 - Remove this section once NSP Links are fully GA
  network_rules {
    default_action = "Deny"
    # This is only required for my lab environment
    ip_rules = [
      var.trusted_ip
    ]
    # Create resource access rule to allow workspaces within the subscription network access through the storage service firewall
    # This is more strict than allowing Trusted Azure Services bypass
    private_link_access {
      endpoint_resource_id = "/subscriptions/${var.subscription_id_workload}/resourceGroups/${azurerm_resource_group.rg_aml_workspace.name}/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the AML Workspace default storage account for blob, file, queue, and table services to 
## send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_storage_default_aml_workspace_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_default_aml_workspace.id}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_default_aml_workspace_file" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_default_aml_workspace_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_default_aml_workspace.id}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_default_aml_workspace_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_default_aml_workspace_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_default_aml_workspace.id}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_default_aml_workspace_table" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_default_aml_workspace_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_default_aml_workspace.id}/tableServices/default"
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

## Associate the default storage account to the relevant profile in the Network Security Perimeter
##
resource "azurerm_network_security_perimeter_association" "assoc_default_storage_account_aml_workspace" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_default_aml_workspace_table,
    azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_default
  ]

  name = "assocstdefaml"
  # TODO: 8/2026 Switch NSP to enforced mode once NSP Links are GA
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_storage_default.id
  resource_id                           = azurerm_storage_account.storage_account_default_aml_workspace.id
}

## Create Key Vault that will hold secrets for AML Workspace connections that use API keys
##
resource "azurerm_key_vault" "key_vault_secrets_aml_workspace" {
  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "kvsecamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  # Add an additional tag specific to my environment
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

  # TODO: 8/2026 - Remove this section once NSP Links are fully GA
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

## Create diagnostic settings for the AML Workspace Key Vault to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_aml_workspace" {
  depends_on = [
    azurerm_key_vault.key_vault_secrets_aml_workspace
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_secrets_aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Associate the default storage account to the relevant profile in the Network Security Perimeter
##
resource "azurerm_network_security_perimeter_association" "assoc_key_vault_secrets_aml_workspace" {
  depends_on = [
    azurerm_key_vault.key_vault_secrets_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_key_vault_aml_workspace,
    azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_secrets
  ]

  name = "assockvsecaml"
  # TODO: 8/2026 Switch NSP to enforced mode once NSP Links are GA
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_secrets.id
  resource_id                           = azurerm_key_vault.key_vault_secrets_aml_workspace.id
}

## Create an Azure Container Registry instance for use by the AML Workspace
##
resource "azurerm_container_registry" "acr_aml_workspace" {
  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "acramlws${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region
  tags                = local.tags

  # Premium SKU required for Private Endpoints
  sku = "Premium"

  # Disable the local admin user of the Container Registry
  admin_enabled = false

  # Disable anonymous pull access
  anonymous_pull_enabled = false

  identity {
    type = "SystemAssigned"
  }

  public_network_access_enabled = false
  network_rule_set {
    default_action = "Deny"
  }
  network_rule_bypass_option = "AzureServices"

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AML Workspace Container Registry to send logs to workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_acr_aml_workspace" {
  depends_on = [
    azurerm_container_registry.acr_aml_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr_aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

########## Create another storage account that is used for user data storage
##########
##########

## Create Azure Storage account which will be used for user data storage to experiment with the workspace
##
resource "azurerm_storage_account" "storage_account_data" {
  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "stamldata${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region
  # TODO: 2/2026 - Remove this section once I add NSPs to the lab
  # Add an additional tag specific to my environment
  tags = merge(local.tags, { SecurityControl = "Ignore" })


  ## Create a system-assigned managed identity for the storage account which is used to access the CMK
  ## from the AML Workspace Key Vault for configuring encryption scopes
  identity {
    type = "SystemAssigned"
  }

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  # TODO: 2/2026 - Moidfy this section to set all public access to disabled with no exceptions once I add NSP support to the lab
  network_rules {
    # Block all public access by default
    default_action = "Deny"

    # Create resource access rule to allow workspaces within the subscription network access through the storage service firewall
    private_link_access {
      endpoint_resource_id = "/subscriptions/${var.subscription_id_workload}/resourceGroups/${azurerm_resource_group.rg_aml_workspace.name}/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the data storage account for blob, file, queue, and table services to 
## send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_storage_data_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_data
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_data.id}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_data_file" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_monitor_diagnostic_setting.diag_storage_data_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_data.id}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_data_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_monitor_diagnostic_setting.diag_storage_data_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_data.id}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_data_table" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_monitor_diagnostic_setting.diag_storage_data_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_data.id}/tableServices/default"
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

########## Create the resources required when the AML Workspace to support CMK encryption of the workspace
##########
##########

## Create the Azure Key Vault instance which will be used to store the key to support CMK encryption of the AML Workspace
##
resource "azurerm_key_vault" "key_vault_cmk_aml_workspace" {
  count = var.workspace_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "kvcmkaml${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  # Add an additional tag specific to my environment
  tags = merge(local.tags, { SecurityControl = "Ignore" })

  sku_name = "standard"

  # If the workspace uses a user-asigned managed identity configure the AML Workspace to use a RBAC
  # if it uses a system-assigned managed identity RBAC will not work and it will need to use access policies
  rbac_authorization_enabled = var.key_vault_cmk_rbac_enabled ? true : false 

  # Turn on purge protection because it is required for CMK usage
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Not required for this implementation
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  # TODO: 8/2026 - Remove this section once NSP Links are fully GA
  network_acls {
    default_action             = "Allow"
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

## Create diagnostic settings for Key Vault used to store the CMK for the AML Workspace to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_cmk_aml_workspace" {
  count = var.workspace_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Associate the Key Vault used to store the CMK used to encrypt the AML workspace
##
resource "azurerm_network_security_perimeter_association" "assoc_key_vault_cmk_aml_workspace" {
  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_key_vault_cmk_aml_workspace,
    azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_cmk
  ]

  count = var.workspace_encryption == "cmk" ? 1 : 0

  name = "assockvcmkaml"
  # TODO: 8/2026 Switch NSP to enforced mode once NSP Links are GA
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_aml_key_vault_cmk[0].id
  resource_id                           = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
}

## Required ONLY FOR MY LAB to allow the service principal my lab machine uses to deploy this template
## to access the Key Vault when the AML workspace is configured with a system-assigned managed identity and
## CMK encryption. It allows the service principal to check the state of the key
resource "azurerm_key_vault_access_policy" "access_policy_terraform_aml_workspace_key_permissions" {
  count = var.workspace_encryption == "cmk" && ( !var.key_vault_cmk_rbac_enabled || var.workspace_managed_identity == "smi") ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_network_security_perimeter_association.assoc_key_vault_cmk_aml_workspace
  ]

  key_vault_id = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "Create",
    "Delete",
    "List",
    "Update",
    "Import",
    "Recover",
    "Backup",
    "Restore",
    "GetRotationPolicy",
    "SetRotationPolicy",
    "Rotate"
  ]
}

## Grant the user-assigned managed identity for the AML workspace permissions to use keys in Key Vault for CMK encryption/decryption operations
## This is only created when a user-assigned managed identity is set for the workspace, the workspace is set to use a CMK, and the Key Vault is set to use access policies
resource "azurerm_key_vault_access_policy" "access_policy_umi_workspace_key_permissions" {

  count = var.workspace_encryption == "cmk" && !var.key_vault_cmk_rbac_enabled && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault_access_policy.access_policy_terraform_aml_workspace_key_permissions
  ]

  key_vault_id = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id

  # Minimum permissions required for CMK usage (encrypt/decrypt operations)
  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey",
    "Sign",
    "Recover"
  ]
}

## Grant the system-assigned managed identity for the default storage account permissions to use keys in Key Vault for CMK encryption/decryption operations
## This is only created when a user-assigned managed identity is set for the workspace, the workspace is set to use a CMK, and the Key Vault is set to use access policies
resource "azurerm_key_vault_access_policy" "access_policy_smi_default_storage_account_key_permissions" {

  count = var.workspace_encryption == "cmk" && !var.key_vault_cmk_rbac_enabled && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_key_vault_access_policy.access_policy_smi_default_storage_account_key_permissions
  ]

  key_vault_id = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_storage_account.storage_account_default_aml_workspace.identity[0].principal_id

  # Minimum permissions required for CMK usage (encrypt/decrypt operations)
  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey",
    "Recover"
  ]
}

## Create the CMK that will be used to encrypt the AML Workspace
##
resource "azurerm_key_vault_key" "key_cmk_aml_workspace" {
  count = var.workspace_encryption == "cmk" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_key_vault_access_policy.access_policy_terraform_aml_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_umi_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_smi_default_storage_account_key_permissions
  ]

  name         = "cmkamlws"
  key_vault_id = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  key_type     = "RSA"

  # Don't use less than 4096 or else it will be upped to 4096 causing recreation of the key on every re-apply
  key_size = 4096
  key_opts = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  # Prevent Terraform from deleting and recreating the key on each apply
  lifecycle {
    ignore_changes = [
      expiration_date,
      not_before_date,
      tags,
      rotation_policy
    ]
  }
}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the storage account system-assigned managed identity
## the Key Vault Crypto Service Encryption User role. This grants the storage account to use the CMK in the Key Vault for encryption operations.
## This is only required if the workspace is configured to use a user-assigned managed identity and the Key Vault is configured to use RBAC for access control
resource "azurerm_role_assignment" "workspace_smi_storage_account_key_vault_key_vault_crypto_service_encryption_user" {
  count = var.workspace_encryption == "cmk" && var.key_vault_cmk_rbac_enabled && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_storage_account.storage_account_default_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.identity[0].principal_id}${azurerm_key_vault.key_vault_cmk_aml_workspace[0].name}keyvaultserviceencryptionuser")
  scope                = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.storage_account_default_aml_workspace.identity[0].principal_id
}

## Sleep for 120 seconds to allow RBAC role assignment to propagate before creating encryption scope
##
resource "time_sleep" "wait_120_seconds_for_storage_key_vault_rbac_propagation" {
  count = var.workspace_encryption == "cmk" && var.key_vault_cmk_rbac_enabled && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.workspace_smi_storage_account_key_vault_key_vault_crypto_service_encryption_user
  ]

  create_duration = "120s"
}

## Create an encryption scope for the default storage account that uses the CMK in the Key Vault for encryption operations for the storage account. 
## This is only required if the workspace is configured to use a user-assigned managed identity and the Key Vault is configured to use access policies for permissions management
resource "azapi_resource" "encryption_scope_default_storage_account" {
  count = var.workspace_encryption == "cmk" && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault_access_policy.access_policy_terraform_aml_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_umi_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_smi_default_storage_account_key_permissions,
    time_sleep.wait_120_seconds_for_storage_key_vault_rbac_propagation
  ]

  type      = "Microsoft.Storage/storageAccounts/encryptionScopes@2026-04-01"
  name      = "cmk-default"
  parent_id = azurerm_storage_account.storage_account_default_aml_workspace.id

  body = {
    properties = {
      source = "Microsoft.KeyVault"
      state = "Enabled"
      keyVaultProperties = {
        keyUri = azurerm_key_vault_key.key_cmk_aml_workspace[0].id
      }
      requireInfrastructureEncryption = true
    }
  }

  lifecycle {
    ignore_changes = [
      # Deal with the stupidity of Azure APIs returning different case sensitivity
      body.properties.source
    ]
  }
}

########## Create the private endpoints for the supporting resources
##########
##########

## Create a Private Endpoint for AML Workspace default storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_default_aml_workspace_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace
  ]

  name                = "pe${azurerm_storage_account.storage_account_default_aml_workspace.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_default_aml_workspace.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_default_aml_workspace.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_default_aml_workspace.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_default_aml_workspace.name}blob"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace storage account file endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_default_aml_workspace_file" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob
  ]

  name                = "pe${azurerm_storage_account.storage_account_default_aml_workspace.name}file"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_default_aml_workspace.name}file"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_default_aml_workspace.name}file"
    private_connection_resource_id = azurerm_storage_account.storage_account_default_aml_workspace.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_default_aml_workspace.name}file"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace default storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_default_aml_workspace_table" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_file
  ]

  name                = "pe${azurerm_storage_account.storage_account_default_aml_workspace.name}table"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_default_aml_workspace.name}table"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_default_aml_workspace.name}table"
    private_connection_resource_id = azurerm_storage_account.storage_account_default_aml_workspace.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_default_aml_workspace.name}table"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace default storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_default_aml_workspace_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_table
  ]

  name                = "pe${azurerm_storage_account.storage_account_default_aml_workspace.name}queue"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_default_aml_workspace.name}queue"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_default_aml_workspace.name}queue"
    private_connection_resource_id = azurerm_storage_account.storage_account_default_aml_workspace.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_default_aml_workspace.name}queue"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace Key Vault used to store secret for AML connections
##
resource "azurerm_private_endpoint" "pe_key_vault_secrets_aml_workspace" {
  depends_on = [
    azurerm_key_vault.key_vault_secrets_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_queue
  ]

  name                = "pe${azurerm_key_vault.key_vault_secrets_aml_workspace.name}vault"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_secrets_aml_workspace.name}vault"

  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_secrets_aml_workspace.name}vault"
    private_connection_resource_id = azurerm_key_vault.key_vault_secrets_aml_workspace.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_secrets_aml_workspace.name}vault"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace Container Registry
##
resource "azurerm_private_endpoint" "pe_container_registry_aml_workspace" {
  depends_on = [
    azurerm_container_registry.acr_aml_workspace,
    azurerm_private_endpoint.pe_key_vault_secrets_aml_workspace
  ]

  name                = "pe${azurerm_container_registry.acr_aml_workspace.name}registry"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_container_registry.acr_aml_workspace.name}registry"

  private_service_connection {
    name                           = "peconn${azurerm_container_registry.acr_aml_workspace.name}registry"
    private_connection_resource_id = azurerm_container_registry.acr_aml_workspace.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_container_registry.acr_aml_workspace.name}registry"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace data storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_data_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_data
  ]

  name                = "pe${azurerm_storage_account.storage_account_data.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_data.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_data.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_data.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_data.name}blob"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace data storage account file endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_data_file" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_private_endpoint.pe_storage_account_data_blob
  ]

  name                = "pe${azurerm_storage_account.storage_account_data.name}file"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_data.name}file"
  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_data.name}file"
    private_connection_resource_id = azurerm_storage_account.storage_account_data.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_data.name}file"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace data storage account table endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_data_table" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_private_endpoint.pe_storage_account_data_file
  ]

  name                = "pe${azurerm_storage_account.storage_account_data.name}table"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_data.name}table"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_data.name}table"
    private_connection_resource_id = azurerm_storage_account.storage_account_data.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_data.name}table"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace data storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_data_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_private_endpoint.pe_storage_account_data_table
  ]

  name                = "pe${azurerm_storage_account.storage_account_data.name}queue"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_data.name}queue"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_data.name}queue"
    private_connection_resource_id = azurerm_storage_account.storage_account_data.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_data.name}queue"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace data storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_data_dfs" {
  depends_on = [
    azurerm_storage_account.storage_account_data,
    azurerm_private_endpoint.pe_storage_account_data_queue
  ]

  name                = "pe${azurerm_storage_account.storage_account_data.name}dfs"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_data.name}dfs"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_data.name}dfs"
    private_connection_resource_id = azurerm_storage_account.storage_account_data.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_data.name}dfs"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########## Create a user-assigned managed identity for the AML workspace and give it appropriate permissions over the resource group
########## and dependent resources if the workspace_managed_identity variable is set to 'umi'
##########

## Create the user-assigned managed identity for the workspace
##
resource "azurerm_user_assigned_identity" "umi_aml_workspace" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  name                = "umiamlws${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Sleep for 10 seconds to give the user-assigned managed identity time to replicate across Entra ID
##
resource "time_sleep" "wait_umi_aml_workspace" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  create_duration = "10s"
}

## Create an Azure RBAC role assignment on the resource group containing the workspace granting the AML workspace user-assigned managed identity
## the Azure AI Administrator role. This grants the workspace permissions to manage the resources the workspace is dependent on
##
resource "azurerm_role_assignment" "workspace_umi_azure_ai_administrator" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace,
    time_sleep.wait_umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_resource_group.rg_aml_workspace.name}azureaiadministrator")
  scope                = azurerm_resource_group.rg_aml_workspace.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the resource group containing the workspace granting the AML workspace user-assigned managed identity
## the Azure AI Enterprise Network Connection Approver role. This grants the workspace permissions to approve managed private endpoints for resources
## that need to be accessible by compute in the managed virtual network
resource "azurerm_role_assignment" "workspace_umi_azure_ai_enterprise_network_connection_approver" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace,
    azurerm_role_assignment.workspace_umi_azure_ai_administrator
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_resource_group.rg_aml_workspace.name}networkconnectionapprover")
  scope                = azurerm_resource_group.rg_aml_workspace.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the AML workspace user-assigned managed identity
## the Key Vault Administrator role. This grants the workspace permission to create and manage connection secrets in the Key Vault
## 
resource "azurerm_role_assignment" "workspace_umi_workspace_key_vault_secrets_key_vault_administrator" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_secrets_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_key_vault.key_vault_secrets_aml_workspace.name}keyvaultadministrator")
  scope                = azurerm_key_vault.key_vault_secrets_aml_workspace.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace default storage account granting the AML workspace user-assigned managed identity
## the Storage Blob Data Contributor. This grants the workspace permissions to create containers and blobs required for
## workspace operations.
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_default_blob_data_contributor" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_storage_account.storage_account_default_aml_workspace.name}blobdatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace default storage account granting the AML workspace user-assigned managed identity
## the Storage File Data Privileged Contributor role. This grants the workspace permissions to create file shares and files
## for workspace operations.
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_default_file_data_privileged_contributor" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_storage_account.storage_account_default_aml_workspace.name}filedataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace default storage account granting the AML workspace user-assigned managed identity
## the Storage Table Data Contributor role. This is required to support batch operations and batch endpoints.
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_default_table_data_contributor" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_file_data_privileged_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_storage_account.storage_account_default_aml_workspace.name}tabledatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace default storage account granting the AML workspace user-assigned managed identity
## the Storage Queue Data Contributor role. This is required to support batch operaitons and endpoints
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_default_queue_data_contributor" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_table_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_storage_account.storage_account_default_aml_workspace.name}queuedatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the AML workspace user-assigned managed identity
## the Reader role on the private endpoint for the blob endpoint of the workspace default storage account. This is required 
## to preview the contents of a blob in the AML Studio UI
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_default_private_endpoint_blob_reader" {
  count = var.workspace_encryption == "cmk" && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob.id}reader")
  scope                = azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the AML workspace user-assigned managed identity
## the Reader role on the private endpoint for the blob endpoint of the data storage account. This is required 
## to preview the contents of a blob in the AML Studio UI
resource "azurerm_role_assignment" "workspace_umi_workspace_storage_account_data_private_endpoint_blob_reader" {
  count = var.workspace_encryption == "cmk" && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_private_endpoint.pe_storage_account_data_blob.id}reader")
  scope                = azurerm_private_endpoint.pe_storage_account_data_blob.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the AML workspace user-assigned managed identity
## the Key Vault Crypto User role. This grants the workspace permission to use the CMK in the Key Vault for encryption operations.
#resource "azurerm_role_assignment" "workspace_umi_workspace_key_vault_cmk_key_vault_administrator" {
#  count = var.workspace_encryption == "cmk" && var.workspace_managed_identity == "umi" ? 1 : 0

#  depends_on = [
#    azurerm_key_vault.key_vault_cmk_aml_workspace,
#    azurerm_user_assigned_identity.umi_aml_workspace
#  ]

#  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_key_vault.key_vault_cmk_aml_workspace[0].name}keyvaultadministrator")
#  scope                = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
#  role_definition_name = "Key Vault Administrator"
#  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
#}

## Create an Azure RBAC role assignment on the workspace Key Vault granting the AML workspace user-assigned managed identity
## the Key Vault Crypto User role. This grants the workspace permission to use the CMK in the Key Vault for encryption operations.
resource "azurerm_role_assignment" "workspace_umi_workspace_key_vault_key_vault_crypto_user" {
  count = var.workspace_encryption == "cmk" && var.workspace_managed_identity == "umi" ? 1 : 0

  depends_on = [
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  name                 = uuidv5("dns", "${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}${azurerm_key_vault.key_vault_cmk_aml_workspace[0].name}keyvaultcryptouser")
  scope                = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Pause for 120 seconds to allow role assignments to propagate
##
resource "time_sleep" "workspace_umi_required_role_assignments" {
  count = var.workspace_managed_identity == "umi" ? 1 : 0
  depends_on = [
    azurerm_role_assignment.workspace_umi_azure_ai_administrator,
    azurerm_role_assignment.workspace_umi_azure_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.workspace_umi_workspace_key_vault_secrets_key_vault_administrator,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_blob_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_file_data_privileged_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_table_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_queue_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_private_endpoint_blob_reader,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_data_private_endpoint_blob_reader,
    #azurerm_role_assignment.workspace_umi_workspace_key_vault_cmk_key_vault_administrator
    azurerm_role_assignment.workspace_umi_workspace_key_vault_key_vault_crypto_user
  ]

  create_duration = "120s"
}

########## Create the AML Workspace and its diagnostic settings
##########
##########

## Create the AML Workspace
## TODO: 8/2026 Switch this to AzureRM provider is more robust
resource "azapi_resource" "aml_workspace" {
  depends_on = [
    # Core resources
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_application_insights.appins_aml_workspace,
    azurerm_container_registry.acr_aml_workspace,
    azurerm_storage_account.storage_account_default_aml_workspace,
    azurerm_key_vault.key_vault_secrets_aml_workspace,
    azurerm_storage_account.storage_account_data,

    # Permissions
    azurerm_role_assignment.workspace_umi_azure_ai_administrator,
    azurerm_role_assignment.workspace_umi_azure_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.workspace_umi_workspace_key_vault_secrets_key_vault_administrator,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_blob_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_file_data_privileged_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_table_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_queue_data_contributor,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_default_private_endpoint_blob_reader,
    azurerm_role_assignment.workspace_umi_workspace_storage_account_data_private_endpoint_blob_reader,
    time_sleep.workspace_umi_required_role_assignments,

    # CMK-specific
    azurerm_key_vault.key_vault_cmk_aml_workspace,
    azurerm_key_vault_key.key_cmk_aml_workspace,
    #azurerm_role_assignment.workspace_umi_workspace_key_vault_cmk_key_vault_administrator,
    azurerm_role_assignment.workspace_umi_workspace_key_vault_key_vault_crypto_user,
    azurerm_key_vault_access_policy.access_policy_terraform_aml_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_umi_workspace_key_permissions,
    azurerm_key_vault_access_policy.access_policy_smi_default_storage_account_key_permissions,
    azurerm_role_assignment.workspace_smi_storage_account_key_vault_key_vault_crypto_service_encryption_user,
    azapi_resource.encryption_scope_default_storage_account
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2026-03-01"
  name                      = "amlws${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aml_workspace.id
  location                  = var.region
  schema_validation_enabled = true
  tags = local.tags

  body = {
    identity = var.workspace_managed_identity == "umi" ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.umi_aml_workspace[0].id) = {}
      }
      } : {
      type                   = "SystemAssigned"
      userAssignedIdentities = null
    }

    # Create an AML Workspace
    kind = "Default"

    properties = {
      friendlyName = "Sample-AML-Workspace"
      description  = "This is a sample AML Workspace"

      applicationInsights = azurerm_application_insights.appins_aml_workspace.id
      keyVault            = azurerm_key_vault.key_vault_secrets_aml_workspace.id
      storageAccount      = azurerm_storage_account.storage_account_default_aml_workspace.id
      containerRegistry   = azurerm_container_registry.acr_aml_workspace.id

      # Enable the HBI feature to encrypt temporary disks on AML compute
      hbiWorkspace = true

      # Enable service-side encryption if workspace is configured to use CMK encryption to ensure workspace metadata is encrypted with the CMK
      enableServiceSideCMKEncryption = var.workspace_encryption == "cmk" ? true : false

      # Specify the the CMK used to encrypt the AML workspace if the workspace is configured to use CMK encryption
      encryption = var.workspace_encryption == "cmk" ? {
        status = "Enabled"
        identity = var.workspace_managed_identity == "umi" ? {
          userAssignedIdentity = azurerm_user_assigned_identity.umi_aml_workspace[0].id
        } : null

        keyVaultProperties = {
          keyVaultArmId = azurerm_key_vault.key_vault_cmk_aml_workspace[0].id
          keyIdentifier = azurerm_key_vault_key.key_cmk_aml_workspace[0].id
        }
      } : null

      primaryUserAssignedIdentity = var.workspace_managed_identity == "umi" ? azurerm_user_assigned_identity.umi_aml_workspace[0].id : null

      # Block access to the AML Workspace over the public endpoint
      publicNetworkAccess = "Disabled"
      managedNetwork = {
        # Managed virtual network will block all outbound traffic unless explicitly allowed
        isolationMode = "AllowOnlyApprovedOutbound"
        # Use Azure Firewall Standard SKU to support FQDN-based rules
        firewallSku = "Standard"
        # TODO: 8/2026 Switch to V2 once PG fixes issue where managed virtual network is provisioned 
        # with open Internet access
        managedNetworkKind = "V1"
        outboundRules = merge(
          {
          },
          local.vscode_ssh_outbound_fqdn_rules,
          local.python_library_outbound_fqdn_rules,
          local.conda_library_outbound_fqdn_rules,
          local.docker_outbound_fqdn_rules,
          local.huggingface_outbound_fqdn_rules,
          local.user_defined_outbound_batch_pe_rules,
          local.user_defined_outbound_custom_pe_rules,
          # This ruleset is only required for the lab and allows access to GitHub for sample files
          local.user_defined_outbound_fqdn_rules
        )
      }

      # Set the authentication for system datastores to use the managed identity of the workspace instead of storing the API keys as secrets in Key Vault
      systemDatastoresAuthMode = "identity"
    }
  }

  response_export_values = [
    "identity.principalId",
    "properties.workspaceId",
  ]

  # Ignore updates to these tags on additional Terraform deployments
  lifecycle {
    ignore_changes = [
      tags["created_by"],
      # Deal with the stupidity of Azure APIs returning different case sensitivity
      body.properties.applicationInsights,
      body.properties.storageAccount,
      body.properties.keyVault,
      body.properties.containerRegistry,
      body.properties.encryption.identity.userAssignedIdentity,
      body.properties.primaryUserAssignedIdentity
    ]
  }
}

## Create diagnostic settings to capture resource logs from the AML Workspace and send them to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aml_workspace" {
  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  enabled_log {
    category = "AmlComputeCpuGpuUtilization"
  }
  enabled_log {
    category = "AmlRunStatusChangedEvent"
  }
  enabled_log {
    category = "ModelsChangeEvent"
  }
  enabled_log {
    category = "ModelsReadEvent"
  }
  enabled_log {
    category = "ModelsActionEvent"
  }
  enabled_log {
    category = "DeploymentReadEvent"
  }
  enabled_log {
    category = "DeploymentEventACI"
  }
  enabled_log {
    category = "DeploymentEventAKS"
  }
  enabled_log {
    category = "InferencingOperationAKS"
  }
  enabled_log {
    category = "InferencingOperationACI"
  }
  enabled_log {
    category = "EnvironmentChangeEvent"
  }
  enabled_log {
    category = "EnvironmentReadEvent"
  }
  enabled_log {
    category = "DataLabelChangeEvent"
  }
  enabled_log {
    category = "DataLabelReadEvent"
  }
  enabled_log {
    category = "ComputeInstanceEvent"
  }
  enabled_log {
    category = "DataStoreChangeEvent"
  }
  enabled_log {
    category = "DataStoreReadEvent"
  }
  enabled_log {
    category = "DataSetChangeEvent"
  }
  enabled_log {
    category = "DataSetReadEvent"
  }
  enabled_log {
    category = "PipelineChangeEvent"
  }
  enabled_log {
    category = "PipelineReadEvent"
  }
  enabled_log {
    category = "RunEvent"
  }
  enabled_log {
    category = "RunReadEvent"
  }
  enabled_log {
    category = "ManagedNetworkEvent"
  }
}

########## Create Private Endpoints for AML Workspace
##########
##########

## Create a Private Endpoint AML Workspace
##
resource "azurerm_private_endpoint" "pe_aml_workspace" {
  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                = "pe${azapi_resource.aml_workspace.name}workspace"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.aml_workspace.name}workspace"

  private_service_connection {
    name                           = "peconn${azapi_resource.aml_workspace.name}workspace"
    private_connection_resource_id = azapi_resource.aml_workspace.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.aml_workspace.name}workspace"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.notebooks.azure.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create the Private DNS record to support authentication to AML compute
##########
##########

## Create auth A record in the instances.azureml.ms private DNS zone for the AML Workspace
##
resource "azurerm_private_dns_a_record" "aml_compute_instance_dns_record_auth" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_private_endpoint.pe_aml_workspace
  ]

  name                = "auth.${var.region}"
  private_dns_zone_id = "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/instances.azureml.ms"
  ttl                 = 10
  records = [
    azurerm_private_endpoint.pe_aml_workspace.private_service_connection.0.private_ip_address
  ]
}

########## Create additional non-human Azure RBAC role assignments
##########
##########

## Create Azure RBAC role assignment granting the AML Workspace system-assigned managed identity the Reader role on the 
## AML Workspace default storage account's Private Endpoint for blob. This is required for operations where the workspace
## identity is used as a proxy to preview data in the storage account
resource "azurerm_role_assignment" "role_assignment_aml_workspace_storage_account_blob_pe_reader" {
  count = var.workspace_managed_identity == "smi" ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob,
    azapi_resource.aml_workspace
  ]

  scope                = azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob.id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.aml_workspace.output.identity.principalId
}

## Create Azure RBAC role assignment granting the AML Workspace system-assigned managed identity the 
## Azure AI Enterprise Network Connection Approver on the resource group containing the AML workspace and its resources
resource "azurerm_role_assignment" "role_assignment_aml_workspace_ai_enterprise_network_connection_approver" {
  count = var.workspace_managed_identity == "smi" ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_storage_account_default_aml_workspace_blob,
    azapi_resource.aml_workspace
  ]

  scope                = azurerm_resource_group.rg_aml_workspace.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azapi_resource.aml_workspace.output.identity.principalId
}

## Create Azure RBAC role assignment granting the AML Workspace system-assigned managed identity the Reader role on the 
## data storage account's Private Endpoint for blob. This is required for operations where the workspace
## identity is used as a proxy to preview data in the storage account
resource "azurerm_role_assignment" "role_assignment_data_storage_account_blob_pe_reader" {
  count = var.workspace_managed_identity == "smi" ? 1 : 0

  depends_on = [
    azurerm_private_endpoint.pe_storage_account_data_blob,
    azapi_resource.aml_workspace
  ]

  scope                = azurerm_private_endpoint.pe_storage_account_data_blob.id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.aml_workspace.output.identity.principalId
}

## Sleep for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_aml_workspace_smi_role_assignments" {
  count = var.workspace_managed_identity == "smi" ? 1 : 0
  depends_on = [
    azurerm_role_assignment.role_assignment_aml_workspace_storage_account_blob_pe_reader,
    azurerm_role_assignment.role_assignment_aml_workspace_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.role_assignment_data_storage_account_blob_pe_reader
  ]

  create_duration = "120s"
}

########## Create an Azure Machine Learning compute instance for the AML Workspace
########## 
##########

## Create a user-assigned managed identity for the compute instance
##
resource "azurerm_user_assigned_identity" "umi_compute_instance" {
  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_key_vault_access_policy.access_policy_umi_workspace_key_permissions,
    time_sleep.wait_aml_workspace_smi_role_assignments
  ]

  name                = "umi${local.compute_instance_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 10 seconds to allow the compute instance managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_umi_aml_compute_instance_identity" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_instance
  ]
  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML workspace default storage account to the compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_st_default_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_umi_aml_compute_instance_identity
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_instance.principal_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML workspace default storage account to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_st_default_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_st_default_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_instance.principal_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_aml_compute_instance_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_st_default_blob_data_contributor,
    azurerm_role_assignment.umi_compute_instance_st_default_file_data_privileged_contributor
  ]
  create_duration = "120s"
}

## Create the AML Compute Instance for the AML Workspace
##
resource "azurerm_machine_learning_compute_instance" "aml_compute_instance" {
  depends_on = [
    time_sleep.wait_umi_aml_compute_instance_role_assignments
  ]

  name                          = local.compute_instance_name
  tags                          = local.tags
  machine_learning_workspace_id = azapi_resource.aml_workspace.id

  virtual_machine_size = "Standard_D2s_v3"
  description          = "Compute instance for Jupyter notebooks and experiments"

  # Identity controls
  local_auth_enabled = false
  assign_to_user {
    object_id = var.user_object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_compute_instance.id
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create an A records for the compute instance in the private DNS zone to support access to the instance
##
resource "azurerm_private_dns_a_record" "aml_compute_instance_dns_record_main" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance
  ]

  name                = "${azurerm_machine_learning_compute_instance.aml_compute_instance.name}.${var.region}"
  private_dns_zone_id = "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/instances.azureml.ms"
  ttl                 = 10
  records = [
    azurerm_private_endpoint.pe_aml_workspace.private_service_connection.0.private_ip_address
  ]
}

resource "azurerm_private_dns_a_record" "aml_compute_instance_dns_record_ssh" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance
  ]

  name                = "${azurerm_machine_learning_compute_instance.aml_compute_instance.name}-22.${var.region}"
  private_dns_zone_id = "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/instances.azureml.ms"
  ttl                 = 10
  records = [
    azurerm_private_endpoint.pe_aml_workspace.private_service_connection.0.private_ip_address
  ]
}

########## Create an Azure Machine Learning compute cluster for the AML Workspace
########## 
##########

## Create a user-assigned managed identity for the compute cluster
##
resource "azurerm_user_assigned_identity" "umi_compute_cluster" {
  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance
  ]

  name                = "umi${local.compute_cluster_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Pause for 10 seconds to allow the compute cluster managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_umi_aml_compute_cluster_identity" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_cluster
  ]
  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML workspace default storage account to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_st_default_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_umi_aml_compute_cluster_identity
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML workspace default storage account to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_st_default_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_default_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage Table Data Contributor role on the
## AML workspace default storage account to the compute cluster user-assigned managed identity
## This supports batch
resource "azurerm_role_assignment" "umi_compute_cluster_st_default_table_data_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_default_file_data_privileged_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storagetabledatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage Queue Data Contributor role on the
## AML default storage account to the compute cluster user-assigned managed identity
## This supports batch
resource "azurerm_role_assignment" "umi_compute_cluster_st_default_queue_data_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_default_table_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storagequeuedatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPull role on the AML Workspace
## Container Registry to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_acr_pull" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_default_queue_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_container_registry.acr_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}acrpull")
  scope                = azurerm_container_registry.acr_aml_workspace.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPush role on the AML Workspace
## Container Registry to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_acr_push" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_acr_pull
  ]
  name                 = uuidv5("dns", "${azurerm_container_registry.acr_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}acrpush")
  scope                = azurerm_container_registry.acr_aml_workspace.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the AzureML Data Scientist role on the AML Workspace
## This allows the compute cluster to perform operations on workspace resource using its managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_azureml_data_scientist" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_acr_push
  ]
  name                 = uuidv5("dns", "${azapi_resource.aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}datascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_aml_compute_cluster_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_default_blob_data_contributor,
    azurerm_role_assignment.umi_compute_cluster_st_default_file_data_privileged_contributor,
    azurerm_role_assignment.umi_compute_cluster_st_default_table_data_contributor,
    azurerm_role_assignment.umi_compute_cluster_st_default_queue_data_contributor,
    azurerm_role_assignment.umi_compute_cluster_acr_pull,
    azurerm_role_assignment.umi_compute_cluster_acr_push,
    azurerm_role_assignment.umi_compute_cluster_azureml_data_scientist
  ]
  create_duration = "120s"
}

## Create the AML Compute Cluster for the AML Workspace
##
resource "azurerm_machine_learning_compute_cluster" "aml_compute_cluster" {
  depends_on = [
    time_sleep.wait_umi_aml_compute_cluster_role_assignments
  ]

  name                          = local.compute_cluster_name
  location                      = var.region
  machine_learning_workspace_id = azapi_resource.aml_workspace.id
  tags                          = local.tags

  description = "Compute cluster for building images, training, and experiments"

  vm_priority = "Dedicated"
  vm_size     = "Standard_D4s_v3"

  scale_settings {
    min_node_count                       = 0
    max_node_count                       = 1
    scale_down_nodes_after_idle_duration = "PT5M"
  }

  # Network controls
  node_public_ip_enabled = false

  # Identity controls
  local_auth_enabled = false
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_compute_cluster.id
    ]
  }
}

########## Patch the Azure Machine Learning Workspace to use the Compute Cluster
########## for environment builds
##########
resource "null_resource" "aml_patch_image_build_compute" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e

      WORKSPACE_NAME="${azapi_resource.aml_workspace.name}"
      RESOURCE_GROUP="${azurerm_resource_group.rg_aml_workspace.name}"
      COMPUTE_TARGET="${local.compute_cluster_name}"

      CURRENT_VALUE=$(az ml workspace show \
        --name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.imageBuildCompute \
        --output tsv)

      if [ "$CURRENT_VALUE" != "$COMPUTE_TARGET" ]; then
        echo "Patching imageBuildCompute from '$CURRENT_VALUE' to '$COMPUTE_TARGET' ..."
        az rest --method patch \
          --url "/subscriptions/${var.subscription_id_workload}/resourceGroups/${azurerm_resource_group.rg_aml_workspace.name}/providers/Microsoft.MachineLearningServices/workspaces/${azapi_resource.aml_workspace.name}?api-version=2026-05-01" \
          --body "{\"properties\":{\"imageBuildCompute\":\"$COMPUTE_TARGET\"}}"
      else
        echo "No patch needed: imageBuildCompute is already correct."
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

########## Create the human role assignments
##########
##########

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Data Scientist role to the user.
## This allows the user to perform all actions except for creating compute resources.
##
resource "azurerm_role_assignment" "wk_perm_data_scientist_project" {
  depends_on = [
    null_resource.aml_patch_image_build_compute
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_workspace.name}${var.user_object_id}${azapi_resource.aml_workspace.name}datascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage File Data Privileged Contributor role on the
## AML Workspace default storage account to the user within the scope of the file share used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_default_file_data_privileged_contributor" {
  depends_on = [
    null_resource.aml_patch_image_build_compute
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${var.user_object_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage Blob Data Contributor role on the
## AML Workspace default storage account to the user within the scope of the containers used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_default_blob_data_contributor" {
  depends_on = [
    azurerm_role_assignment.wk_pr_perm_st_default_file_data_privileged_contributor
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_default_aml_workspace.name}${var.user_object_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_default_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}