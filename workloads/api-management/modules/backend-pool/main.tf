resource "azapi_resource" "backend" {
  type                      = "Microsoft.ApiManagement/service/backends@2025-09-01-preview"
  name                      = var.pool_name
  parent_id                 = var.apim_id
  schema_validation_enabled = true
  body = {
    properties = {
      description = "This is a load balanced pool for ${var.pool_name}"
      type        = "Pool"
      pool = merge({
        services = var.backends
        }, var.session_affinity ? {
        sessionAffinity = {
          sessionId = {
            source = "Cookie"
            name   = "SessionId"
          }
        }
      } : {})
    }
  }
}
