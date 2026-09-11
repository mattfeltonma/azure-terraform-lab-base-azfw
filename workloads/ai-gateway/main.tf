########## Create base resources
##########
##########

## Use time_static to generate a timestamp which will be used in created_date tag. Use this instead of timestamp
## so Terraform doesn't freak out every time apply is run again
##
resource "time_static" "created" {}

########## Create a resource group for the workload resources
##########
##########

## Create resource group where resources in this template will be deployed to
##
resource "azurerm_resource_group" "rg_ai_gateway" {
  name     = "rgapim${var.region_code}${var.random_string}"
  location = var.region
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create Log Analytics Workspace for the resources created in this deployment
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_workload" {
  name                = "lawaigw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Pause for 30 seconds after Log Analytics Workspace is created to allow for replication
##
resource "time_sleep" "sleep_law_creation" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]
  create_duration = "30s"
}

########## Create Network Security Perimeters that will be used to restrict access to resources
########## that support features within API Management AI Gateway instance
########## For now this is just the Key Vault used to hold the certificate for the custom domain feature

## Create a Network Security Perimeter that will be used to restrict access to resources that support
## the API Management AI Gateway instance
resource "azurerm_network_security_perimeter" "nsp_ai_gateway_resources" {
  depends_on = [
    azurerm_resource_group.rg_ai_gateway,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                = "nspaigwres${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  location            = var.region
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_ai_gateway_resources" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_gateway_resources
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                       = "diag-base"
  target_resource_id         = azurerm_network_security_perimeter.nsp_ai_gateway_resources[0].id
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
## to store the certificate used for the custom domain name of the API Management AI Gateway instance
resource "azurerm_network_security_perimeter_profile" "profile_nsp_key_vault_ai_gateway" {
  depends_on = [
    azurerm_network_security_perimeter.nsp_ai_gateway_resources
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                          = "pkvaigw"
  network_security_perimeter_id = azurerm_network_security_perimeter.nsp_ai_gateway_resources[0].id
}

## Create an access rule to allow the API Management AI Gateway intsance
## to pull the certificate to associate it with the custom domain name
## Create an access rule to allow the machine deploying the Terraform resources data plane access to the storage account
## Only required for my shitty lab
resource "azurerm_network_security_perimeter_access_rule" "access_rule_key_vault_ai_gateway_sub_id" {
  depends_on = [
    azurerm_network_security_perimeter_profile.profile_nsp_key_vault_ai_gateway
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                                  = "arkvaigwtrustedsubs"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_key_vault_ai_gateway[0].id
  direction                             = "Inbound"
  subscription_ids                        = [
    data.azurerm_subscription.current.id
  ]
}

## Create an access rule to allow the machine deploying the Terraform resources data plane access to the Key Vault
## Only required for my shitty lab
resource "azurerm_network_security_perimeter_access_rule" "access_rule_key_vault_ai_gateway_ipprefix" {
  depends_on = [
    azurerm_network_security_perimeter_access_rule.access_rule_key_vault_ai_gateway_sub_id
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                                  = "arkvaigwtrustedips"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_key_vault_ai_gateway[0].id
  direction                             = "Inbound"
  address_prefixes = [
    "${var.trusted_ip}/32"
  ]
}

########## Create the Key Vault and certificate if the provision_certificate variable is set to true.
########## This certificate will be used to configure a custom domain on the API Management instance
##########

## Create an Azure Key Vault instance to store the certificate used for the custom domain name
##
resource "azurerm_key_vault" "key_vault_ai_gateway_custom_domain" {
  depends_on = [
    azurerm_resource_group.rg_ai_gateway,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                = "kvaigw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  # Adding tag specific to my environment. Not needed outside my environment
  # TODO: Remove this tag when NSPs support cross-NSP links which will allow diagnostic
  # logs to be delivered outside the NSP
  tags = merge(local.tags, { SecurityControl = "Ignore" })

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
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for the Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_ai_gateway_custom_domain" {
  depends_on = [
    azurerm_key_vault.key_vault_ai_gateway_custom_domain
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                       = "diag"
  target_resource_id         = azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].id
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
resource "azurerm_network_security_perimeter_association" "assoc_ai_gateway_env_key_vault_custom_domain" {
  depends_on = [
    azurerm_key_vault.key_vault_ai_gateway_custom_domain,
    azurerm_network_security_perimeter_access_rule.access_rule_key_vault_ai_gateway_ipprefix,
    azurerm_network_security_perimeter_access_rule.access_rule_key_vault_ai_gateway_sub_id
  ]

  count = var.provision_certificate == true ? 1 : 0

  name = "rapkvcustomdomain"
  # TODO: 7/2026 Switch NSP to enforced mode once cross NSP links are introduced. This will resolve diagnostic settings delivery of signals being blocked by NSP
  access_mode                           = "Learning"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.profile_nsp_key_vault_ai_gateway[0].id
  resource_id                           = azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].id
}

## Create a Private Endpoint to the Key Vault
## 
resource "azurerm_private_endpoint" "private_endpoint_key_vault_ai_gateway_env" {
  depends_on = [
    azurerm_key_vault.key_vault_ai_gateway_custom_domain,
    azurerm_network_security_perimeter_association.assoc_ai_gateway_env_key_vault_custom_domain
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                = "pekvaigwenv${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name

  subnet_id = var.subnet_id_private_endpoints

  private_service_connection {
    name                           = "pekvcaenv${var.region_code}${var.random_string}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].name}vault"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
  }

  tags = local.tags
}

## Create a certificate request in Azure Key Vault
##
resource "azurerm_key_vault_certificate" "ai_gateway_certificate" {
  depends_on = [ 
    azurerm_private_endpoint.private_endpoint_key_vault_ai_gateway_env,
    azurerm_network_security_perimeter_association.assoc_ai_gateway_env_key_vault_custom_domain
   ]

  count = var.provision_certificate == true ? 1 : 0

  name         = "ai-gateway-certificate-v3${var.random_string}"
  key_vault_id = azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].id

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
      subject            = "CN=aigw-example${var.random_string}.${var.ai_gateway_private_dns_zone_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = concat(
          [
            "aigw-example${var.random_string}.${var.ai_gateway_private_dns_zone_name}",
            "aigw-example${var.random_string}${var.region_code}.${var.ai_gateway_private_dns_zone_name}",
            # These additional SANS are only used for classic SKUs and really aren't even used there
            "aigw-example${var.random_string}.management.${var.ai_gateway_private_dns_zone_name}",
            "aigw-example${var.random_string}.scm.${var.ai_gateway_private_dns_zone_name}",
            "aigw-example${var.random_string}.developer.${var.ai_gateway_private_dns_zone_name}"
          ]
        )
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
resource "acme_registration" "ai_gateway_certificate_registration_letsencrypt" {
  depends_on = [
    azurerm_key_vault_certificate.ai_gateway_certificate,
    data.azurerm_key_vault_secret.letsencrypt_account_key
  ]

  count = var.provision_certificate == true ? 1 : 0

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
resource "acme_certificate" "ai_gateway_certificate_request" {
  count = var.provision_certificate == true ? 1 : 0

  account_key_pem         = acme_registration.ai_gateway_certificate_registration_letsencrypt[0].account_key_pem
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
  count = var.provision_certificate == true ? 1 : 0

  depends_on = [
    acme_certificate.ai_gateway_certificate_request
  ]

  triggers = {
    certificate_pem = acme_certificate.ai_gateway_certificate_request[0].certificate_pem
  }

  provisioner "local-exec" {
    command = <<EOT
      # Check if the certificate is still in pending state
      CERT_STATUS=$(az keyvault certificate pending show \
        --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_apim_custom_domain[0].id).resource_name} \
        --name ${azurerm_key_vault_certificate.apim_gateway_certificate[0].name} \
        --query "status" -o tsv 2>/dev/null || echo "notfound")
      
      if [ "$CERT_STATUS" = "inProgress" ]; then
        echo "Certificate is pending, merging signed certificate..."
        echo '${acme_certificate.ai_gateway_certificate_request[0].certificate_pem}' > ${path.module}/signed-cert.pem
        echo '${acme_certificate.ai_gateway_certificate_request[0].issuer_pem}' >> ${path.module}/signed-cert.pem
        az keyvault certificate pending merge \
          --vault-name ${provider::azurerm::parse_resource_id(azurerm_key_vault.key_vault_apim_custom_domain[0].id).resource_name} \
          --name ${azurerm_key_vault_certificate.apim_gateway_certificate[0].name} \
          --file ${path.module}/signed-cert.pem
        rm ${path.module}/signed-cert.pem
        echo "Certificate merged successfully."
      else
        echo "Certificate is not in pending state (status: $CERT_STATUS), skipping merge."
      fi
    EOT
  }
}

## Create the required CNAME record in Cloudfare which is required for v2 APIM custom domain
##
resource "cloudflare_dns_record" "custom_domain_cname" {
  count = var.provision_certificate == true ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "aigw-example${var.random_string}.${var.ai_gateway_private_dns_zone_name}"
  content = "aigw${var.region_code}${var.random_string}.azure-api.net"
  ttl     = 60
  type    = "CNAME"

}

########### Create the new Private DNS Zone used for internal mode with a custom domain
########### and link it to the shared services virtual network
###########

## Create a Private DNS Zone that be the custom domain namespace for the API Management AI Gateway instance
##
resource "azurerm_private_dns_zone" "private_dns_zone_ai_gateway" {
  provider = azurerm.subscription_infrastructure

  count = var.provision_certificate == true && var.existing_zone == false ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_apim
  ]

  name                = var.ai_gateway_private_dns_zone_name
  resource_group_name = var.resource_group_dns
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Create the Private DNS Zone virtual network link to the shared services virtual network
##
resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_link_ai_gateway" {
  provider = azurerm.subscription_infrastructure

  count = var.provision_certificate == true && var.existing_zone == false ? 1 : 0

  depends_on = [
    azurerm_private_dns_zone.private_dns_zone_ai_gateway
  ]

  name                  = azurerm_private_dns_zone.private_dns_zone_ai_gateway[0].name
  private_dns_zone_id   = azurerm_private_dns_zone.private_dns_zone_ai_gateway[0].id
  virtual_network_id    = var.virtual_network_id_shared_services
  registration_enabled  = false

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########### Create the Application Insights instance the API Management service
########### will use to send telemetry data to
###########

## Create Application Insights instance
resource "azurerm_application_insights" "appins_ai_gateway" {
  depends_on = [
    time_sleep.sleep_law_creation
  ]

  name                = "appinsaigw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_apim.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  application_type    = "web"
  tags                = local.tags

  # Disable access keys and restrict to Entra ID authentication
  local_authentication_enabled = false

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########### Create the Foundry accounts, deploy the GPT 4.1 model, and create a Private Endpoint
########### for the Foundry account
###########

## Create Foundry accounts to act as the backends for the API Management AI Gateway instance
##
resource "azurerm_cognitive_account" "ms_foundry_accounts" {
  depends_on = [
    azurerm_resource_group.rg_apim,
    azurerm_log_analytics_workspace.log_analytics_workspace_workload
  ]

  for_each = local.ms_foundry_regions

  name                = "msf${each.value.region_code}${var.random_string}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = merge(local.tags, { SecurityControl = "Ignore" })

  # Create an AI Foundry Account to support Foundry Projects
  kind                       = "AIServices"
  sku_name                   = "S0"
  project_management_enabled = true

  # Set custom subdomain name for DNS names created for this Foundry resource
  custom_subdomain_name = "msf${each.value.region_code}${var.random_string}"

  # Block public network access to the Foundry account
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Deploy GPT 4.1 model to the Foundry accounts
##
resource "azurerm_cognitive_deployment" "deployment_gpt41" {
  depends_on = [
    azurerm_cognitive_account.ms_foundry_accounts
  ]

  for_each = local.ms_foundry_regions

  name                 = "gpt-4.1"
  cognitive_account_id = azurerm_cognitive_account.ms_foundry_accounts[each.key].id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-4.1"
  }

  lifecycle {
    ignore_changes = [
      model[0].version
    ]
  }
}

## Deploy GPT 4.1-mini model to the Foundry accounts
##
resource "azurerm_cognitive_deployment" "deployment_gpt41_mini" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt41
  ]

  for_each = local.ms_foundry_regions

  name                 = "gpt-4.1-mini"
  cognitive_account_id = azurerm_cognitive_account.ms_foundry_accounts[each.key].id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-4.1-mini"
  }

  lifecycle {
    ignore_changes = [
      model[0].version
    ]
  }
}

## Deploy GPT 4.1 model to the Foundry accounts
##
resource "azurerm_cognitive_deployment" "deployment_text_embedding_3_large" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_gpt41_mini
  ]

  for_each = local.ms_foundry_regions

  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.ms_foundry_accounts[each.key].id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
  }

  lifecycle {
    ignore_changes = [
      model[0].version
    ]
  }
}

