########## Create an Azure Machine Learning Compute Instance to act as the developer machine
########## for running Jupyter notebooks and other development tasks
##########

## Create a user-assigned managed identity for the compute instance that will be used to build environment images
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

## Pause for 10 seconds to allow the dev compute instance managed identity to be replicated through Entra ID
##
resource "time_sleep" "wait_aml_compute_instance_identity_dev" {
  depends_on = [
    azurerm_user_assigned_identity.umi_compute_instance_dev
  ]
  create_duration = "10s"
}

## Create Azure RBAC Role Assignment granting the Storage Blob Data Contributor role on the
## AML workspace storage account to the dev compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_blob_data_contributor" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.workspace_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storageblobdatacontributor")
  scope                = var.workspace_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the Storage File Data Privileged Contributor role on the
## AML workspace storage account to the dev compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_st_file_data_privileged_contributor" {
  depends_on = [
    azurerm_role_assignment.umi_compute_instance_dev_st_blob_data_contributor,
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.workspace_storage_account_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}storagefiledataprivilegedcontributor")
  scope                = var.workspace_storage_account_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPush role on the Azure Container Registry
## to the dev compute instance user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_acr_push" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.workspace_container_registry_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}acrpush")
  scope                = var.workspace_container_registry_id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id
}

## Create Azure RBAC Role Assignment granting the AcrPull role on the Azure Container Registry
## to the build compute cluster user-assigned managed identity
resource "azurerm_role_assignment" "umi_compute_instance_dev_acr_pull" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_identity_dev
  ]

  name                 = uuidv5("dns", "${local.workspace_container_registry_name}${azurerm_user_assigned_identity.umi_compute_instance_dev.principal_id}acrpull")
  scope                = var.workspace_container_registry_id
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

## Create the AML Compute Instance to be used for a development environment
##
resource "azurerm_machine_learning_compute_instance" "aml_compute_instance_dev" {
  depends_on = [
    time_sleep.wait_aml_compute_instance_dev_role_assignments
  ]

  name        = local.dev_compute_instance_name
  description = "This is the development build compute instance"
  tags        = var.tags

  # Specify the AML workspace to deploy the compute instance to
  machine_learning_workspace_id = var.aml_workspace_resource_id

  # VM Settings
  virtual_machine_size     = var.vm_size

  # Disable local authentication
  local_auth_enabled = false

  # Configure authorization type to personal
  authorization_type = "personal"

  # Use the user-assigned managed identity for the compute cluster
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.umi_compute_instance_dev.id]
  }
  # Disable public IP on the compute cluster virtual machines
  node_public_ip_enabled = false

  # Designate the subnet to deploy the compute cluster to
  subnet_resource_id = var.subnet_id_amlcompute

  # Assign to development user
  assign_to_user {
    object_id = var.user_object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
}

## Create an A records for the compute cluster in the private DNS zone
##
resource "azurerm_private_dns_a_record" "aml_compute_instance_dev_dns_record_main" {
  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance_dev
  ]

  name                = "${azurerm_machine_learning_compute_instance.aml_compute_instance_dev.name}.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_workspace
  ]
}

resource "azurerm_private_dns_a_record" "aml_compute_instance_dev_dns_record_ssh" {
  depends_on = [
    azurerm_machine_learning_compute_instance.aml_compute_instance_dev
  ]

  name                = "${azurerm_machine_learning_compute_instance.aml_compute_instance_dev.name}-22.${var.region}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records = [
    var.pe_ip_address_aml_workspace
  ]
}