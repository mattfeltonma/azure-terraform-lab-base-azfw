resource "azurerm_api_management_backend" "backend" {
  name                 = var.backend_name
  api_management_name = var.apim_management_name
  resource_group_name    = var.apim_resource_group_name

  protocol             = "http"
  url                  = var.url

  circuit_breaker_rule {
    name = "breakThrottling"
    trip_duration = "PT10S"
    failure_condition {
      interval_duration = "PT10S"
      count = 1

      status_code_range {
        min = 429
        max = 429
      }

      status_code_range {
        min = 500
        max = 503
      }
    }
  }
}