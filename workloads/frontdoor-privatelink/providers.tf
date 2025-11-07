# Setup providers
provider "azapi" {
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

provider "time" {
}

provider "null" {
}