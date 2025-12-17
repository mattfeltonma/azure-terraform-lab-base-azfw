variable "byo_key_vault" {
  description = "Specify whether BYO Key Vault will be used to store secrets for connections created within Foundry resource and projects that use key-based authentication"
  type        = bool
  default     = false
}

variable "first_project" {
  description = "TEMPORARY: Set to true to create the first Foundry project within the Foundry resource. This is required for now because the BYOK will fail to create a connection if there are no projects associated to the Foundry resource"
  type        = bool
  default     = true
}

variable "foundry_resource_id" {
  description = "The resource id of the Foundry resource where the project will be created"
  type        = string
}

variable "foundry_resource_resource_group_id" {
  description = "The resource group id of the Foundry resource where the project will be created"
  type        = string
}

variable "project_managed_identity_type" {
  description = "The type of managed identity to create for the Foundry project. Use 'smi' for System-assigned and 'umi' for User-assigned managed identity."
  type        = string
  default     = "smi"
  validation {
    condition     = contains(["smi", "umi"], var.project_managed_identity_type)
    error_message = "Managed identity type must be either 'smi' or 'umi'."
  }
}

variable "project_number" {
  description = "The number to append to the Foundry project name to make it unique. This is only required for this lab"
  type        = number
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "shared_byo_key_vault_resource_id" {
  description = "The resource id of the Azure Key Vault to store secrets for connections created within Foundry resource and projects that use key-based authentication"
  type        = string
  default     = null
}

variable "user_object_id" {
  description = "The object id of the user who will manage the AI Studio Hub"
  type        = string
}