## Create a deployment for OpenAI's GPT-5.1
##
resource "azurerm_cognitive_deployment" "deployment_gpt_5_1" {
  depends_on = [
    azurerm_cognitive_deployment.deployment_text_embedding_3_large
  ]

  for_each = local.ms_foundry_regions

  name                 = "gpt-5.1"
  cognitive_account_id = azurerm_cognitive_account.ms_foundry_accounts[each.key].id

  # Use the default Responsible AI policy for the deployment
  rai_policy_name = "Microsoft.DefaultV2"

  sku {
    # Using global for maximum TPM; DataZone should be used for regulated customers
    name     = "GlobalStandard"
    capacity = 1000
  }

  model {
    format  = "OpenAI"
    name    = "gpt-5.1"
  }

  lifecycle {
    ignore_changes = [
      model[0].version
    ]
  }
}

## Create a diagnostic setting for the Microsoft Foundry accounts to send logs to the Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_msfoundry_accounts" {
  depends_on = [
    azurerm_cognitive_account.ms_foundry_accounts
  ]

  for_each = local.ms_foundry_regions

  name                       = "diag-base"
  target_resource_id         = azurerm_cognitive_account.ms_foundry_accounts[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "AzureOpenAIRequestUsage"
  }

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Trace"
  }
}

## Create Private Endpoint for Microsoft Foundry account
##
resource "azurerm_private_endpoint" "pe_msfoundry_accounts" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_cognitive_account.ms_foundry_accounts,
    azurerm_cognitive_deployment.deployment_text_embedding_3_large
  ]

  for_each = local.ms_foundry_regions

  name                = "pe${azurerm_cognitive_account.ms_foundry_accounts[each.key].name}account"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_apim.name
  tags                = local.tags
  subnet_id           = var.subnet_id_private_endpoints

  custom_network_interface_name = "nic${azurerm_cognitive_account.ms_foundry_accounts[each.key].name}account"

  private_service_connection {
    name                           = "peconn${azurerm_cognitive_account.ms_foundry_accounts[each.key].name}account"
    private_connection_resource_id = azurerm_cognitive_account.ms_foundry_accounts[each.key].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azurerm_cognitive_account.ms_foundry_accounts[each.key].name}account"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

