variable "agent_service_outbound_networking" {
  description = "Configuration for agent service outbound networking"
  type = object({
    type      = string
    subnet_id = optional(string)
  })
  
  validation {
    condition = contains(["vnet_injection", "managed_virtual_network"], var.agent_service_outbound_networking.type)
    error_message = "type must be either 'vnet_injection' or 'managed_virtual_network'"
  }
  
  validation {
    condition = (
      var.agent_service_outbound_networking.type == "vnet_injection" ? 
        var.agent_service_outbound_networking.subnet_id != null : 
        true
    )
    error_message = "subnet_id is required when type is 'vnet_injection'"
  }
}

variable "byo_key_vault" {
  description = "Set to true to create an Azure Key Vault to store secrets for connections created within Foundry resource and projects that use key-based authentication"
  type        = bool
  default     = false
}

variable "external_openai" {
  description = "Indicate the external Azure OpenAI or Foundry resource that will host the LLMs"
  type = object({
    name        = string
    endpoint    = string
    resource_id = string
    region      = string
  })
  default = null
}

variable "foundry_encryption" {
  description = "Indicate whether the Foundry resource should be encrypted with a provider-managed key or customer-managed key. CMK will create a Key Vault, key, and necessary role assignments"
  type        = string
  default     = "cmk"
  validation {
    condition     = contains(["pmk", "cmk"], var.foundry_encryption)
    error_message = "Encryption must be either 'pmk' or 'cmk'."
  }
}

variable "resource_managed_identity_type" {
  description = "The type of managed identity to create for the Foundry resource. Use 'smi' for System-assigned and 'umi' for User-assigned managed identity."
  type        = string
  default     = "umi"
  validation {
    condition     = contains(["smi", "umi"], var.resource_managed_identity_type)
    error_message = "Managed identity type must be either 'smi' or 'umi'."
  }
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "purpose" {
  description = "The three character purpose of the resource"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription where the Private DNS Zones are located"
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
  description = "The trusted IP address of the Terraform deployment server. This is only used for this lab because the Terraform deployment server is not within the virtual network and is not required for a production deployment"
  type        = string
}

variable "user_object_id" {
  description = "The object id of the user who will manage the AI Studio Hub"
  type        = string
}
