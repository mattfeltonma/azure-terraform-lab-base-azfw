variable "app_gateway_domain_name" {
  description = "The domain name to use for the Azure Application Gateway custom domain."
  type        = string
}

variable "cloudflare_api_token" {
  description = "The API token for the Cloudflare account to use for DNS validation when requesting a certificate from Let's Encrypt for the Application Gateway custom domain."
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

variable "public_listener" {
  description = "Determines whether the Application Gateway has a public listener."
  type        = bool
  default     = true
}

variable "private_ip_address" {
  description = "The private IP address to assign to the Application Gateway if deploying as a private application gateway. Must be within the address range of the subnet specified in var.subnet_id_app_gateway."
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

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
}

variable "subnet_id_app_gateway" {
  description = "The subnet id to place the private listener of the Application Gateway. The subnet must delegated to Microsoft.Network/applicationGateways"
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

variable "tcp_port" {
  description = "The TCP port to use for the Application Gateway listener if tcp_proxy is enabled."
  type        = number
  default     = null
}

variable "trusted_ip" {
  description = "The trusted IP address or CIDR block to allow access to the Front Door"
  type        = string
}