########### Create the user-assigned managed identity for the API Management AI Gateway intance
########### and any required RBAC assignments
###########

## Create the user-assigned managed identity that will be associated with the API Management AI Gateway service
##
resource "azurerm_user_assigned_identity" "umi_ai_gateway" {
  depends_on = [
    azurerm_resource_group.rg_ai_gateway,
    azurerm_application_insights.appins_ai_gateway,
    azurerm_key_vault.key_vault_ai_gateway_custom_domain,
    azurerm_cognitive_account.ms_foundry_accounts
  ]

  name                = "uamiaigw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_ai_gateway.name
  tags                = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Pause for 30 seconds to allow the user-assigned management identity to propagate through Entra ID
##
resource "time_sleep" "sleep_ai_gateway_umi_propagation" {
  depends_on = [
    azurerm_user_assigned_identity.umi_ai_gateway
  ]
  create_duration = "30s"
}

## Create Azure RBAC Role assignment granting user-assigned managed identity associated with the
## API Management AI Gateway service the Key Vault Secrets User role on the Key Vault instance that stores the
## private key and certificate used for the custom domain name of the API Management instance.
resource "azurerm_role_assignment" "umi_ai_gateway_secrets_key_vault_key_vault_secret_user" {
  depends_on = [
    time_sleep.sleep_ai_gateway_umi_propagation
  ]

  count = var.provision_certificate == true ? 1 : 0

  scope                = azurerm_key_vault.key_vault_ai_gateway_custom_domain[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.umi_ai_gateway.principal_id
}

## Create Azure RBAC Role assignment granting the user-assigned managed identity associated with the
## API Management AI Gateway service the Monitoring Metrics Publisher role on the Application Insights instance
resource "azurerm_role_assignment" "umi_ai_gateway_appinsights_metrics_publisher" {
  depends_on = [
    time_sleep.sleep_ai_gateway_umi_propagation
  ]

  scope                = azurerm_application_insights.appins_api_management.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.umi_ai_gateway.principal_id
}

## Create Azure RBAC Role assignment granting the user-assigned managed identity associated with the
## API Management AI Gateway service the Foundry User role on the MS Foundry accounts
## hosting LLMs
resource "azurerm_role_assignment" "umi_ai_gateway_foundry_account_foundry_user" {
  depends_on = [
    time_sleep.sleep_ai_gateway_umi_propagation
  ]
  
  for_each = local.ms_foundry_regions

  scope                = azurerm_cognitive_account.ms_foundry_accounts[each.key].id
  role_definition_name = "Foundry User"
  principal_id         = azurerm_user_assigned_identity.umi_ai_gateway.principal_id
}

## Sleep for 120 seconds to allow the Azure RBAC role assignments to propagate
##
resource "time_sleep" "sleep_ai_gateway_umi_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_ai_gateway_secrets_key_vault_key_vault_secret_user,
    azurerm_role_assignment.umi_ai_gateway_appinsights_metrics_publisher,
    azurerm_role_assignment.umi_ai_gateway_foundry_account_foundry_user,
  ]
  create_duration = "120s"
}

