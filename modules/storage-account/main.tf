## Create a storage account
##
resource "azurerm_storage_account" "storage_account" {
  name                = "st${var.purpose}${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.region
  tags                = var.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable key-based access
  shared_access_key_enabled = false

  # Disable public access for blob containers
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"

    # Configure bypass if bypass isn't an empty list
    bypass         = var.network_trusted_services_bypass
    ip_rules = var.allowed_ips
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Configure diagnostic settings for blob, file, queue, and table services to send logs to Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_flow_logs_blob" {

  depends_on = [
    azurerm_storage_account.storage_account
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/blobServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_flow_logs_file" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag_storage_flow_logs_blob
  ]

  name                       = "diag-file"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/fileServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_flow_logs_queue" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag_storage_flow_logs_file
  ]

  name                       = "diag-default"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/queueServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_flow_logs_table" {

  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag_storage_flow_logs_queue
  ]

  name                       = "diag-table"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/tableServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
