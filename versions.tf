# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.5.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.44.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
  required_version = ">= 1.8.3"
  # Uncomment to store state in Azure Storage
  # backend "azurerm" {}
}