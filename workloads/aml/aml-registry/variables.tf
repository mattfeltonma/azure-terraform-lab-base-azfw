variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to link the AML Hub to"
  type        = string
}

variable "managed_identity_principal_ids" {
  description = "The principal ids that will be assigned the AML Registry User role on the AML Registries"
  type        = list(string)
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the private endpoints to"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription id where the infrastructure resources are deployed"
  type        = string
}

variable "subscription_id_workload_production" {
  description = "The subscription id where the production workload resources will be deployed to"
  type        = string
}

variable "subscription_id_workload_non_production" {
  description = "The subscription id where the non-production workload resources will be deployed to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "workspace_managed_identity_principal_id" {
  description = "The principal id of the AML workspace that will be granted the Azure AI Enterprise Network Connection Approver role on the AML Registry resource group"
  type        = string
}

variable "non_human_rbac" {
  description = "Setting to true will create the non-human Azure RBAC role assignments for the AML Registries"
  type        = bool
  default     = true
}

variable "user_object_ids" {
  description = "The user object ids that will be assigned the AML Registry User role on the AML Registries"
  type        = list(string)
}