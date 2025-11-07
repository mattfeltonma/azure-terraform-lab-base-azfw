########## Create a resource group for the AML Project workspace and its resources
########## 
##########

## Create resource group the project and any of its resources will be deployed to
##
resource "azurerm_resource_group" "rg_aml_project" {
  name     = "rgamlproject${var.project_number}${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create optional resources for AML Projects which includes Azure Storage Accounts
##########
##########

## Create an optional storage account that can be used as a separate storage account from the default storage account
## to store data for the AML Project
resource "azurerm_storage_account" "storage_account_project" {
  name                = "stamlp${var.project_number}${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_aml_project.name
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
    # Block all public access by default
    default_action = "Deny"

    # Create resource access rule to allow workspaces within the subscription network access through the storage service firewall
    private_link_access {
      endpoint_resource_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_aml_project.name}/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for blob, file, queue, and table services to send logs to workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_project_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_project
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_project.id}/blobServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_project_file" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_monitor_diagnostic_setting.diag_storage_project_blob
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_project.id}/fileServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_project_queue" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_monitor_diagnostic_setting.diag_storage_project_file
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_project.id}/queueServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

resource "azurerm_monitor_diagnostic_setting" "diag_storage_project_table" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_monitor_diagnostic_setting.diag_storage_project_queue
  ]

  name                       = "diag-base"
  target_resource_id         = "${azurerm_storage_account.storage_account_project.id}/tableServices/default"
  log_analytics_workspace_id = var.law_resource_id

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

## Create a container in the project's storage account
##
resource "azurerm_storage_container" "storage_container_project_data" {
  depends_on = [
    azurerm_storage_account.storage_account_project
  ]

  name                  = "projectdata"
  storage_account_id    = azurerm_storage_account.storage_account_project.id
  container_access_type = "private"
}

## Create a Private Endpoint for data storage account blob endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_project_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_project
  ]

  name                = "pe${azurerm_storage_account.storage_account_project.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_project.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_project.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_project.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_project.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_project.name}blob"
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

## Create a Private Endpoint for data storage account file endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_project_file" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_private_endpoint.pe_storage_account_project_blob
  ]

  name                = "pe${azurerm_storage_account.storage_account_project.name}file"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_project.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_project.name}file"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_project.name}file"
    private_connection_resource_id = azurerm_storage_account.storage_account_project.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_project.name}file"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for data storage account table endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_project_table" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_private_endpoint.pe_storage_account_project_file
  ]

  name                = "pe${azurerm_storage_account.storage_account_project.name}table"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_project.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_project.name}table"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_project.name}table"
    private_connection_resource_id = azurerm_storage_account.storage_account_project.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_project.name}table"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for data storage account dfs endpoint
