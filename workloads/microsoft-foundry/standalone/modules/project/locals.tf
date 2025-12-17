locals {
    # Extract resource name from the Foundry resource resource id
    foundry_resource_name = provider::azurerm::parse_resource_id(var.foundry_resource_id)["resource_name"]
    foundry_resource_resource_group_name = provider::azurerm::parse_resource_id(var.foundry_resource_id)["resource_group_name"]

    # Convert project id to a valid GUID
    raw_project_id = azapi_resource.foundry_project.output.properties.internalId
    formatted_guid = "${substr(local.raw_project_id, 0, 8)}-${substr(local.raw_project_id, 8, 4)}-${substr(local.raw_project_id, 12, 4)}-${substr(local.raw_project_id, 16, 4)}-${substr(local.raw_project_id, 20, 12)}"
}