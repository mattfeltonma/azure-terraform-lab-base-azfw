########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_aml_workspace" {
  provider = azurerm.subscription_workload

  name     = "rgamlws${var.region_code}${var.random_string}"
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
resource "azurerm_log_analytics_workspace" "law_workload" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace
  ]

  name                = "lawamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name

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

## Pause for 60 seconds to allow the Log Analytics Workspace to be fully provisioned
## and mitigate risks of Application Insights creation failure due to workspace not being
## fully available
resource "time_sleep" "wait_log_analytics_workspace" {
  depends_on = [
    azurerm_log_analytics_workspace.law_workload
  ]

  create_duration = "60s"
}

########## Create dependent resources required by Azure Machine Learning Workspace
##########
##########

## Create Application Insights instance. This will be used by the AML Workspace
## to collect metrics and logs
resource "azurerm_application_insights" "appins_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_log_analytics_workspace
  ]

  name                = "appinsamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  workspace_id        = azurerm_log_analytics_workspace.law_workload.id
  application_type    = "other"
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Azure Storage account which will be used as the default storage account for the AML workspace
##
resource "azurerm_storage_account" "storage_account_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.law_workload
  ]

  name                = "stamlws${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region
  tags                = var.tags

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
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the AML Workspace default storage account for blob, file, queue, and table services to 
## send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_storage_aml_workspace_blob" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aml_workspace.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aml_workspace_file" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_aml_workspace_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aml_workspace.id}/fileServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aml_workspace_queue" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_aml_workspace_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aml_workspace.id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_aml_workspace_table" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_monitor_diagnostic_setting.diag_storage_aml_workspace_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_aml_workspace.id}/tableServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

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

## Create Key Vault that will hold secrets for AML Workspace connections that use API keys
##
resource "azurerm_key_vault" "key_vault_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.law_workload
  ]

  name                = "kvamlws${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = var.tags


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

## Create diagnostic settings for the AML Workspace Key Vault to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_key_vault.key_vault_aml_workspace
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create an Azure Container Registry instance for use by the AML Workspace
##
resource "azurerm_container_registry" "acr_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.law_workload
  ]

  name                = "acramlws${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  location            = var.region
  tags                = var.tags

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
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AML Workspace Container Registry to send logs to workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_acr_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_container_registry.acr_aml_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr_aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

########## Create the resources required when the AML Workspace to support CMK encryption of the workspace
##########
##########

## Create the Azure Key Vault instance which will be used to store the key to support CMK encryption of the AML Workspace
##
resource "azurerm_key_vault" "key_vault_aml_workspace_cmk" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.law_workload
  ]

  name                = "kvamlwscmk${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = var.tags

  sku_name = "standard"

  # Disable RBAC authorization and use local access policies because this is required for Service-Side Encryption with CMK for AML Workspaces
  rbac_authorization_enabled = true

  # Turn on purge protection because it is required for CMK usage
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Not required for this implementation
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []

    # This is only for my lab
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

## Create diagnostic settings for Key Vault used to store the CMK for the AML Workspace to send logs to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_aml_workspace_cmk" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_key_vault.key_vault_aml_workspace_cmk
  ]

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_aml_workspace_cmk.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create the CMK that will be used to encrypt the AML Workspace
##
resource "azurerm_key_vault_key" "key_aml_workspace_cmk" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_key_vault.key_vault_aml_workspace_cmk
  ]

  name         = "cmkamlws"
  key_vault_id = azurerm_key_vault.key_vault_aml_workspace_cmk.id
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

########## Create user-assigned managed identity for AML Workspace
##########
##########

