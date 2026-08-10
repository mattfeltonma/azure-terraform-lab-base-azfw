provider "azapi" {
  subscription_id = var.subscription_id_workload
}

provider "azapi" {
  alias           = "subscription_infrastructure"
  subscription_id = var.subscription_id_infrastructure
}

provider "azurerm" {
  subscription_id = var.subscription_id_workload
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
