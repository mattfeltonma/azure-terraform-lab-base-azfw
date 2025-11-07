# Setup providers
provider "azapi" {
}

provider "azapi" {
  alias           = "subscription_workload_production"
  subscription_id = var.subscription_id_workload_production
}

provider "azapi" {
  alias           = "subscription_workload_non_production"
  subscription_id = var.subscription_id_workload_non_production
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
  alias           = "subscription_workload_production"
  subscription_id = var.subscription_id_workload_production
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias           = "subscription_workload_non_production"
  subscription_id = var.subscription_id_workload_non_production
  features {}
  storage_use_azuread = true
}

provider "azurerm" {
  alias           = "subscription_infrastructure"
  subscription_id = var.subscription_id_infrastructure
  features {}
  storage_use_azuread = true
}