## Create a user-assigned managed identity for the AML Workspace
##
resource "azurerm_user_assigned_identity" "umi_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_key_vault.key_vault_aml_workspace,
    azurerm_key_vault.key_vault_aml_workspace_cmk
  ]

  count = var.workspace_umi ? 1 : 0

  name                = "umi${local.workspace_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 10 seconds to allow the AML Workspace managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_umi_aml_workspace_identity" {
  depends_on = [
    azurerm_user_assigned_identity.umi_aml_workspace
  ]

  count = var.workspace_umi ? 1 : 0

  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Azure AI Administrator role on the
## resource group to the AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_azure_ai_administrator" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_workspace.name}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}azureaiadministrator")
  scope                = azurerm_resource_group.rg_aml_workspace.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create Azure RBAC Role Assignment granting the Azure AI Enterprise Network Connection Approver role on the
## resource group to the AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_azure_ai_enterprise_network_connection_approver" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_workspace.name}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}azureaiadministratorenterprisenetworkconnectionapprover")
  scope                = azurerm_resource_group.rg_aml_workspace.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create Azure RBAC Role Assignment granting Key Vault Administrator role on the 
## Key Vault that will be used to store connection secrets for the AML Workspace to the
## AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_kv_administrator" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_key_vault.key_vault_aml_workspace.id}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}keyvaultadministrator")
  scope                = azurerm_key_vault.key_vault_aml_workspace.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create Azure RBAC Role Assignment granting Key Vault Crypto User role on the
## Key Vault that holds the CMK for the AML Workspace to the AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_kv_crypto_user" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_key_vault.key_vault_aml_workspace_cmk.id}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}keyvaultcryptouser")
  scope                = azurerm_key_vault.key_vault_aml_workspace_cmk.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML Hub storage account to the AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_st_blob_data_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the AML Workspace user-assigned managed identity
resource "azurerm_role_assignment" "umi_aml_workspace_st_file_data_privileged_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_workspace_identity
  ]

  count = var.workspace_umi ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml_workspace[0].principal_id
}

## Pause for 120 seconds to allow for Azure RBAC Role Assignments to propagate
##
resource "time_sleep" "wait_aml_workspace_rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.umi_aml_workspace_azure_ai_administrator,
    azurerm_role_assignment.umi_aml_workspace_azure_ai_enterprise_network_connection_approver,
    azurerm_role_assignment.umi_aml_workspace_kv_administrator,
    azurerm_role_assignment.umi_aml_workspace_kv_crypto_user,
    azurerm_role_assignment.umi_aml_workspace_st_blob_data_contributor,
    azurerm_role_assignment.umi_aml_workspace_st_file_data_privileged_contributor
  ]

  count = var.workspace_umi ? 1 : 0

  create_duration = "120s"
}

########## Create the AML Workspace and its diagnostic settings
##########
##########

## Create the AML Workspace
##
resource "azapi_resource" "aml_workspace" {
  provider = azapi.subscription_workload

  depends_on = [
    azurerm_resource_group.rg_aml_workspace,
    azurerm_log_analytics_workspace.law_workload,
    azurerm_application_insights.appins_aml_workspace,
    azurerm_container_registry.acr_aml_workspace,
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_key_vault.key_vault_aml_workspace,
    azurerm_key_vault.key_vault_aml_workspace_cmk,
    azurerm_key_vault_key.key_aml_workspace_cmk,
    time_sleep.wait_aml_workspace_rbac_propagation
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-09-01"
  name                      = "amlws${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aml_workspace.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    identity = var.workspace_umi == true ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.umi_aml_workspace[0].id}" = {}
      }
      } : {
      type                   = "SystemAssigned"
      userAssignedIdentities = null
    }

    tags = var.tags

    # Create an AML Workspace
    kind = "Default"

    properties = merge({
      friendlyName = "Sample-AML-Workspace"
      description  = "This is a sample AML Workspace"

      applicationInsights = azurerm_application_insights.appins_aml_workspace.id
      keyVault            = azurerm_key_vault.key_vault_aml_workspace.id
      storageAccount      = azurerm_storage_account.storage_account_aml_workspace.id
      containerRegistry   = azurerm_container_registry.acr_aml_workspace.id

      # Enable the HBI feature to encrypt temporary disks on AML compute
      hbiWorkspace = true

      # Enable Service-Side CMK encryption which only supports the usage of system-assigned managed identities for the workspace at this time
      enableServiceSideCMKEncryption = true

      # Specify the the CMK used to encrypt the workspace and its metadata
      encryption = {
        status = "Enabled"
        keyVaultProperties = {
          keyVaultArmId = azurerm_key_vault.key_vault_aml_workspace_cmk.id
          keyIdentifier = azurerm_key_vault_key.key_aml_workspace_cmk.id
        }
      }

      # Block access to the AML Workspace over the public endpoint
      publicNetworkAccess = "Disabled"
      managedNetwork = {
        # Managed virtual network will block all outbound traffic unless explicitly allowed
        isolationMode = "AllowOnlyApprovedOutbound"
        # Use Azure Firewall Standard SKU to support FQDN-based rules
        firewallSku = "Standard"
        outboundRules = merge(
          {
          },
          local.vscode_ssh_outbound_fqdn_rules,
          local.python_library_outbound_fqdn_rules,
          local.conda_library_outbound_fqdn_rules,
          local.docker_outbound_fqdn_rules,
          local.huggingface_outbound_fqdn_rules,
          local.user_defined_outbound_pe_rules,
          # This ruleset is only required for the lab and allows access to GitHub for sample files
          local.user_defined_outbound_fqdn_rules
        )
      }

      # Set the authentication for system datastores to use the managed identity of the workspace instead of storing the API keys as secrets in Key Vault
      systemDatastoresAuthMode = "identity"

      },

      # If a user-assigned managed identity is being used, set the user-assigned managed identity ID
      var.workspace_umi == true ? {
        primaryUserAssignedIdentity = azurerm_user_assigned_identity.umi_aml_workspace[0].id
      } : {}
    )
  }

  response_export_values = [
    "identity.principalId",
    "properties.workspaceId",
  ]

  # Ignore updates to these tags on additional Terraform deployments
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"],
      # Azure API returns incorrect casing causing Terraform to try to change this properties
      # which cannot be modified after the workspace is created
      body.properties.applicationInsights,
      body.properties.keyVault
    ]
  }
}

