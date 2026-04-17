########## Create resource group and Log Analytics Workspace
##########
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_aca" {
  name     = "rgaca${var.region_code}${var.random_string}"
  location = var.region
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a Log Analytics Workspace that all resources specific to this workload will
## write configured resource logs and metrics to
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawaca${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create Network Security Perimeters that will be used to restrict access to resources that support the Container Apps instance
########## that support the Container Apps instance
##########

## Create a Network Security Perimeter that will be used to restrict access to resources that support
## the Container Apps instance
resource "azapi_resource" "nsp_aca_resources" {
  depends_on = [
    azurerm_resource_group.rg_aca,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspacares${var.region_code}${var.random_string}"
  location  = var.region
  parent_id = azurerm_resource_group.rg_aca.id
  tags      = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }

}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_aca_resources" {
  depends_on = [
    azapi_resource.nsp_aca_resources
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_aca_resources[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspIntraPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPrivateInboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterOutboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspOutboundAttempt"
  }
}

## Create a Network Security Perimeter profile that will be associated with the Key Vault instance used
## to store the certificate used for the custom domain name of the Container Apps Environment.
resource "azapi_resource" "profile_nsp_key_vault_aca_env" {
  depends_on = [
    azapi_resource.nsp_aca_resources
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pkvacaenv"
  location  = var.region
  parent_id = azapi_resource.nsp_aca_resources[0].id
}

## Create an access rule to allow the ACA service to connect to the key Vault instance
## to pull the certificate to associate it with the custom domain name of the Container Apps Environment
resource "azapi_resource" "access_rule_key_vault_aca_env_sub_id" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_aca_env
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arkvacaenvtrustedsubs"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_key_vault_aca_env[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      # Allow the subscription containing the ACA to bypass the NSP
      subscriptions = [
        {
          id = data.azurerm_subscription.current.id
        }
      ]
    }
  }
}

## Create an access rule to allow the machine deploying the Terraform resources data plane access to the Key Vault
## Only required for my shitty lab
resource "azapi_resource" "access_rule_key_vault_aca_env_ipprefix" {
  depends_on = [
    azapi_resource.access_rule_key_vault_aca_env_sub_id
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arkvacaenvtrustedips"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_key_vault_aca_env[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      # This address prefix exception is only required for this lab
      addressPrefixes = [
        "${var.trusted_ip}/32"
      ]
    }
  }
}

########## Create an Azure Key Vault instance and supporting resources to store the certificate used for the custom domain name
########## for the Container Apps Environment
##########

