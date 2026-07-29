locals {
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