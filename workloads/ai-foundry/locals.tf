locals {
    # Convert project id to a valid GUID
    raw_project_id = azapi_resource.ai_foundry_project.output.properties.internalId
    formatted_guid = "${substr(local.raw_project_id, 0, 8)}-${substr(local.raw_project_id, 8, 4)}-${substr(local.raw_project_id, 12, 4)}-${substr(local.raw_project_id, 16, 4)}-${substr(local.raw_project_id, 20, 12)}"
}