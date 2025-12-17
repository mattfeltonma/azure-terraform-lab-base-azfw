########## Create Foundry Project
##########
##########

## Create the Foundry project
##
resource "azapi_resource" "foundry_project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview"
  name                      = "sampleproject${var.project_number}"
  parent_id                 = var.foundry_resource_id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {
      displayName = "Sample Project ${var.project_number}"
      description = "This is sample AI Foundry project"
    }
  }

  # Output the principalId of the managed identity and internalId (which is the workspace ID behind the scenes) of the AI Foundry project
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
## This is only required if using system-assigned managed identity for the project
resource "time_sleep" "wait_project_identities" {
  count = var.project_managed_identity_type == "smi" ? 1 : 0

  depends_on = [
    azapi_resource.foundry_project
  ]
  create_duration = "10s"
}

########## Create the required human role assignments to allow the user to perform common tasks within the Foundry project
########## 
##########

## Create a role assignment granting a user the Azure AI User role which will allow the user
## the ability to utilize the sample Foundry project
resource "azurerm_role_assignment" "foundry_user" {
  depends_on = [
    azapi_resource.foundry_project
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${local.foundry_resource_name}${azapi_resource.foundry_project.name}user")
  scope                = azapi_resource.foundry_project.id
  role_definition_name = "Azure AI User"
  principal_id         = var.user_object_id
}