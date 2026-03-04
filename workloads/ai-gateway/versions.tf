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

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }

    ## Used for my lab only
    ##
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.45.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
  required_version = ">= 1.8.3"
}