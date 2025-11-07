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

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.1"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
  }
  required_version = ">= 1.8.3"
}