########### Create the API Management AI Gateway instance and its dependent resources
###########
###########

resource "azapi_resource" "ai_gateway" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace_workload,
    azurerm_application_insights.appins_api_management,
    time_sleep.sleep_apim_umi_role_assignments,
    # Used for custom domain
    null_resource.merge_certificate,
    cloudflare_dns_record.custom_domain_cname
  ]

  type                      = "Microsoft.ApiManagement/service@2025-09-01-preview"
  name                      = "aigw${var.region_code}${var.random_string}"
  location                  = var.region
  parent_id                 = azurerm_resource_group.rg_ai_gateway.id
  schema_validation_enabled = false

  body = {
    sku = {
      name = "AIGateway"
      capacity = 1
    }
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.umi_ai_gateway[0].id) = {}
      }
    }
    properties = {
      # TODO: 9/2026 Remove this is requirement for public network access to be enabled until Private Endpoint is created is removed
      publicNetworkAccess = "Enabled"
      publisherEmail = var.publisher_email
      publisherName  = var.publisher_name

      # Configure the AI Gateway to support a Private Endpoint and VNet integration if var.networking_model is set to vnet_integrated
      virtualNetworkType = var.networking_model == "vnet_integrated" ? "External" : null
      virtualNetworkConfiguration = var.networking_model == "vnet_integrated" ? {
        subnetResourceId = ai_gateway_integration_subnet_id
      } : null

    }
    tags = merge(local.tags, { SecurityControl = "Ignore" })
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"],
      # This will prevent Terraform from shifting this back to true when re-applying
      public_network_access_enabled
    ]
  }
}

