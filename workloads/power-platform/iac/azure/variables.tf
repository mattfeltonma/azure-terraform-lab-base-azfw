variable "dns_servers" {
  description = "The DNS servers to be set on the virtual network"
  type        = list(string)
  default     = ["168.63.129.16"]
}

variable "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall"
  type        = string
}

variable "network_watcher_resource_group_name" {
  description = "The resource group name the Network Watcher is deployed to"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "regions" {
  description = "The regions where the resources will be deployed"
  type = list(object({
    name = string
    code = string
    cidr = string
  }))
  default = [
    {
      name = "eastus"
      code = "eus"
      cidr = "10.0.20.0/22"
    },
    {
      name = "westus"
      code = "wus"
      cidr = "10.0.24.0/22"
    }
  ]
}

variable "resource_group_name_transit" {
  description = "The name of the resource group the transit virtual network is deployed to"
  type        = string
}

variable "resource_group_name_shared_services" {
  description = "The name of the resource group the shared services virtual network is deployed to"
  type        = string
}

variable "subscription_id_billing" {
  description = "The subscription where Power Platform Pay-As-You-Go billing is associated to"
  type        = string
}

variable "subscription_id_resources" {
  description = "The subscription where the resources are deployed"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vnet_id_transit" {
  description = "The resource id of the transit virtual network this virtual network will be peered to"
  type        = string
}

variable "vnet_name_transit" {
  description = "The name of the transit virtual network"
  type        = string
}

variable "workload_number" {
  description = "The workload number to append to the resource name"
  type        = number
}
