# Configure the AzApi providers
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.8.0"
    }
  }
}