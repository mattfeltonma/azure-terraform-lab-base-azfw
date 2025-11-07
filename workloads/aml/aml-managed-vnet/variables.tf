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

variable "user_object_id" {
  description = "The user object id of the ML Engineer"
  type        = string
}
