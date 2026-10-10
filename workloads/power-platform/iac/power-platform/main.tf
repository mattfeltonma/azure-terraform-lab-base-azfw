########## Create base resources
##########
##########

## Use time_static to generate a timestamp which will be used in created_date tag. Use this instead of timestamp
## so Terraform doesn't freak out every time apply is run again
##
resource "time_static" "created" {}

########## Power Platform Stuff
##########
##########

## Create the actual Microsoft.PowerPlatform/enterprisePolicies resource for network injection
##
resource "azapi_resource" "power_platform_enterprise_policy" {
  type      = "Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview"
  name      = "pp-enterprise-policy-${var.random_string}"
  parent_id = var.resource_group_id_resources
  location  = var.power_platform_environment_location

  body = {
    kind = "NetworkInjection"
    properties = {
      networkInjection = {
        virtualNetworks = [
          for idx, vnet in var.vnet_ids : {
            id = vnet
            subnet = {
              name = provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", var.vnet_subnet_ids[idx]).name
            }
          }
        ]
      }
    }
  }

  # Extract the systemId to link it to the environment
  response_export_values = [
    "properties.systemId"
  ]
}

## Create Power Platform Environment
##
resource "powerplatform_environment" "environment" {
  depends_on = [
    azapi_resource.power_platform_enterprise_policy
  ]

  display_name = "pp-env-${var.random_string}"
  location     = var.power_platform_environment_location
  environment_type = "Production"
  cadence = "Moderate"

  # Allow usage of Bing Search
  allow_bing_search = true

  # Allow M365 stuff
  allow_microsoft_365_services = true

  # Create a dataverse
  dataverse = {
    language_code     = "1033"
    currency_code     = "USD"
    # Leave it so any user can access the environment
    security_group_id = var.security_group_object_id
  }
}

## Make the environment a managed environment
##
resource "powerplatform_managed_environment" "managed_environment" {
  depends_on = [
    powerplatform_environment.environment
  ]
 
  environment_id = powerplatform_environment.environment.id
  is_usage_insights_disabled = true
  # Don't disable the ability for users to share apps with security groups
  is_group_sharing_disabled = false
  limit_sharing_mode = "NoLimit"
  max_limit_user_sharing = -1

  # Only email when there are warnings about sharing
  suppress_validation_emails = false

  # Disable solution checker since this is POC (https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-solution-checker)
  solution_checker_mode = "None"

  # Allow users to share Power Automate flows
  power_automate_is_sharing_disabled                 = false

  # Copilot settings
  copilot_allow_grant_editor_permissions_when_shared = false
  copilot_limit_sharing_mode                         = "NoLimit"
  copilot_max_limit_user_sharing                     = -1
}

## Link the enterprise policy to the managed environment
##
resource "powerplatform_enterprise_policy" "enterprise_policy" {
  depends_on = [
    powerplatform_managed_environment.managed_environment
  ]

  environment_id = powerplatform_environment.environment.id
  policy_type            = "NetworkInjection"
  system_id = azapi_resource.power_platform_enterprise_policy.output.properties.systemId
}


