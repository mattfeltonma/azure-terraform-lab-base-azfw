## Create a Log Analytics Workspace in the primary region
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.environments["primary"].region_code}${var.random_string}"
  location            = var.environments["primary"].region_name
  resource_group_name = var.environments["primary"].region_resource_group_name

  sku               = "PerGB2018"
  retention_in_days = var.retention_in_days

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Configure diagnostic settings for Log Analytics Workspace in the primary region
##
resource "azurerm_monitor_diagnostic_setting" "diag_law" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_log_analytics_workspace.log_analytics_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "SummaryLogs"
  }
}

## Create Data Collection Endpoints in each region
##
resource "azurerm_monitor_data_collection_endpoint" "endpoint" {
  for_each = var.environments

  name                = "dce${var.purpose}${each.value.region_code}${var.random_string}"
  resource_group_name = each.value.region_resource_group_name
  location            = each.value.region_name

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create optional Data Collection Rule for Windows in the primary environment only
##
resource "azurerm_monitor_data_collection_rule" "rule_windows" {
  name                        = "dcrwin${var.purpose}${var.random_string}"
  resource_group_name         = var.environments["primary"].region_resource_group_name
  location                    = var.environments["primary"].region_name
  description                 = "This data collection rule captures common Windows logs and metrics"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.endpoint["primary"].id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
      name                  = "lawdestination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["lawdestination"]
  }

  data_sources {
    windows_event_log {
      name    = "Windows-Event-Logs"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]",
        "Security!*[System[(band(Keywords,13510798882111488))]]",
        "System!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]",
        "Directory Services!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=5)]]"
      ]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create optional Data Collection Rule for Linux in the primary region
##
resource "azurerm_monitor_data_collection_rule" "rule_linux" {
  name                        = "dcrlin${var.purpose}${var.random_string}"
  resource_group_name         = var.environments["primary"].region_resource_group_name
  location                    = var.environments["primary"].region_name
  description                 = "This data collection rule captures common Linux logs and metrics"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.endpoint["primary"].id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
      name                  = "lawdestination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["lawdestination"]
  }
 
  data_sources {
    syslog {
      facility_names = ["syslog"]
      log_levels     = [
        "Alert",
        "Critical",
        "Emergency"
     ]
      name           = "syslogBase"
      streams        = ["Microsoft-Syslog"]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

}
