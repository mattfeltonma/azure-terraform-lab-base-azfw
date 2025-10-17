variable "workspace_identity" {
  description = "The identity name to use for the AML Workspace. This should be smi (system-assigned managed identity) or umi (user-managed identity)"
  type        = string
  default     = "smi"
  validation {
    condition     = contains(["smi", "umi"], var.workspace_identity)
    error_message = "Workspace identity must be either 'smi' or 'umi'."
  }
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

variable "sub_id_dns" {
  description = "The subscription where the Private DNS Zones are located"
  type        = string
}

variable "subnet_id_amlcompute" {
  description = "The subnet id to deploy the AML Compute Cluster to"
  type        = string
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the private endpoints to"
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

variable "vm_size" {
  description = "The size of the VM to use for the build compute cluster and compute instance"
  type        = string
}
