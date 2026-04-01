variable "aca_environment_domain_name" {
  description = "This is optional. The domain name to use for the Azure Container Apps Environment custom domain."
  type        = string
  default     = null
}

variable "cloudflare_api_token" {
  description = "This is optional. The API token for the Cloudflare account to use for DNS validation when requesting a certificate from Let's Encrypt for the ACA environment custom domain."
  type        = string
  sensitive   = true
  default     = null
}

variable "letsencrypt_account_key" {
  description = "This is optional. The Key Vault secret id that contains the PEM encoded private key to use for the Let's Encrypt account"
  type = object({
    key_vault_resource_id = string
    secret_name           = string
  })
  default = null
}

variable "letsencrypt_account_email" {
  description = "This is optional. The email address to use for the Let's Encrypt account"
  type        = string
  default     = null
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
}

variable "subnet_id_aca" {
  description = "The subnet id that has been delegated to be used by Azure Container Apps Environment"
  type        = string
}

variable "subnet_id_svc" {
  description = "The subnet is to be used to create Private Endpoints for supporting resource"
  type        = string
}

variable "subscription_id_infrastructure" {
  description = "The subscription where the Private DNS Zones are located"
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