## Create a diagnostic setting for the API Management AI Gateway instance to send logs to the Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_ai_gateway" {
  depends_on = [
    azapi_resource.ai_gateway
  ]

  name                           = "diag-base"
  target_resource_id             = azapi_resource.ai_gateway.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace_workload.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_log {
    category = "WebSocketConnectionLogs"
  }

  enabled_log {
    category = "DeveloperPortalAuditLogs"
  }

  enabled_log {
    category = "GatewayLlmLogs"
  }

  enabled_log {
    category = "GatewayMCPLogs"
  }
}

# Unsure of what this resource does at this time
resource "azapi_resource" "connector_namespace_ai_gateway" {
  depends_on = [
    azapi_resource.ai_gateway
  ]

  type                      = "Microsoft.Web/connectorGateways@2026-05-01-preview"
  name                      = "aigw${var.region_code}${var.random_string}"
  location                  = var.region
  schema_validation_enabled = false

  body = {
    properties = {}
  }
}

## Create a custom domain names for the API Management AI Gateway instance
## This resource creation takes about 20 minutes
resource "azurerm_api_management_custom_domain" "ai_gateway_custom_domains" {
  depends_on = [
    azapi_resource.ai_gateway
  ]

  count = var.provision_certificate == true ? 1 : 0

  api_management_id = azapi_resource.ai_gateway.id

  gateway {
    host_name                = "aigw-example${var.random_string}.${var.ai_gateway_private_dns_zone_name}"
    key_vault_certificate_id = data.azurerm_key_vault_certificate.apim_gateway_certificate_completed[0].versionless_secret_id
    default_ssl_binding      = true
  }
}

