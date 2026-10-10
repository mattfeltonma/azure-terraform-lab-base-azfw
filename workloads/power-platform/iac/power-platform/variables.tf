variable "power_platform_billing_policy_id" {
  description = "The ID of the Power Platform billing policy"
  type        = string
}

variable "power_platform_environment_location" {
  description = "The location of the Power Platform environment"
  type        = string
  default     = "unitedstates"
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_id_resources" {
  description = "The resource id of the resource group to deploy the Power Platform Enterprise Policy to"
  type        = string
}

variable "resource_group_name_billing" {
  description = "The name of the resource group where the Power Platform Pay-As-You-Go billing is associated to"
  type        = string
}

variable "security_group_object_id" {
  description = "The Entra ID object id of the Security Group to grant access to the Power Platform environment"
  type        = string
}

variable "subscription_id_billing" {
  description = "The subscription id where the Power Platform Pay-As-You-Go billing is associated to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vnet_ids" {
  description = "The resource ids of the virtual networks to be used"
  type        = list(string)
}

variable "vnet_subnet_ids" {
  description = "The subnet ids of the virtual networks to be used"
  type        = list(string)
}
