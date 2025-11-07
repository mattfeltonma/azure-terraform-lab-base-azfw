########## Create an Azure Machine Learning Compute Cluster to act as the build compute
########## This is required because the Azure Container Registry is blocking public network access
##########

## Create a user-assigned managed identity for the compute cluster that will be used to build environment images
##
resource "azurerm_user_assigned_identity" "umi_compute_cluster_build" {
  name                = "umi${local.build_compute_cluster_name}"
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

## Pause for 10 seconds to allow the build compute cluster managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_aml_compute_cluster_identity_build" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_cluster_build
  ]
  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML workspace storage account to the build compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_build_st_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_aml_compute_cluster_identity_build
  ]

  name                 = uuidv5("dns", "${local.workspace_storage_account_name}${azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id}storageblobdatacontributor")
  scope                = var.workspace_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML workspace storage account to the build compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_build_st_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_build_st_blob_data_contributor,
    time_sleep.wait_aml_compute_cluster_identity_build
  ]

  name                 = uuidv5("dns", "${local.workspace_storage_account_name}${azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id}storagefiledataprivilegedcontributor")
  scope                = var.workspace_storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPush role on the Azure Container Registry
## to the build compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_build_acr_push" {
  depends_on = [
    time_sleep.wait_aml_compute_cluster_identity_build
  ]

  name                 = uuidv5("dns", "${local.workspace_container_registry_name}${azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id}acrpush")
  scope                = var.workspace_container_registry_id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPull role on the Azure Container Registry
## to the build compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_cluster_build_acr_pull" {
  depends_on = [
    time_sleep.wait_aml_compute_cluster_identity_build
  ]

  name                 = uuidv5("dns", "${local.workspace_container_registry_name}${azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id}acrpull")
  scope                = var.workspace_container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.umi_compute_cluster_build.principal_id
}

## Pause for 120 seconds to allow the role assignments to propagate through Azure
##
resource "time_sleep" "wait_aml_compute_cluster_build_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_compute_cluster_build_st_blob_data_contributor,
    azurerm_role_assignment.umi_compute_cluster_build_st_file_data_privileged_contributor,
    azurerm_role_assignment.umi_compute_cluster_build_acr_push,
    azurerm_role_assignment.umi_compute_cluster_build_acr_pull
  ]
  create_duration = "120s"
}

## Create the AML Compute Cluster to be used for building environment images
##
resource "azurerm_machine_learning_compute_cluster" "aml_compute_cluster_build" {
  depends_on = [
    time_sleep.wait_aml_compute_cluster_build_role_assignments
  ]

  name        = local.build_compute_cluster_name
  description = "This is the dedicated build compute cluster"
  location    = var.region
  tags        = var.tags

  # Specify the AML workspace to deploy the compute cluster to
  machine_learning_workspace_id = var.aml_workspace_resource_id

  # VM Settings
  vm_size     = var.vm_size
  vm_priority = "Dedicated"
  scale_settings {
    max_node_count                       = 4
    min_node_count                       = 0
    scale_down_nodes_after_idle_duration = "PT15M"
  }

  # Disable local authentication
  local_auth_enabled = false
  # Use the user-assigned managed identity for the compute cluster
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.umi_compute_cluster_build.id]
  }
  # Disable public IP on the compute cluster virtual machines
  node_public_ip_enabled = false

  # Designate the subnet to deploy the compute cluster to
  subnet_resource_id = var.subnet_id_amlcompute
}

## Create an A records for the compute cluster in the private DNS zone
##
resource "azurerm_private_dns_a_record" "aml_compute_cluster_build_dns_record_main" {
  depends_on = [
    azurerm_machine_learning_compute_cluster.aml_compute_cluster_build
  ]

  name                = "${azurerm_machine_learning_compute_cluster.aml_compute_cluster_build.name}.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_workspace
  ]
}

resource "azurerm_private_dns_a_record" "aml_compute_cluster_build_dns_record_ssh" {
  depends_on = [
    azurerm_machine_learning_compute_cluster.aml_compute_cluster_build
  ]

  name                = "${azurerm_machine_learning_compute_cluster.aml_compute_cluster_build.name}-22.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_workspace
  ]
}