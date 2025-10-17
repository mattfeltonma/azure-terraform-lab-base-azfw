########## Create an Azure Machine Learning Compute Instance to perform development and experimentation
########## 
##########

## Create a user-assigned managed identity for the development compute instance
##
resource "azurerm_user_assigned_identity" "umi_compute_instance_dev" {
  name                = "umi${local.dev_compute_instance_name}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
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
## AML Hub storage account to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.hub_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storageblobdatacontributor")
  scope                = var.hub_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML Hub storage account to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_dev_st_blob_data_contributor,
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.hub_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storagefiledataprivilegedcontributor")
  scope                = var.hub_storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPush role on the Azure Container Registry 
## to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_acr_push" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.hub_container_registry_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}acrpush")
  scope                = var.hub_container_registry_id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPull role on the Azure Container Registry
## to the development compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_acr_pull" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.hub_container_registry_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}acrpull")
  scope                = var.hub_container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_aml_compute_instance_dev_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_dev_st_blob_data_contributor,
    azurerm_role_assignment.umi_compute_instance_dev_st_file_data_privileged_contributor,
    azurerm_role_assignment.umi_compute_instance_dev_acr_push,
    azurerm_role_assignment.umi_compute_instance_dev_acr_pull
  ]
  create_duration = "120s"
}

## Create the AML Compute Instance for the AML Project workspace
##
resource "azapi_resource" "aml_compute_instance_project_dev" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_instance_dev,
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
      computeLocation = var.region
      computeType     = "ComputeInstance"
      description    = "Development compute instance for building environment images for the AML project"
      disableLocalAuth = true
      properties = {
        applicationSharingPolicy = "Shared"
        enableNodePublicIp        = false
        vmSize = "Standard_D2s_v3"
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

## Create an A records for the compute instance in the private DNS zone
##
resource "azurerm_private_dns_a_record" "aml_compute_instance_dev_dns_record_main" {
  depends_on = [
    azapi_resource.aml_compute_instance_project_dev
  ]

  name                = "${azapi_resource.aml_compute_instance_project_dev.name}.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records             = [
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
  records             = [
    var.pe_ip_address_aml_hub
  ]
}

########## Create an AML Project workspace within the AML Hub
##########
##########

## Create an AML Hub project workspace
##
resource "azapi_resource" "aml_project" {
  depends_on = [
    azapi_resource.aml_compute_instance_project_dev
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-09-01"
  name                      = "amlws${var.region_code}${var.random_string}"
  parent_id                 = var.resource_group_id_workload
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
      friendlyName = "Sample-Aml-Project-1"
      description  = "This is sample AML Project 1"

      # Associate the workspace to the AML Hub
      hubResourceId = var.hub_aml_workspace_resource_id

      # Probably unnecessary due to hub configuration but can't hurt
      systemDatastoresAuthMode = "identity"

      # This it the resource group where the AML Hub has been deployed
      workspaceHubConfig = {
        defaultWorkspaceResourceGroup = var.resource_group_name_workload
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
  name                      = substr("conn${var.project_storage_account_name}", 0, 24)
  parent_id                 = azapi_resource.aml_project.id
  schema_validation_enabled = true

  body = {
    properties = {
      description   = "Data storage account for AI Foundry Project"
      datastoreType = "AzureBlob"
      accountName   = var.project_storage_account_name
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
  name                 = uuidv5("dns", "${var.resource_group_name_workload}${var.user_object_id}${azapi_resource.aml_project.name}datascientist")
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
