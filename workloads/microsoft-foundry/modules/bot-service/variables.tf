variable "activity_endpoint" {
  description = "The activity endpoint of the agent"
  type        = string
}

variable "agent_name" {
  description = "The name of the Foundry agent the Bot Service is being created for"
  type        = string
}

variable "agent_identity_principal_id" {
  description = "The principal id of the Foundry agent's Entra ID Agent Identity"
  type        = string
}

variable "bot_service_sku" {
  description = "The SKU of the Bot Service. Use 'F0' for free tier or 'S1' for standard tier."
  type        = string
  default     = "F0"
  validation {
    condition     = contains(["F0", "S1"], var.bot_service_sku)
    error_message = "Bot Service SKU must be either 'F0' or 'S1'."
  }
}

variable "entra_id_tenant_id" {
  description = "The tenant id of the Entra ID tenant where the user is located"
  type        = string
}

variable "log_analytics_workspace_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send Bot Service diagnostics to"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to create the Bot Service in"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to the resources"
  type        = map(string)
  default     = {}
}
