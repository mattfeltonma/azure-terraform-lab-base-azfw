variable "apim_injection_subnet_id" {
  description = "The subnet resource id to deploy the primary gateway to when using classic internal mode or v2 with VNet injection. The subnet must be delegated to Microsoft.Web/hostingEnvironments if using v2."
  type        = string
  default = null
  validation {
    condition     = var.networking_model_v2 == "vnet_injected" || var.apim_generation_v2 == false ? var.apim_injection_subnet_id != null : true
    error_message = "The apim_injection_subnet_id variable must be set when using classic internal mode or v2 with VNet injection."
  }
}

variable "apim_integration_subnet_id" {
  description = "The subnet resource id to use for regional VNet integration when using the v2 SKU with VNet integration. The subnet must be delegated to Microsoft.Web/serverFarms"
  type        = string
  default = null
  validation {
    condition     = var.networking_model_v2 == "vnet_integrated" ? var.apim_integration_subnet_id != null : true
    error_message = "The apim_integration_subnet_id variable must be set when using the v2 SKU with VNet integration"
  }
}

variable "apim_pe_subnet_id" {
  description = "The subnet resource id to deploy the Private Endpoints to when using the v2 SKU with VNet integration."
  type        = string
  default = null
  validation {
    condition     = var.networking_model_v2 == "vnet_integrated" ? var.apim_pe_subnet_id != null : true
    error_message = "The apim_pe_subnet_id variable must be set when using the v2 SKU with VNet integration"
  }
}

variable "apim_private_dns_zone_name" {
  description = "The name of the Private DNS Zone to create for the API Management instance. This is only required when provisioning a certificate for a custom domain."
  type        = string
  default = null
  validation {
    condition     = var.provision_certificate == true ? var.apim_private_dns_zone_name != null : true
    error_message = "The apim_private_dns_zone_name variable must be set when provision_certificate is set to true"
  }
}

variable "apim_generation_v2" {
  description = "Boolean that can be set to true to deploy API Management v2"
  type        = bool
  default     = false
}

variable "cloudflare_api_token" {
  description = "The API token for the Cloudflare account to use for DNS validation when requesting a certificate from Let's Encrypt for the API Management instance custom domain"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_zone_id" {
  description = "The Cloudflare zone id for the DNS zone to use for DNS validation when requesting a certificate from Let's Encrypt for the API Management instance custom domain"
  type        = string
  default     = null
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

variable "networking_model_v2" {
  description = "The networking model for the APIM if using v2. This can be set to VNet injection or VNet integration. If set to VNet integration an additional private endpoint will be created."
  type        = string
  default     = "vnet_injected"
  validation {
    condition     = !var.apim_generation_v2 || contains(["vnet_injected", "vnet_integrated"], var.networking_model_v2)
    error_message = "The networking_model_v2 variable must be set to either vnet_injected or vnet_integrated"
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

# Not used in this one but keeping it here so I remember what the syntax looks like
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

variable "service_principal_object_id" {
  description = "The object id of the service principal that will be granted permission to the AI Foundry instances. This is used when using a service principal in the code"
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

variable "user_object_id" {
  description = "The object id of the user that will be granted permission to the AI Foundry instances. This is used when not using a service principal in the code"
  type        = string
}

variable "virtual_network_id_shared_services" {
  description = "The shared services virtual network id"
  type        = string
}
