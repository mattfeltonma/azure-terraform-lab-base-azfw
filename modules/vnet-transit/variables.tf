variable "address_space_amlcpt" {
  description = "The address spaces used by the subnet deleted to Azure Machine Learning compute"
  type        = list(string)
}

variable "address_space_apim" {
  description = "The address spaces used by the APIM instances"
  type        = list(string)
}

variable "address_space_azure" {
  description = "The address space used in the Azure environment"
  type        = string
}

variable "address_space_onpremises" {
  description = "The address space used on-premises"
  type        = string
}

variable "address_space_vnet" {
  description = "The address space to assign to the virtual network. This must be /22 or larger."
  type        = string
  validation {
    condition     = tonumber(split("/", var.address_space_vnet)[1]) <= 22
    error_message = "The address space must be /22 or larger. Current value has a prefix of /${split("/", var.address_space_vnet)[1]}."
  }
}

variable "dns_servers" {
  description = "The DNS Servers to configure for the virtual network"
  type        = list(string)
  default    = ["168.63.129.16"]
}

variable "private_resolver_inbound_endpoint_subnet_cidr" {
  description = "The address space to assign to the subnet hosting the Private DNS Resolver inbound endpoints"
  type        = string
}

variable "firewall_sku_tier" {
  description = "The SKU tier of the Azure Firewall. This can be standard or premium"
  type        = string
  default     = "Standard"
}

variable "log_analytics_workspace_guid" {
  description = "The GUID of the Log Analytics Workspace"
  type        = string
}

variable "log_analytics_workspace_region" {
  description = "The region of the Log Analytics Workspace"
  type        = string
}

variable "log_analytics_workspace_resource_id" {
  description = "The resource id of the Log Analytics Workspace"
  type        = string
}

variable "network_watcher_name" {
  description = "The resource id of the Network Watcher to send vnet flow logs to"
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

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The region code to append to the resource name"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "storage_account_id_flow_logs" {
  description = "The resource id of the storage account to send virtual network flow logs to"
  type        = string
}

variable "subnet_cidr_firewall" {
  description = "The address space to assign to the subnet used by Azure Firewall"
  type        = string
}

variable "subnet_cidr_gateway" {
  description = "The address space to assign to the Virtual Network Gateway subnet"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vnet_cidr_ss" {
  description = "The address space to assign to the shared services virtual network"
  type        = string
}

variable "vnet_cidr_wl" {
  description = "The address spaces to assigned to the workload virtual networks"
  type        = list(string)
}