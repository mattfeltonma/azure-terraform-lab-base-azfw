variable "function_plan_sku" {
  description = "The SKU of the Azure Function App Service Plan. This can be FC1 or EP1"
  type        = string
  default     = "FC1"

  validation {
    condition     = contains(["FC1", "EP1"], var.function_plan_sku)
    error_message = "The function_plan_sku variable must be either 'FC1' or 'EP1'."
  }
}

variable "mcp_server_enabled" {
  description = "Setting this to true enables the Azure Functions MCP Server Extension"
  type        = bool
  default     = false
}

variable "python_version" {
  description = "Python version to use for the Function App"
  type        = string
  default = "3.13"
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

variable "subnet_id_app" {
  description = "The resource ID of the subnet where the private endpoint for the Azure Function App will be created"
  type        = string
}

variable "subnet_id_svc" {
  description = "The resource ID of the subnet where the private endpoints for the supporting resources will be created"
  type        = string
}

variable "subnet_id_vint" {
  description = "The resource ID of the subnet that has been delegated to Microsoft.Web/serverFarms for regional VNet integration for outbound traffic from the Azure Function"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription ID where the infrastructure is provisioned. This is the GUID not the full resource id"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "trusted_ip" {
  description = "The trusted IP address or CIDR block to allow access to the Front Door"
  type        = string
}
