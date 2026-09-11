locals {
    ms_foundry_regions = {
        region1 = {
            region = "westus"
            region_code = "wus"
        }
        region2 = {
            region = "eastus2"
            region_code = "eus2"
        }
    }

    ai_services_arm_api_version = "2024-10-01" 

  ##### Combine required and user-specified tags
  # Add required tags and merge them with the provided tags
  required_tags = {
    created_date = time_static.created.rfc3339
    created_by   = data.azurerm_client_config.identity_config.object_id
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}