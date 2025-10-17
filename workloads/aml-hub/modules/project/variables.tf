variable "hub_aml_workspace_resource_id" {
  description = "The resource id of the AML Hub workspace"
  type = string
}

variable "hub_container_registry_id" {
  description = "The resource id of the AML Hub container registry"
  type = string
}

variable "hub_storage_account_id" {
  description = "The resource id of the AML Hub storage account"
  type = string
}

variable "project_storage_account_name" {
  description = "The name of the storage account to use for the project data storage"
  type = string
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace"
  type = string
}

variable "pe_ip_address_aml_hub" {
  description = "The Private Endpoint IP address of the AML Hub Workspace Private Endpoint"
  type = string 
}

variable "region" {
  description = "The name of the Azure region to deploy the resources to"
  type = string
}

variable "region_code" {
  description = "The Azure region code to append to the resource name"
  type = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type = string
}

variable "resource_group_id_workload" {
  description = "The id of the resource group to deploy the project and its resources to"
  type = string
}

variable "resource_group_name_workload" {
  description = "The name of the resource group to deploy the project and its resources to"
  type = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group the Private DNS Zones are located in"
  type = string
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the private endpoints to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type = map(string)
}

variable "user_object_id" {
  description = "The object id of the Entra ID user who will use the AML Project"
  type        = string
}