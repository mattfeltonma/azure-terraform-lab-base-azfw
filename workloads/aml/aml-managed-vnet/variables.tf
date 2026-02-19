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
  description = "The name of the resource group where the Private DNS Zones exist in the infrastructure subscription"
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
  description = "The trusted IP address Terraform will run from that needs access to the CMK Key Vault. This is only used for this lab and is not required for a production deployment"
  type        = string
}

variable "user_defined_outbound_rules_private_endpoint_resources" {
  description = "The external resources created outside of this module that are used by this module"
  type = map(
    object({
      serviceResourceId = string
      subresourceTarget = string
    })
  )
  default = {}
}

variable "user_object_id" {
  description = "The user object id of the ML Engineer"
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
  description = "The type of managed identity to create and use for the workspace. Options are 'umi' or 'smi'"
  type        = string
  default = "smi"
  #validation {
  #  # This condition validates that the value of the variable is either 'umi' or 'smi'. It also validates whether cmk encryption is enabled, as SMI is only supported with CMK encryption. If the condition is not met, an error message is returned.
  #  condition     = (var.workspace_managed_identity == "umi" || var.workspace_managed_identity == "smi") && !(var.workspace_encryption == "pmk" && var.workspace_managed_identity == "smi")
  #  error_message = "The workspace_managed_identity variable must be either 'umi' or 'smi' and if using cmk encryption the managed identity must be 'smi'."
  #}
}
