# Setup providers
provider "azapi" {
}

provider "azapi" {
  alias           = "subscription_infrastructure"
  subscription_id = var.subscription_id_infrastructure
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias           = "subscription_infrastructure"
  subscription_id = var.subscription_id_infrastructure
  features {}
  storage_use_azuread = true
}

## Used for my lab only
##
provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
