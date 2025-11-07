########## Create a resource group for the AML Registries
########## 
##########

## Create resource group the production registries will be deployed to
##
resource "azurerm_resource_group" "rg_aml_registry_production" {
  provider = azurerm.subscription_workload_production

  name     = "rgamlregistryp${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create resource group the non-production registries will be deployed to
##
resource "azurerm_resource_group" "rg_aml_registry_non_production" {
  provider = azurerm.subscription_workload_non_production

  name     = "rgamlregistrynp${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create a production and non-production AML Registry and configure diagnostics settings for the managed resources
##########
##########

## Create an AML Registry for production
##
resource "azapi_resource" "aml_registry_production" {
  provider = azapi.subscription_workload_production

  depends_on = [
    azurerm_resource_group.rg_aml_registry_production
  ]

  type                      = "Microsoft.MachineLearningServices/registries@2025-06-01"
  name                      = "amlrp${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aml_registry_production.id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    # Set the identity for the AML Registry to use
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      regionDetails = [
        {
          location = var.region
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountType       = "Standard_LRS"
                storageAccountHnsEnabled = false
              }
            }
          ]
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountSku = "Premium"
              }
            }
          ]
        }
      ]
      # You can uncomment and use this section if you want to assign an identity the AI Administrator role over the managed
      # resource gorup and exempt from the denyAssignemnts. This is primarily used when a pipeline doesn't have subscription
      # wide permissions
      managedResourceGroupSettings = {
        assignedIdentities = [
          {
            principalId = "2e69d9f2-b5b3-482b-9c15-faeca086b632"
          }
        ]
      }
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.regionDetails",
    "properties"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the production AML Registry storage account for blob, file, queue, and table services
## to send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_production_storage_blob" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azapi_resource.aml_registry_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_production_storage_file" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_production_storage_blob
  ]

  name                       = "diag-file"
  target_resource_id         = "${azapi_resource.aml_registry_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_production_storage_queue" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_production_storage_file
  ]

  name                       = "diag-default"
  target_resource_id         = "${azapi_resource.aml_registry_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_production_storage_table" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_production_storage_queue
  ]

  name                       = "diag-table"
  target_resource_id         = "${azapi_resource.aml_registry_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/tableServices/default"
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

## Create diagnostic settings for the production AML Registry Container Registry to send logs to workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_production_acr" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_registry_production.output.properties.regionDetails[0].acrDetails[0].systemCreatedAcrAccount.armResourceId.resourceId
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

## Create an AML Registry for non-production
##
resource "azapi_resource" "aml_registry_non_production" {
  provider = azapi.subscription_workload_non_production

  depends_on = [
    azurerm_resource_group.rg_aml_registry_non_production
  ]

  type                      = "Microsoft.MachineLearningServices/registries@2025-06-01"
  name                      = "amlrnp${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_aml_registry_non_production.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    # Set the identity for the AML Registry to use
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      regionDetails = [
        {
          location = var.region
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountType       = "Standard_LRS"
                storageAccountHnsEnabled = false
              }
            }
          ]
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountSku = "Premium"
              }
            }
          ]
        }
      ]
      # You can uncomment and use this section if you want to assign an identity the AI Administrator role over the managed
      # resource gorup and exempt from the denyAssignemnts. This is primarily used when a pipeline doesn't have subscription
      # wide permissions
      #managedResourceGroupSettings = {
      #  assignedIdentities = [
      #    {
      #      principalId = var.object_id
      #    }
      #  ]
      #}
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.regionDetails",
    "properties"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the non-production AML Registry storage account for blob, file, queue, and table services
