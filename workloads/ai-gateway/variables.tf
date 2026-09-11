variable "ai_gateway_integration_subnet_id" {
  description = "The subnet resource id to use for regional VNet integration when using VNet integration. The subnet must be delegated to Microsoft.Web/serverFarms"
  type        = string
  default = null
  validation {
    condition     = var.networking_model == "vnet_integrated" ? var.ai_gateway_integration_subnet_id != null : true
    error_message = "The ai_gateway_integration_subnet_id variable must be set when using VNet integration"
  }
}

variable "ai_gateway_pe_subnet_id" {
  description = "The subnet resource id to deploy the Private Endpoints to when using a Private Endpoint and VNet integration"
  type        = string
  default = null
  validation {
    condition     = var.networking_model == "vnet_integrated" ? var.ai_gateway_pe_subnet_id != null : true
    error_message = "The ai_gateway_pe_subnet_id variable must be set when using a Private Endpoint and VNet integration"
  }
}

variable "ai_gateway_private_dns_zone_name" {
  description = "The name of the Private DNS Zone to create for the API Management AI Gateway instance. This is only required when provisioning a certificate for a custom domain."
  type        = string
  default = null
  validation {
    condition     = var.provision_certificate == true ? var.ai_gateway_private_dns_zone_name != null : true
    error_message = "The ai_gateway_private_dns_zone_name variable must be set when provision_certificate is set to true"
  }
}

variable "cloudflare_api_token" {
  description = "The API token for the Cloudflare account to use for DNS validation when requesting a certificate from Let's Encrypt for the API Management AI Gateway instance custom domain"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_zone_id" {
  description = "The Cloudflare zone id for the DNS zone to use for DNS validation when requesting a certificate from Let's Encrypt for the API Management AI Gateway instance custom domain"
  type        = string
  default     = null
}

variable "entra_id_tenant_id" {
  description = "The Entra ID tenant id where the API Management instance will be created"
  type        = string
}

variable "existing_zone" {
  description = "Boolean to indicate if the Private DNS Zone already exists. If it doesn't already exist, it will be created and linked to the shared services virtual network."
  type        = bool
  default     = true
}

variable "letsencrypt_account_key" {
  description = "This is optional. The Key Vault secret id that contains the PEM encoded private key to use for the Let's Encrypt account"
  type = object({
    key_vault_resource_id = string
    secret_name           = string
  })
  default = null
  validation {
    condition     = var.provision_certificate == true ? var.letsencrypt_account_key != null : true
    error_message = "The letsencrypt_account_key variable must be set when provision_certificate is set to true"
  }
}

variable "letsencrypt_account_email" {
  description = "This is optional. The email address to use for the Let's Encrypt account"
  type        = string
  default     = null
  validation {
    condition     = var.provision_certificate == true ? var.letsencrypt_account_email != null : true
    error_message = "The letsencrypt_account_email variable must be set when provision_certificate is set to true"
  }
}

variable "networking_model" {
  description = "The networking model of the AI Gateway. This can be VNet integrated or public"
  type        = string
  default     = "vnet_integrated"
  validation {
    condition     = contains(["vnet_integrated", "public"], var.networking_model)
    error_message = "The networking_model variable must be set to either vnet_integrated or public"
  }
}

variable "provision_certificate" {
  description = "Set to true to provision a certificate using the ACME provider. If set to false, the key_vault_secret_id_versionless variable must be set with the versionless secret id of the existing certificate in Key Vault."
  type        = bool
  default     = false
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

variable "resource_group_dns" {
  description = "The resource group name where the Private DNS Zones should be deployed"
  type        = string
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the Private Endpoints to"
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

variable "trusted_ip" {
  description = "The trusted IP address or CIDR block to allow access to the Front Door"
  type        = string 
}

variable "virtual_network_id_shared_services" {
  description = "The shared services virtual network id"
  type        = string
}
