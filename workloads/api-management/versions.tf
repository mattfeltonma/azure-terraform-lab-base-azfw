# Configure the AzApi and AzureRM providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.11.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0.1"
    }
 
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
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
  required_version = ">= 1.10.0"
}