## Create diagnostic settings to capture resource logs from the AML Workspace and send them to the workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_log_analytics_workspace.law_workload
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law_workload.id

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
}

########## Create Private Endpoints for AML Workspace and required resources in the customer virtual network
##########
##########

## Create a Private Endpoint AML Workspace
##
resource "azurerm_private_endpoint" "pe_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                = "pe${azapi_resource.aml_workspace.name}workspace"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags
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

## Create a Private Endpoint for AML Workspace default storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_aml_workspace_blob" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace
  ]

  name                = "pe${azurerm_storage_account.storage_account_aml_workspace.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_aml_workspace.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_aml_workspace.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_aml_workspace.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_aml_workspace.name}blob"
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

## Create a Private Endpoint for AML Workspace storage account file endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_aml_workspace_file" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_storage_account.storage_account_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_aml_workspace_blob
  ]

  name                = "pe${azurerm_storage_account.storage_account_aml_workspace.name}file"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_aml_workspace.name}file"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_aml_workspace.name}file"
    private_connection_resource_id = azurerm_storage_account.storage_account_aml_workspace.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_aml_workspace.name}file"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace Key Vault used to store secret for AML connections
##
resource "azurerm_private_endpoint" "pe_key_vault_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_key_vault.key_vault_aml_workspace,
    azurerm_private_endpoint.pe_storage_account_aml_workspace_file
  ]

  name                = "pe${azurerm_key_vault.key_vault_aml_workspace.name}vault"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_aml_workspace.name}vault"

  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_aml_workspace.name}vault"
    private_connection_resource_id = azurerm_key_vault.key_vault_aml_workspace.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_aml_workspace.name}vault"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for AML Workspace Container Registry
##
resource "azurerm_private_endpoint" "pe_container_registry_aml_workspace" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_container_registry.acr_aml_workspace,
    azurerm_private_endpoint.pe_key_vault_aml_workspace
  ]

  name                = "pe${azurerm_container_registry.acr_aml_workspace.name}registry"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags
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
      tags["created_date"],
      tags["created_by"]
    ]
  }
}



########## Create an Azure Machine Learning compute instance for the AML Workspace
########## 
##########

