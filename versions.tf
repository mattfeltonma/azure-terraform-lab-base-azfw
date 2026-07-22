# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.10.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.74.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
  }
  required_version = ">= 1.10.0"
  # Uncomment to store state in Azure Storage
  # backend "azurerm" {}
}