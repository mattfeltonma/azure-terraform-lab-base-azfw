variable "allowed_ips" {
  description = "The list of IP addresses to allow through the service firewall for the storage account"
  type = list(string)
  default = []
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace"
  type = string
}

variable "region" {
  description = "The name of the Azure region to deploy the resources to"
  type = string
}

variable "region_code" {
  description = "The Azure region code to append to the resource name"
  type = string
}

variable "purpose" {
  description = "The three-letter purpose code for the resource"
  type = string
}

variable "network_trusted_services_bypass" {
  description = "The trusted services to bypass the network"
  type = list(string)
  # For Azure Storage this can be set to AzureServices, Logging, Metrics
  # By default trusted services are not bypassed
  default = ["None"]
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type = map(string)
}