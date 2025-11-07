locals {
    dev_compute_instance_name   = "vmdev${var.project_number}${var.region_code}${var.random_string}"

    parsed_hub_storage_account_id = provider::azurerm::parse_resource_id(var.hub_storage_account_id)
    hub_storage_account_name      = local.parsed_hub_storage_account_id["resource_name"]

    parsed_hub_container_registry_id = provider::azurerm::parse_resource_id(var.hub_container_registry_id)
    hub_container_registry_name      = local.parsed_hub_container_registry_id["resource_name"]
}