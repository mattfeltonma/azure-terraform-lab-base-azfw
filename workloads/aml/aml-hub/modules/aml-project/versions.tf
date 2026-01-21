# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.8.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.1"
    }
  }
  required_version = ">= 1.8.3"
}