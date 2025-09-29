variable "address_space_azure" {
  description = "The address space assigned to Azure"
  type        = string
}

variable "address_space_onpremises" {
  description = "The address space assigned to on-premises"
  type        = string
}

variable "address_space_vnet" {
  description = "The address space assigned to virtual network"
  type        = string
}

variable "dns_servers" {
  description = "The DNS servers to be set on the virtual network"
  type        = list(string)
  default     = ["168.63.129.16"]
}

variable "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall"
  type        = string
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

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The location code of the Azure regionto append to the resource name"
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

variable "resource_group_id" {
  description = "The resource id of the resource group to deploy the resources to"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "resource_group_name_hub" {
  description = "The name of the resource group the hub virtual network is deployed to"
  type        = string
}

variable "storage_account_id_flow_logs" {
  description = "The resource id of the storage account to send virtual network flow logs to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vm_admin_username" {
  description = "The username to assign to the virtual machine"
  type        = string
}

variable "vm_admin_password" {
  description = "The password to assign to the virtual machine"
  type        = string
  sensitive   = true
}

variable "vm_sku_size" {
  description = "The SKU size for the virtual machine."
  type        = string
  default = "Standard_D2s_v3"
}

variable "vnet_id_transit" {
  description = "The resource id of the transit virtual network this virtual network will be peered to"
  type        = string
}

variable "vnet_name_transit" {
  description = "The name of the transit virtual network"
  type        = string
}