## Create an Azure Key Vault instance to store the certificate used for the custom domain name
##
resource "azurerm_key_vault" "key_vault_aca_env_custom_domain" {
  depends_on = [
    azurerm_resource_group.rg_aca,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name                = "kvacaenv${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name
  # Adding tag specific to my environment. Not needed outside my environment
  # TODO: Remove this tag when NSPs support cross-NSP links which will allow diagnostic
  # logs to be delivered outside the NSP
  tags = merge(var.tags, { SecurityControl = "Ignore" })

  sku_name  = "premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  # Configure vault to support Azure RBAC-based authorization of data-plane
  rbac_authorization_enabled = true

  # Disable purge protection since this is a lab
  purge_protection_enabled = false

  # TODO: 3/2026 This is set to true for now to allow the IP exception that is specific to my environment. Once NSPs support cross-NSP links (which will address diagnostic log delivery issue)
  # then this can be set to false and the network_acls section can be removed and instead rely on NSP ruleset.
  public_network_access_enabled = true
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []
    ip_rules = [
      var.trusted_ip
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_aca_env_custom_domain" {
  depends_on = [
    azurerm_key_vault.key_vault_aca_env_custom_domain
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_aca_env_custom_domain[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Create a Network Security Perimeter resource assocation to associate the Key Vault with the NSP profile
##
resource "azapi_resource" "assoc_aca_env_key_vault_custom_domain" {
  depends_on = [
    azapi_resource.access_rule_key_vault_aca_env_ipprefix,
    azapi_resource.access_rule_key_vault_aca_env_sub_id,
    azurerm_key_vault.key_vault_aca_env_custom_domain
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rapkvfoundrysecrets"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_aca_resources[0].id
  schema_validation_enabled = false

  body = {
    properties = {
      # TODO: 3/2026 Typically don't enforce since no NSP links yet, but need to in order to restrict network access to Key Vault
      # while supporting ACA pulling from it
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_key_vault.key_vault_aca_env_custom_domain[0].id
      }
      profile = {
        id = azapi_resource.profile_nsp_key_vault_aca_env[0].id
      }
    }
  }
}

## Create a Private Endpoint to the Key Vault
## 
resource "azurerm_private_endpoint" "private_endpoint_key_vault_aca_env" {
  depends_on = [
    azapi_resource.assoc_aca_env_key_vault_custom_domain
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name                = "pekvacaenv${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "pekvacaenv${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.key_vault_aca_env_custom_domain[0].id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_aca_env_custom_domain[0].name}vault"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }

  tags = var.tags
}

########## Create a certificate that will be used for the custom domain name of the Container Apps Environment and store it in the Key Vault
##########
##########

## Create a certificate request in Azure Key Vault
##
resource "azurerm_key_vault_certificate" "aca_env_certificate" {
  depends_on = [
    azapi_resource.assoc_aca_env_key_vault_custom_domain,
    azurerm_private_endpoint.private_endpoint_key_vault_aca_env,
    azurerm_key_vault.key_vault_aca_env_custom_domain
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name         = "aca-env${var.random_string}"
  key_vault_id = azurerm_key_vault.key_vault_aca_env_custom_domain[0].id

  certificate_policy {
    issuer_parameters {
      # Use unknown since it's not Digicert or GlobalSign
      name = "Unknown"
    }

    key_properties {
      # Private key must be exportable for APIM to pull the PFX into its own store
      exportable = true
      key_size   = 4096
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=*.${var.aca_environment_domain_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [
          "*.${var.aca_environment_domain_name}"
        ]
      }

      key_usage = [
        "digitalSignature",
        "keyEncipherment"
      ]
    }
  }
}

## Create a registration object
##
resource "acme_registration" "aca_env_certificate_registration_letsencrypt" {
  depends_on = [
    data.azurerm_key_vault_secret.letsencrypt_account_key
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  # Replaces \r\n with newlines to account for the way Key Vault butchers the PEM
  account_key_pem = replace(
  replace(
    data.azurerm_key_vault_secret.letsencrypt_account_key[0].value,
    "\\r\\n",
    "\n"
  ),
  "\\n",
  "\n"
  )
  email_address   = var.letsencrypt_account_email

  # Preserve account key so it can be reused
  lifecycle {
    prevent_destroy = true
  }
}

## Create a certificate request using Cloudflare for DNS validation
##
resource "acme_certificate" "aca_env_certificate_request" {
  depends_on = [
    data.azurerm_key_vault_secret.letsencrypt_account_key
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  account_key_pem         = acme_registration.aca_env_certificate_registration_letsencrypt[0].account_key_pem
  certificate_request_pem = data.external.certificate_csr[0].result.csr

  dns_challenge {
    provider = "cloudflare"
    config = {
      CLOUDFLARE_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
  # Don't revoke certs on destroy since they are revoked every 90 days and I may want to redeploy
  revoke_certificate_on_destroy = false
}

## Add the signed certificate into Key Vault to complete the CSR process
##
resource "null_resource" "merge_certificate" {
  depends_on = [
    acme_certificate.aca_env_certificate_request
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  triggers = {
    certificate_pem = acme_certificate.aca_env_certificate_request[0].certificate_pem
  }

  provisioner "local-exec" {
    command = <<EOT
      # Check if the certificate is still in pending state
      CERT_STATUS=$(az keyvault certificate pending show \
        --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_aca_env_custom_domain[0].id).resource_name} \
        --name ${azurerm_key_vault_certificate.aca_env_certificate[0].name} \
        --query "status" -o tsv 2>/dev/null || echo "notfound")
      
      if [ "$CERT_STATUS" = "inProgress" ]; then
        echo "Certificate is pending, merging signed certificate..."
        echo '${acme_certificate.aca_env_certificate_request[0].certificate_pem}' > ${path.module}/signed-cert.pem
        echo '${acme_certificate.aca_env_certificate_request[0].issuer_pem}' >> ${path.module}/signed-cert.pem
        az keyvault certificate pending merge \
          --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_aca_env_custom_domain[0].id).resource_name} \
          --name ${azurerm_key_vault_certificate.aca_env_certificate[0].name} \
          --file ${path.module}/signed-cert.pem
        rm ${path.module}/signed-cert.pem
        echo "Certificate merged successfully."
      else
        echo "Certificate is not in pending state (status: $CERT_STATUS), skipping merge."
      fi
    EOT
  }
}

########## Create an Azure Container Registry and Application Insights instance
##########
##########

## Create an Azure Container Registry
##
resource "azurerm_container_registry" "acr" {
  name                = "acr${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name
  sku                 = "Premium"

  admin_enabled          = false
  anonymous_pull_enabled = false

  public_network_access_enabled = false

  tags = var.tags
}

## Enable diagnostic logs for Azure Container Registry
##
resource "azurerm_monitor_diagnostic_setting" "diag_acr" {
  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}

## Create the Private Endpoint to connect to Azure Container Registry
##
resource "azurerm_private_endpoint" "private_endpoint_acr" {
  depends_on = [
    azurerm_container_registry.acr
  ]

  name                = "peacr${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name

  subnet_id = var.subnet_id_svc

  private_service_connection {
    name                           = "peacr${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_container_registry.acr.name}registry"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    ]
  }

  tags = var.tags
}

## Create Application Insights instance used for DAPR service-to-service signals
##
resource "azurerm_application_insights" "app_insights_aca" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  name                = "ai${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name

  application_type = "other"
  workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  tags = var.tags
}

## Add 30 second sleep to allow for Application Insights 
## instance to be provisioned and key ready to use
resource "null_resource" "wait_for_app_insights_aca" {
  depends_on = [
    azurerm_application_insights.app_insights_aca
  ]
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

########## Create the user-assigned managed identity and relevant RBAC role assignments
##########
##########

## Create the user-assigned managed for the Container Apps Environment
##
resource "azurerm_user_assigned_identity" "umi_aca_env" {
  depends_on = [
    azurerm_resource_group.rg_aca,
    null_resource.merge_certificate
  ]

  name                = "umiacaenv${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_aca.name

  tags = var.tags
}

## Sleep for 10 seconds to allow the user-assigned managed identity to replicate through Entra ID
##
resource "time_sleep" "wait_umi_aca_env" {

  depends_on = [
    azurerm_user_assigned_identity.umi_aca_env
  ]
  create_duration = "120s"
}

## Create an Azure RBAC role assignment granting the user-assigned managed identity for Container Apps Environment
## the Key Vault Secrets User role on the Key Vault instance holding the certificate for the Container Apps Environment custom domain
##
resource "azurerm_role_assignment" "umi_aca_env_key_vault_certificate_user" {
  depends_on = [
    time_sleep.wait_umi_aca_env,
    azurerm_key_vault.key_vault_aca_env_custom_domain
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  scope                = azurerm_key_vault.key_vault_aca_env_custom_domain[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.umi_aca_env.principal_id
}

## Sleep for 120 seconds to allow the replication of the RBAC role assignments to propagate through Azure
##
resource "time_sleep" "wait_umi_aca_env_permissions" {
  depends_on = [
    azurerm_role_assignment.umi_aca_env_key_vault_certificate_user
  ]
  create_duration = "120s"
}

########## Create the Container App Environment
##########
##########

## Create a Container Apps Environment with a custom domain and restrict inbound and outbound traffic
## to the customer's virtual network
resource "azapi_resource" "container_app_environment" {
  depends_on = [
    null_resource.wait_for_app_insights_aca,
    time_sleep.wait_umi_aca_env_permissions,
    null_resource.merge_certificate
  ]

  type      = "Microsoft.App/managedEnvironments@2025-07-01"
  name      = "caevnetpriv${var.region_code}${var.random_string}"
  location  = var.region
  parent_id = azurerm_resource_group.rg_aca.id

  body = {
    properties = {
      # Send container logs to Azure Monitor which will allow you to direct them
      # via platform diagnostic logs
      appLogsConfiguration = {
        destination = "azure-monitor"
      }
      # Set a custom domain for the environment
      customDomainConfiguration =  var.aca_environment_domain_name != null ? {
        dnsSuffix = "${var.aca_environment_domain_name}"
        certificateKeyVaultProperties = {
          keyVaultUrl = azurerm_key_vault_certificate.aca_env_certificate[0].versionless_secret_id
          identity = azurerm_user_assigned_identity.umi_aca_env.id
        }
      } : null
      # Set the managed resource group to hold the internal load balancer
      infrastructureResourceGroup = "rgmanagedcaepriv${var.region_code}${var.random_string}"
      
      # Enforce encryption in transit between Container Apps
      peerTrafficConfiguration = {
        encryption = {
          enabled = true
        }
      }

      # Disable public network access
      publicNetworkAccess = "Disabled"
    
      # Configure the environment to use the designated subnet for inbound and outbound traffic
      # to the environment
      vnetConfiguration = {
        internal = true
        infrastructureSubnetId = var.subnet_id_aca
      }

      # Create a dedicated workload profile
      workloadProfiles =[
        {
          name = "dedicated"
          workloadProfileType = "D4"
          maximumCount = 2
          minimumCount = 1
        },
        # This profile is automatically created but this keeps Terraform state standard
        {
          name = "Consumption",
          workloadProfileType = "Consumption"      }
      ]

      # Disable zone redundancy to mitigate capacity issues
      zoneRedundant = false
    }
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.umi_aca_env.id}" = {}
      }
    }
    tags = var.tags
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for Container Apps Environment
##
resource "azurerm_monitor_diagnostic_setting" "diag_cae" {
  depends_on = [
    azapi_resource.container_app_environment
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.container_app_environment.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  enabled_log {
    category = "AppEnvSpringAppConsoleLogs"
  }

  enabled_log {
    category = "AppEnvSessionConsoleLogs"
  }

  enabled_log {
    category = "AppEnvSessionPoolEventLogs"
  }

  enabled_log {
    category = "AppEnvSessionLifeCycleLogs"
  }
}

## Create the A record in the private DNS zone that will be used for the custom domain of the Container Apps Environment
##
resource "azurerm_private_dns_a_record" "a_record_aca_env_custom_domain" {
  depends_on = [
    azapi_resource.container_app_environment
  ]

  count = var.aca_environment_domain_name != null ? 1 : 0

  name                = "*"
  zone_name           = var.aca_environment_domain_name
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records             = [
    azapi_resource.container_app_environment.output.properties.staticIp
  ]
}