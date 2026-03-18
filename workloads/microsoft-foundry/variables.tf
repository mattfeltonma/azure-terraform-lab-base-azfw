variable "agents" {
  description = "Set to true if plan to use this Foundry resource with AI Agents"
  type        = bool
  default     = false
}

variable "agent_service_outbound_networking" {
  description = "Configuration for agent service outbound networking if using agents"
  type = object({
    type      = string
    subnet_id = optional(string)
  })

  default = {
    type = "none"
  }

  validation {
    condition     = !(var.agent_service_outbound_networking.type != "none" && !var.agents)
    error_message = "Outbound networking can only be configured when agents are being deployed"
  }

  validation {
    condition     = contains(["vnet_injection", "managed_virtual_network", "none"], var.agent_service_outbound_networking.type)
    error_message = "This must be either 'vnet_injection' or 'managed_virtual_network' or 'none'"
  }

  validation {
    condition = (
      var.agent_service_outbound_networking.type == "managed_virtual_network" ?
      var.agent_service_outbound_networking.subnet_id == null :
      true
    )
    error_message = "The subnet_id variable cannot be set when type is 'managed_virtual_network'"
  }


  validation {
    condition = (
      var.agent_service_outbound_networking.type == "vnet_injection" ?
      var.agent_service_outbound_networking.subnet_id != null :
      true
    )
    error_message = "The subnet_id variable must be set when type is 'vnet_injection'"
  }
}

variable "apim_ai_gateway" {
  description = "Specify the APIM AI Gateway APIs that are hosting the Foundry models. A connection object will be created for each API. These APIs may be the OpenAI legacy API or v1 API."
  type = list(object({
    apim_resource_id      = string
    apim_fqdn             = string
    api_path              = string
    deployment_in_path    = string
    inference_api_version = optional(string, null)
    # This is technically optional if you're doing dynamic discovery, but for the purposes of this demo it is required.
    # It simply isn't used when creating the dynamic discovery apim connection in this demonstration
    models = optional(list(object({
      name = string
      properties = object({
        model = object({
          name    = string
          version = string
          format  = string
        })
      })
    })))
  }))
  default = null
}

variable "deploy_key_vault_connection_secrets" {
  description = "Set to true to create an Azure Key Vault to store secrets for connections used by agents created within Foundry resource and projects that use key-based authentication"
  type        = bool
  default     = false
  ## TODO: 12/2025 Remove this validation if a use case pops up for this feature when not using agents
  validation {
    condition     = !(var.deploy_key_vault_connection_secrets && !var.agents)
    error_message = "Key Vault for connection secrets only makes sense to deploy if agents are also being deployed"
  }
}

variable "deploy_rag_resources" {
  description = "Set to true if you are not using agents but want to deploy the resources required to demonstrate simple RAG patterns. This is not necessary when deploying agents."
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

variable "model_gateway" {
  description = "Specify the Model Gateway APIs that are hosting the Foundry models. A connection object will be created for each API. These APIs may be the OpenAI legacy API or v1 API."
  type = list(object({
    model_gateway_fqdn     = string
    model_gateway_api_path = string
    deployment_in_path     = string
    inference_api_version  = optional(string, null)
    # This is technically optional if you're doing dynamic discovery, but for the purposes of this demo it is required.
    # It simply isn't used when creating the dynamic discovery model gateway connection in this demonstration
    models = optional(list(object({
      name = string
      properties = object({
        model = object({
          name    = string
          version = string
          format  = string
        })
      })
    })))
  }))
  default = null
}

variable "model_gateway_api_key" {
  description = "The API key for the Model Gateway APIs. This is only used to demonstrate the model gateway pattern and is not required for Foundry to connect to an API Management instance hosting models. The connection uses the Entra ID authentication using the project's managed identity"
  type        = string
  sensitive   = true
  default     = null
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

variable "purpose" {
  description = "The three character purpose of the resource"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
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

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
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
