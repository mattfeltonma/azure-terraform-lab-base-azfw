locals {
    # Extract resource name from the Foundry resource resource id
    foundry_resource_name = provider::azurerm::parse_resource_id(var.foundry_resource_id)["resource_name"]
    foundry_resource_resource_group_name = provider::azurerm::parse_resource_id(var.foundry_resource_id)["resource_group_name"]

    # Extract resource name from shared agent resources
    agent_ai_search_name = var.shared_agent_ai_search_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_agent_ai_search_resource_id)["resource_name"] : null
    agent_cosmosdb_account_name = var.shared_agent_cosmosdb_account_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_agent_cosmosdb_account_resource_id)["resource_name"] : null
    agent_cosmosdb_account_resource_group_name = var.shared_agent_cosmosdb_account_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_agent_cosmosdb_account_resource_id)["resource_group_name"] : null
    agent_storage_account_name = var.shared_agent_storage_account_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_agent_storage_account_resource_id)["resource_name"] : null
    agent_bing_grounding_search_name = var.shared_bing_grounding_search_resource_id != null ? provider::azapi::parse_resource_id("Microsoft.Bing/accounts",var.shared_bing_grounding_search_resource_id).name : null
    resource_app_insights_name = var.shared_app_insights_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_app_insights_resource_id)["resource_name"] : null
    resource_byo_key_vault_name = var.shared_byo_key_vault_resource_id != null ? provider::azurerm::parse_resource_id(var.shared_byo_key_vault_resource_id)["resource_name"] : null


    # Create unique connection names for each project
    agent_ai_search_connection_name = var.shared_agent_ai_search_resource_id != null ? substr("conn${var.project_number}${local.agent_ai_search_name}", 0, 60) : null
    agent_cosmosdb_account_connection_name = var.shared_agent_cosmosdb_account_resource_id != null ? substr("conn${var.project_number}${local.agent_cosmosdb_account_name}", 0, 60) : null
    agent_storage_account_connection_name = var.shared_agent_storage_account_resource_id != null ? substr("conn${var.project_number}${local.agent_storage_account_name}", 0, 60) : null
    agent_bing_grounding_search_connection_name = var.shared_bing_grounding_search_resource_id != null ? substr("conn${var.project_number}${local.agent_bing_grounding_search_name}", 0, 60) : null
    agent_external_openai_connection_name = var.shared_external_openai != null ? substr("conn${var.project_number}${var.shared_external_openai.name }", 0, 60) : null

    # Convert project id to a valid GUID
    raw_project_id = azapi_resource.foundry_project.output.properties.internalId
    formatted_guid = "${substr(local.raw_project_id, 0, 8)}-${substr(local.raw_project_id, 8, 4)}-${substr(local.raw_project_id, 12, 4)}-${substr(local.raw_project_id, 16, 4)}-${substr(local.raw_project_id, 20, 12)}"
}