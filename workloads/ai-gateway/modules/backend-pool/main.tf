resource "azapi_resource" "backend" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = var.pool_name
  parent_id                 = var.apim_id
  schema_validation_enabled = true
  body = {
    properties = {
      description = "This is a load balanced pool for ${var.pool_name}"
      type        = "Pool"
      pool = {
        services = var.backends
      }
    }
  }
}
