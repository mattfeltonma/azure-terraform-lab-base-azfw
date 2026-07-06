# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.79.0"
    }
  }
  required_version = ">= 1.10"
}