##
resource "azurerm_private_endpoint" "pe_storage_account_project_dfs" {
  depends_on = [
    azurerm_storage_account.storage_account_project,
    azurerm_private_endpoint.pe_storage_account_project_table
  ]

  name                = "pe${azurerm_storage_account.storage_account_project.name}dfs"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_project.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_project.name}dfs"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_project.name}dfs"
    private_connection_resource_id = azurerm_storage_account.storage_account_project.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_storage_account.storage_account_project.name}dfs"
    private_dns_zone_ids = [
      "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create an AML Project workspace within the AML Hub
##########
##########

## Create an AML Hub project workspace
##
resource "azapi_resource" "aml_project" {
  type                      = "Microsoft.MachineLearningServices/workspaces@2025-09-01"
  name                      = "amlws${var.project_number}${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aml_project.id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    identity = {
      type = "SystemAssigned"
    }
    tags = var.tags

    # Create an AML project workspace
    kind = "Project"

    # Only SKU right now
    sku = {
      tier = "Basic"
      name = "Basic"
    }

    properties = {
      friendlyName = "Sample-Aml-Project-${var.project_number}"
      description  = "This is sample AML Project ${var.project_number}"

      # Enable the HBI feature for additional security since there are very few reasons not to
      hbiWorkspace = true

      # Associate the workspace to the AML Hub
      hubResourceId = var.hub_aml_workspace_resource_id

      # Probably unnecessary due to hub configuration but can't hurt
      systemDatastoresAuthMode = "identity"
    }
  }
  # Export system-assigned managed identity principal ID for the project
  response_export_values = [
    "identity.principalId",
    "properties.workspaceId"
  ]

  # Ignore updates to these tags on additional Terraform deployments
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AML project
##
resource "azurerm_monitor_diagnostic_setting" "diag_aml_project" {
  depends_on = [
    azapi_resource.aml_project
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_project.id
  log_analytics_workspace_id = var.law_resource_id

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

## Pause for 10 seconds to allow the project identity to be replicated through Entra ID
##
resource "time_sleep" "wait_project_identities" {
  depends_on = [
    azapi_resource.aml_project
  ]
  create_duration = "10s"
}

## Create a connection from the project workspace to a storage account that will be used to demonstrate data storage
##
resource "azapi_resource" "project_storage_data_datastore" {
  depends_on = [
    azapi_resource.aml_project
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces/datastores@2025-01-01-preview"
  name                      = substr("conn${azurerm_storage_account.storage_account_project.name}", 0, 24)
  parent_id                 = azapi_resource.aml_project.id
  schema_validation_enabled = true

  body = {
    properties = {
      description   = "Data storage account for AI Foundry Project"
      datastoreType = "AzureBlob"
      accountName   = azurerm_storage_account.storage_account_project.name
      endpoint      = "core.windows.net"
      protocol      = "https"
      containerName = "data"

      # Set the authentication to use the user's Entra ID identity
      credentials = {
        credentialsType = "None"
      }
      serviceDataAccessAuthIdentity = "None"

      tags = var.tags
    }
  }
}

########## Create an Azure Machine Learning Compute Instance to perform development and experimentation
########## 
##########

## Create a user-assigned managed identity for the development compute instance
##
resource "azurerm_user_assigned_identity" "umi_compute_instance_dev" {
  depends_on = [
    azurerm_resource_group.rg_aml_project,
    azapi_resource.aml_project
  ]

  name                = "umi${local.dev_compute_instance_name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_project.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 10 seconds to allow the development compute instance managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_aml_compute_instance_identity_dev" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_instance_dev
  ]
  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML Hub storage account to the development compute instance user-assigned managed identity with an ABAC condition restricting it to the project workspace containers
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.hub_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storageblobdatacontributor")
  scope                = var.hub_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
  condition_version    = "2.0"
  condition            = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'})  
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'}) 
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'}) 
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action'})
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'})
    ) 
    OR 
    (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${azapi_resource.aml_project.output.properties.workspaceId}-') 
  )
  EOT
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_dev_st_blob_data_contributor
  ]

  name                 = uuidv5("dns", "${local.hub_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storagefiledataprivilegedcontributor")
  scope                = var.hub_storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_aml_compute_instance_dev_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_dev_st_blob_data_contributor,
    azurerm_role_assignment.umi_compute_instance_dev_st_file_data_privileged_contributor
  ]
  create_duration = "120s"
}

## Create the AML Compute Instance for the AML Project workspace
##
resource "azapi_resource" "aml_compute_instance_project_dev" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_dev_role_assignments
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces/computes@2025-09-01"
  name                      = local.dev_compute_instance_name
  parent_id                 = var.hub_aml_workspace_resource_id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.umi_compute_instance_dev.id}" = {}
      }
    }
    tags = var.tags

    properties = {
      computeLocation  = var.region
      computeType      = "ComputeInstance"
      description      = "Development compute instance for building environment images for the AML project"
      disableLocalAuth = true
      properties = {
        applicationSharingPolicy = "Shared"
        enableNodePublicIp       = false
        vmSize                   = "Standard_D2s_v3"
        personalComputeInstanceSettings = {
          assignedUser = {
            objectId = var.user_object_id
            tenantId = data.azurerm_client_config.current.tenant_id
          }
        }
      }
    }
  }
  # Export system-assigned managed identity principal ID for the project
  response_export_values = [
    "identity.principalId",
    "properties.workspaceId"
  ]

  # Ignore updates to these tags on additional Terraform deployments
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create an A records for the compute instance in the private DNS zone to support access to the instance
##
resource "azurerm_private_dns_a_record" "aml_compute_instance_dev_dns_record_main" {
  depends_on = [
    azapi_resource.aml_compute_instance_project_dev
  ]

  name                = "${azapi_resource.aml_compute_instance_project_dev.name}.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_hub
  ]
}

