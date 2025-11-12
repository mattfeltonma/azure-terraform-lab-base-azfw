variable "ai_foundry_instances" {
  description = "The list of AI Foundry instances to create backends for. This should be the Foundry resources names"
  type = list(string)
} 

variable "apim_private_dns_zone_name" {
  description = "The name of the Private DNS Zone to create for the API Management instance"
  type        = string
}

variable "customer_managed_public_ip" {
  description = "Boolean to indicate if customer managed public IPs are used for the API Management instance. If set to false, the public IP used for the API Management instance will be managed by Microsoft"
  type        = bool
  default     = false
}

variable "entra_id_tenant_id" {
  description = "The Entra ID tenant id where the API Management instance will be created"
  type        = string
}

variable "key_vault_id" {
  description = "The Key Vault resource id the API Management instance will have access to"
  type        = string
}

variable "key_vault_secret_id_versionless" {
  description = "The versionless Key Vault secret id for the TLS certificate to use for the API Management instance custom domain"
  type        = string
}

variable "publisher_name" {
  description = "The name of the publisher to display in the Azure API Management instance"
  type        = string
}

variable "publisher_email" {
  description = "The email address of the publisher to display in the Azure API Management instance"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "region" {
  description = "The name of the Azure region to deploy the resources to"
  type        = string
}

variable "region_code" {
  description = "The location code of the Azure region to append to the resource name"
  type        = string
}

variable "regions_additional" {
  description = "Additional regions to deploy API Management Gateways to and the corresponding subnets the gateway should be deployed to"
  type = list(object({
    region      = string
    region_code = string
    subnet_id   = string
  }))
  default = []
}

variable "resource_group_dns" {
  description = "The resource group name where the Private DNS Zones should be deployed"
  type        = string
}

variable "sku" {
  description = "The APIM SKU to use for the API Management instance"
  type        = string
  default     = "Developer_1"
}

variable "subnet_id" {
  description = "The subnet id to deploy the primary API Gateway to"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription id where the shared infrastructure resources are deployed"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "virtual_network_id_shared_services" {
  description = "The shared services virtual network id"
  type        = string
}
