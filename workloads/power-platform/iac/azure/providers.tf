# Setup providers
provider "azapi" {
  subscription_id = var.subscription_id_resources
}

provider "azapi" {
  alias           = "subscription_billing"
  subscription_id = var.subscription_id_billing
}

provider "azurerm" {
  subscription_id = var.subscription_id_resources
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias           = "subscription_billing"
  subscription_id = var.subscription_id_billing
  features {}
  storage_use_azuread = true
}

provider "time" {
}

provider "null" {
}