resource "azurerm_private_dns_a_record" "aml_compute_instance_dev_dns_record_ssh" {
  depends_on = [
    azapi_resource.aml_compute_instance_project_dev
  ]

  name                = "${azapi_resource.aml_compute_instance_project_dev.name}-22.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_hub
  ]
}

########## Create the non-human role assignments
##########
##########

## Create an Azure RBAC Role Assignment granting the AML Hub managed identity the Azure AI Enterprise Network Connection Approver
## role on the project resource group to allow it to approve the creation of managed private endpoints for additional project resources
resource "azurerm_role_assignment" "smi_aml_rg_azure_ai_net_conn_app" {
  depends_on = [
    azurerm_resource_group.rg_aml_project
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_project.name}${var.hub_managed_identity_principal_id}netconnapp")
  scope                = azurerm_resource_group.rg_aml_project.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = var.hub_managed_identity_principal_id
}

########## Create the human role assignments
##########
##########

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Data Scientist role to the user.
## This allows the user to perform all actions except for creating compute resources.
##
resource "azurerm_role_assignment" "wk_perm_data_scientist_project" {
  depends_on = [
    azapi_resource.aml_project
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_project.name}${var.user_object_id}${azapi_resource.aml_project.name}datascientist")
  scope                = azapi_resource.aml_project.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the user within the scope of the file share used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_file_data_privileged_contributor" {
  depends_on = [
    azapi_resource.aml_project
  ]
  name                 = uuidv5("dns", "${local.hub_storage_account_name}${var.user_object_id}${azapi_resource.aml_project.output.properties.workspaceId}storagefiledataprivilegedcontributor")
  scope                = "${var.hub_storage_account_id}/fileServices/default/fileshares/${azapi_resource.aml_project.output.properties.workspaceId}-code"
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage Blob Data Contributor role on the
## AML Hub storage account to the user within the scope of the containers used by the AML Project
##
resource "azurerm_role_assignment" "wk_pr_perm_st_blob_data_contributor" {
  depends_on = [
    azapi_resource.aml_project,
    azurerm_role_assignment.wk_pr_perm_st_file_data_privileged_contributor,
  ]
  name                 = uuidv5("dns", "${local.hub_storage_account_name}${var.user_object_id}${azapi_resource.aml_project.output.properties.workspaceId}storageblobdatacontributor")
  scope                = var.hub_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
  condition_version    = "2.0"
  condition            = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'})  
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'}) 
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'}) 
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action'})
      AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'})
    ) 
    OR 
    (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${azapi_resource.aml_project.output.properties.workspaceId}-') 
  )
  EOT
}

## Create Azure RBAC Role assignment granting the Storage File Data Privileged Contributor role on the
## project data storage account to the user
##
resource "azurerm_role_assignment" "wk_pr_perm_project_st_file_data_privileged_contributor" {
  depends_on = [
    azapi_resource.project_storage_data_datastore
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_project.name}${var.user_object_id}storagefiledataprivilegedcontributor")
  scope                = azurerm_storage_account.storage_account_project.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role assignment granting the Storage Blob Data Contributor role on the
## project data storage account to the user
##
resource "azurerm_role_assignment" "wk_pr_perm_project_st_blob_data_contributor" {
  depends_on = [
    azapi_resource.project_storage_data_datastore
  ]
  name                 = uuidv5("dns", "${azurerm_storage_account.storage_account_project.name}${var.user_object_id}storageblobdatacontributor")
  scope                = azurerm_storage_account.storage_account_project.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}