## Create a Private Endpoint for the API Management AI Gateway instance if using VNet integration networking model
##
resource "azurerm_private_endpoint" "pe_ai_gateway_vnet_integrated" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azapi_resource.ai_gateway,
    azurerm_api_management_custom_domain.ai_gateway_custom_domains
  ]

  count = var.networking_model == "vnet_integrated" ? 1 : 0

  name                = "pe${azapi_resource.ai_gateway.name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_apim.name
  tags                = local.tags
  subnet_id           = var.ai_gateway_integration_subnet_id

  custom_network_interface_name = "nic${azapi_resource.ai_gateway.name}"

  private_service_connection {
    name                           = "peconn${azapi_resource.ai_gateway.name}"
    private_connection_resource_id = azapi_resource.ai_gateway.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "zoneconn${azapi_resource.ai_gateway.name}"
    private_dns_zone_ids = [
      "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_by"]
    ]
  }
}

## Patch the Azure API Management AI Gateway instance to disable public network access
##
resource "azapi_update_resource" "ai_gateway_disable_public_network_access" {
  depends_on = [
    azurerm_private_endpoint.pe_ai_gateway_vnet_integrated
  ]

  count = var.networking_model == "vnet_integrated" ? 1 : 0

  type        = "Microsoft.ApiManagement/service@2025-09-01-preview"
  resource_id = azapi_resource.ai_gateway.id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}

## Create A record for the API Management AI Gateway custom domain in the Private DNS Zone
##
resource "azurerm_private_dns_a_record" "dns_a_record_ai_gateway" {
  provider = azurerm.subscription_infrastructure

  depends_on = [
    azurerm_ai_gateway_management_custom_domain.ai_gateway_custom_domains,
    azurerm_private_dns_zone_virtual_network_link.dns_vnet_link_ai_gateway
  ]

  count = var.provision_certificate == true ? 1 : 0

  name                = "aigw-example${var.random_string}"
  private_dns_zone_id = var.existing_zone == false ? azurerm_private_dns_zone.private_dns_zone_apim[0].id : "/subscriptions/${var.subscription_id_infrastructure}/resourceGroups/${var.resource_group_dns}/providers/Microsoft.Network/privateDnsZones/${var.ai_gateway_private_dns_zone_name}"
  ttl                 = 10

  records = [
     azurerm_private_endpoint.pe_ai_gateway_vnet_integrated[0].private_service_connection[0].private_ip_address
  ]
}