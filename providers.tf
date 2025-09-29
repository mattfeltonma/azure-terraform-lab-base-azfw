# Setup providers
provider "azapi" {
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

provider "random" {
}

provider "null" {
}