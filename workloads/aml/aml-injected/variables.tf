variable "key_vault_cmk_rbac_enabled" {
  description = "Sets the Key Vault to either support RBAC or Access Policies."
  type        = bool
  default     = false
}

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

variable "ssh_public_key" {
  description = "The SSH public key to access the build compute instance"
  type        = string
  default     = null
}

variable "subnet_id_amlcompute" {
  description = "The subnet id to deploy the AML Compute Cluster to"
  type        = string
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the private endpoints to"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription id where the infrastructure resources are deployed"
  type        = string
}

variable "subscription_id_workload" {
  description = "The subscription id where the workload resources will be deployed to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "trusted_ip" {
  description = "The trusted IP address to allow access to the AML Hub. This is only used for this lab and is not required for a production deployment"
  type        = string
}

variable "user_object_id" {
  description = "The object id of the Entra ID user who will use the AML Project"
  type        = string
}

variable "workspace_encryption" {
  description = "The type of encryption to use for the AML Workspace. Options are 'cmk' or 'pmk'"
  type        = string
  default = "pmk"
  validation {
    condition     = contains(["cmk", "pmk"], var.workspace_encryption)
    error_message = "The workspace_encryption variable must be either 'cmk' or 'pmk'."
  }
}

variable "workspace_managed_identity" {
  description = "The identity name to use for the AML Workspace. This should be smi (system-assigned managed identity) or umi (user-managed identity)"
  type        = string
  default     = "smi"
  validation {
    condition     = contains(["smi", "umi"], var.workspace_managed_identity)
    error_message = "Workspace identity must be either 'smi' or 'umi'."
  }
}
