# Configure the AzApi providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.13.0"
    }
  }
}