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

provider "time" {
}

provider "null" {
}