## Create a user-assigned managed identity for the compute instance
##
resource "azurerm_user_assigned_identity" "umi_compute_instance" {
  provider = azurerm.subscription_workload

  depends_on = [
    azapi_resource.aml_workspace
  ]

  name                = "umi${local.compute_instance_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags

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
## AML Hub storage account to the compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_st_blob_data_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_compute_instance_identity
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_instance.principal_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_st_file_data_privileged_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_role_assignment.umi_compute_instance_st_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_instance.principal_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_aml_compute_instance_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_st_blob_data_contributor,
    azurerm_role_assignment.umi_compute_instance_st_file_data_privileged_contributor
  ]
  create_duration = "120s"
}

## Create the AML Compute Instance for the AML Workspace
##
resource "azurerm_machine_learning_compute_instance" "aml_compute_instance" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_compute_instance_role_assignments
  ]

  name                          = local.compute_instance_name
  tags                          = var.tags
  machine_learning_workspace_id = azapi_resource.aml_workspace.id

  virtual_machine_size = "Standard_D4s_v3"
  description          = "Compute instance for Jupyter notebooks and experiments"

  # Identity controls
  local_auth_enabled = false
  assign_to_user {
    object_id = var.user_object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  # Network controls
  node_public_ip_enabled = false

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi_compute_instance.id
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
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
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
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
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
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance
  ]

  name                = "umi${local.compute_cluster_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_workspace.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
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
## AML Hub storage account to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_st_blob_data_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_compute_cluster_identity
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the development compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_st_file_data_privileged_contributor" {
  provider = azurerm.subscription_workload

  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPull role on the AML Workspace
## Container Registry to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_acr_pull" {
  provider = azurerm.subscription_workload
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_file_data_privileged_contributor
  ]
  name                 = uuidv5("dns", "${azurerm_container_registry.acr_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}acrpull")
  scope                = azurerm_container_registry.acr_aml_workspace.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPush role on the AML Workspace
## Container Registry to the compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_acr_push" {
  provider = azurerm.subscription_workload
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_acr_pull
  ]
  name                 = uuidv5("dns", "${azurerm_container_registry.acr_aml_workspace.name}${azurerm_user_assigned_identity.umi_compute_cluster.principal_id}acrpush")
  scope                = azurerm_container_registry.acr_aml_workspace.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_aml_compute_cluster_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_st_blob_data_contributor,
    azurerm_role_assignment.umi_compute_cluster_st_file_data_privileged_contributor,
    azurerm_role_assignment.umi_compute_cluster_acr_pull,
    azurerm_role_assignment.umi_compute_cluster_acr_push
  ]
  create_duration = "120s"
}

## Create the AML Compute Cluster for the AML Workspace
##
resource "azurerm_machine_learning_compute_cluster" "aml_compute_cluster" {
  provider = azurerm.subscription_workload

  depends_on = [
    time_sleep.wait_umi_aml_compute_cluster_role_assignments
  ]

  name                          = local.compute_cluster_name
  location                      = var.region
  machine_learning_workspace_id = azapi_resource.aml_workspace.id
  tags                          = var.tags

  description = "Compute cluster for building images, training, and experiments"

  vm_priority = "Dedicated"
  vm_size     = "Standard_D4s_v3"

  scale_settings {
    min_node_count                       = 0
    max_node_count                       = 1
    scale_down_nodes_after_idle_duration = "PT30S"
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

  depends_on = [
    azurerm_machine_learning_compute_cluster.aml_compute_cluster
  ]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = <<EOT
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
          --url "/subscriptions/${var.subscription_id_workload}/resourceGroups/${azurerm_resource_group.rg_aml_workspace.name}/providers/Microsoft.MachineLearningServices/workspaces/${azapi_resource.aml_workspace.name}?api-version=2025-09-01" \
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
## AML Hub storage account to the user within the scope of the file share used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_file_data_privileged_contributor" {
  depends_on = [
    null_resource.aml_patch_image_build_compute
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${var.user_object_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage Blob Data Contributor role on the
## AML Hub storage account to the user within the scope of the containers used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_blob_data_contributor" {
  depends_on = [
    azurerm_role_assignment.wk_pr_perm_st_file_data_privileged_contributor
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_aml_workspace.name}${var.user_object_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_aml_workspace.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}