## to send logs to the workload Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_non_production_storage_blob" {
  provider = azurerm.subscription_workload_non_production

  depends_on = [
    azapi_resource.aml_registry_non_production
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azapi_resource.aml_registry_non_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_non_production_storage_file" {
  provider = azurerm.subscription_workload_non_production

  depends_on = [
    azapi_resource.aml_registry_non_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_non_production_storage_blob
  ]

  name                       = "diag-file"
  target_resource_id         = "${azapi_resource.aml_registry_non_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_non_production_storage_queue" {
  provider = azurerm.subscription_workload_non_production

  depends_on = [
    azapi_resource.aml_registry_non_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_non_production_storage_file
  ]

  name                       = "diag-default"
  target_resource_id         = "${azapi_resource.aml_registry_non_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_non_production_storage_table" {
  provider = azurerm.subscription_workload_non_production

  depends_on = [
    azapi_resource.aml_registry_non_production,
    azurerm_monitor_diagnostic_setting.diag_aml_registry_non_production_storage_queue
  ]

  name                       = "diag-table"
  target_resource_id         = "${azapi_resource.aml_registry_non_production.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/tableServices/default"
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

## Create diagnostic settings for the non-production AML Registry Container Registry to send logs to workload Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_aml_registry_non_production_acr" {
  provider = azurerm.subscription_workload_non_production

  depends_on = [
    azapi_resource.aml_registry_non_production
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_registry_non_production.output.properties.regionDetails[0].acrDetails[0].systemCreatedAcrAccount.armResourceId.resourceId
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

########## Create Private Endpoints the AML Registries
##########
##########

## Create a Private Endpoint for the production AML Registry
##
resource "azurerm_private_endpoint" "pe_aml_registry_production" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production
  ]

  name                = "pe${azapi_resource.aml_registry_production.name}registry"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_registry_production.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.aml_registry_production.name}registry"

  private_service_connection {
    name                           = "peconn${azapi_resource.aml_registry_production.name}registry"
    private_connection_resource_id = azapi_resource.aml_registry_production.id
    subresource_names              = ["amlregistry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.aml_registry_production.name}registry"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"
    ]
  }
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Private Endpoint for the non-production AML Registry
##
resource "azurerm_private_endpoint" "pe_aml_registry_non_production" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_non_production,
    azurerm_private_endpoint.pe_aml_registry_production
  ]

  name                = "pe${azapi_resource.aml_registry_non_production.name}registry"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aml_registry_production.name
  tags                = var.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azapi_resource.aml_registry_non_production.name}registry"

  private_service_connection {
    name                           = "peconn${azapi_resource.aml_registry_non_production.name}registry"
    private_connection_resource_id = azapi_resource.aml_registry_non_production.id
    subresource_names              = ["amlregistry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.aml_registry_non_production.name}registry"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"
    ]
  }
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}


########## Create the non-human role assignments granting permissions on the AML Registries
##########
##########

## Create an Azure RBAC Role Assignment granting the AML Hub managed identity the Azure AI Enterprise Network Connection Approver
## role on the project resource group to allow it to approve the creation of managed private endpoints for AML Registries
resource "azurerm_role_assignment" "smi_aml_rg_prod_azure_ai_net_conn_app" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azurerm_resource_group.rg_aml_registry_production
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_registry_production.name}${var.workspace_managed_identity_principal_id}netconnapp")
  scope                = azurerm_resource_group.rg_aml_registry_production.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = var.workspace_managed_identity_principal_id
}

resource "azurerm_role_assignment" "smi_aml_rg_non_prod_azure_ai_net_conn_app" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azurerm_resource_group.rg_aml_registry_non_production
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_aml_registry_non_production.name}${var.workspace_managed_identity_principal_id}netconnapp")
  scope                = azurerm_resource_group.rg_aml_registry_non_production.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = var.workspace_managed_identity_principal_id
}


## Create Azure RBAC Role Assignment granting the relevanted managed identity the AML Registry User role
## to the production AML Registry
resource "azurerm_role_assignment" "aml_registry_production_aml_registry_user_non_human" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production
  ]

  for_each = toset(var.managed_identity_principal_ids)

  name                 = uuidv5("dns", "${azapi_resource.aml_registry_production.name}${each.value}amlregistryuser")
  scope                = azapi_resource.aml_registry_production.id
  role_definition_name = "AzureML Registry User"
  principal_id         = each.value
}

## Create Azure RBAC Role Assignment granting the relevanted managed identity the AML Registry User role
## to the non-production AML Registry
resource "azurerm_role_assignment" "aml_registry_non_production_aml_registry_user_non_human" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_non_production
  ]

  for_each = toset(var.managed_identity_principal_ids)

  name                 = uuidv5("dns", "${azapi_resource.aml_registry_non_production.name}${each.value}amlregistryuser")
  scope                = azapi_resource.aml_registry_non_production.id
  role_definition_name = "AzureML Registry User"
  principal_id         = each.value
}

########## Create the human role assignments granting permissions on the AML Registries
##########
##########

## Create Azure RBAC Role Assignment granting the Azure ML Registry User role to the user
## over the production AML Registry
resource "azurerm_role_assignment" "aml_registry_production_aml_registry_user_human" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_production,
    azurerm_role_assignment.aml_registry_production_aml_registry_user_non_human
  ]

  for_each = toset(var.user_object_ids)

  name                 = uuidv5("dns", "${azapi_resource.aml_registry_production.name}${each.value}amlregistryuser")
  scope                = azapi_resource.aml_registry_production.id
  role_definition_name = "AzureML Registry User"
  principal_id         = each.value
}

## Create Azure RBAC Role Assignment granting the Azure ML Registry User role to the user
## over the non-production AML Registry
resource "azurerm_role_assignment" "aml_registry_non_production_aml_registry_user_human" {
  provider = azurerm.subscription_workload_production

  depends_on = [
    azapi_resource.aml_registry_non_production,
    azurerm_role_assignment.aml_registry_non_production_aml_registry_user_non_human
  ]

  for_each = toset(var.user_object_ids)

  name                 = uuidv5("dns", "${azapi_resource.aml_registry_non_production.name}${each.value}amlregistryuser")
  scope                = azapi_resource.aml_registry_non_production.id
  role_definition_name = "AzureML Registry User"
  principal_id         = each.value
}
