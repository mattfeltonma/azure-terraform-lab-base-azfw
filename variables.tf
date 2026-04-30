variable "address_space_onpremises" {
  description = "The address space on-premises"
  type        = string
}

variable "address_space_cloud" {
  description = "The address space in the cloud"
  type        = string
}

variable "environment_details" {
  description = "The environment details including environment name, region name and address space. This should include primary and secondary if multi-region is required"
  type = map(object({
    region_name   = string
    address_space = string
  }))
}

variable "key_vault_admin" {
  description = "The object id of the user or service principal to assign the Key Vault Administrator role to"
  type        = string

}

variable "hero_region" {
  description = "The 'hero' region to deploy a third workload spoke to. This is primarily used for Microsoft Foundry use cases because hero regions tend to get new services first."
  type        = string
  default     = "eastus2"
}

variable "network_watcher_name_prefix" {
  description = "The prefix name of the network watcher resource"
  type        = string
  default     = "NetworkWatcher_"
}

variable "network_watcher_resource_group_name" {
  description = "The name of the network watcher resource group"
  type        = string
  default     = "NetworkWatcherRG"
}

variable "private_dns_namespaces" {
  description = "The private DNS zones to create and link to the shared services virtual network"
  type        = map(string)
}

variable "vm_sku_size" {
  description = "The SKU size to use for any virtual machines created by the lab"
  type        = string
  default     = "Standard_D2s_v3"
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

variable "trusted_ip" {
  description = "This is the trusted IP address that will be allowed through service firewalls for Key Vault"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resources"
  type        = map(string)
}
