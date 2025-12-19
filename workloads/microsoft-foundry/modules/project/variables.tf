variable "agents" {
  description = "Specify whether to deploy the AI Agents resources within the Foundry project"
  type        = bool
  default     = false
}

variable "deploy_key_vault_connection_secrets" {
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

variable "shared_app_insights_resource_id" {
  description = "The resource id of the Application Insights resource to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_app_insights_connection_string" {
  description = "The connection string of the Application Insights resource to connect to the Foundry resource"
  type        = string
  sensitive   = true
  default     = null
}

variable "shared_bing_grounding_search_resource_id" {
  description = "The resource id of the Bing Grounding Search resource to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_bing_grounding_search_api_key" {
  description = "The API key of the Bing Grounding Search resource to connect to the Foundry project"
  type        = string
  sensitive   = true
  default     = null
}

variable "shared_byo_key_vault_resource_id" {
  description = "The resource id of the Azure Key Vault to store secrets for connections created within Foundry resource and projects that use key-based authentication"
  type        = string
  default     = null
}

variable "shared_agent_ai_search_resource_id" {
  description = "The resource id of the AI Search resource to connect to the Foundry project"
  type        = string
  default = null
}

variable "shared_agent_cosmosdb_account_resource_id" {
  description = "The resource id of the CosmosDB account to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_agent_cosmosdb_account_endpoint" {
  description = "The endpoint of the CosmosDB account to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_agent_storage_account_blob_endpoint" {
  description = "The blob endpoint of the Storage Account to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_agent_storage_account_resource_id" {
  description = "The resource id of the Storage Account to connect to the Foundry project"
  type        = string
  default     = null
}

variable "shared_external_openai" {
  description = "Indicate the external Azure OpenAI or Foundry instance that will host the LLMs"
  type = object({
    name        = string
    endpoint    = string
    resource_id = string
    region      = string
  })
  default = null
}

variable "user_object_id" {
  description = "The object id of the user who will manage the AI Studio Hub"
  type        = string
}

