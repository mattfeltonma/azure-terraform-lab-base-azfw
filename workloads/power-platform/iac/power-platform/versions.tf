# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.11.0"
    }

    powerplatform = {
      source = "microsoft/power-platform"
      version = "~> 4.2.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
    }
  }
  required_version = ">= 1.10"
}