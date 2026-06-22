variable "function_plan_sku" {
  description = "The SKU of the Flexible Consumption plan. This template only supports the Flexible Consumption Plan"
  type        = string
  default     = "FC1"
}

variable "python_version" {
  description = "Python version to use for the Function App"
  type        = string
  default = "3.13"
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
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

variable "subnet_id_svc" {
  description = "The ID of the subnet where the private endpoints will be created"
  type        = string
}

variable "subnet_id_vint" {
  description = "The ID of the subnet where the virtual network integration will be configured"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription ID where the infrastructure is provisioned"
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
