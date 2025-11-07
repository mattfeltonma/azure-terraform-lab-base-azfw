locals {
    build_compute_cluster_name   = "vmccbuild${var.region_code}${var.random_string}"

    parsed_workspace_storage_account_id = provider::azurerm::parse_resource_id(var.workspace_storage_account_id)
    workspace_storage_account_name      = local.parsed_workspace_storage_account_id["resource_name"]

    parsed_workspace_container_registry_id = provider::azurerm::parse_resource_id(var.workspace_container_registry_id)
    workspace_container_registry_name      = local.parsed_workspace_container_registry_id["resource_name"]
}