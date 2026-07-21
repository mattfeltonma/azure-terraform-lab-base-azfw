locals {
  # Convert the region name to a unique abbreviation
   region_abbreviations = {
    "australiacentral"   = "acl",
    "australiacentral2"  = "acl2",
    "australiaeast"      = "ae",
    "australiasoutheast" = "ase",
    "brazilsouth"        = "brs",
    "brazilsoutheast"    = "bse",
    "canadacentral"      = "cnc",
    "canadaeast"         = "cne",
    "centralindia"       = "ci",
    "centralus"          = "cus",
    "centraluseuap"      = "ccy",
    "eastasia"           = "ea",
    "eastus"             = "eus",
    "eastus2"            = "eus2",
    "eastus2euap"        = "ecy",
    "francecentral"      = "frc",
    "francesouth"        = "frs",
    "germanynorth"       = "gn",
    "germanywestcentral" = "gwc",
    "israelcentral"      = "ilc",
    "italynorth"         = "itn",
    "japaneast"          = "jpe",
    "japanwest"          = "jpw",
    "jioindiacentral"    = "jic",
    "jioindiawest"       = "jiw",
    "koreacentral"       = "krc",
    "koreasouth"         = "krs",
    "mexicocentral"      = "mxc",
    "newzealandnorth"    = "nzn",
    "northcentralus"     = "ncus",
    "northeurope"        = "ne",
    "norwayeast"         = "nwe",
    "norwaywest"         = "nww",
    "polandcentral"      = "plc",
    "qatarcentral"       = "qac",
    "southafricanorth"   = "san",
    "southafricawest"    = "saw",
    "southcentralus"     = "scus",
    "southeastasia"      = "sea",
    "southindia"         = "si",
    "spaincentral"       = "spac"
    "swedencentral"      = "swc",
    "switzerlandnorth"   = "swn",
    "switzerlandwest"    = "sww",
    "uaecentral"         = "uaec",
    "uaenorth"           = "uaen",
    "uksouth"            = "uks",
    "ukwest"             = "ukw",
    "westcentralus"      = "wcus",
    "westeurope"         = "we",
    "westindia"          = "wi",
    "westus"             = "wus",
    "westus2"            = "wus2",
    "westus3"            = "wus3"
  }

  # Define this variable to hold the region names when multiple environments are created
  regions = [for env in values(var.environment_details) : env.region_name]

  # Create the virtual network cidr ranges
  vnet_cidr_tr_pri = cidrsubnet(var.environment_details["primary"].address_space, 3, 0)
  vnet_cidr_ss_pri = cidrsubnet(var.environment_details["primary"].address_space, 3, 1)
  vnet_cidr_wl1_pri = cidrsubnet(var.environment_details["primary"].address_space, 3, 2)
  vnet_cidr_wl2_pri = cidrsubnet(var.environment_details["primary"].address_space, 3, 3)
  vnet_cidr_wl3_hero = cidrsubnet(var.environment_details["primary"].address_space, 3, 4)
  primary_region_vnet_cidrs = {
    "ss" = local.vnet_cidr_ss_pri,
    "wl1" = local.vnet_cidr_wl1_pri,
    "wl2" = local.vnet_cidr_wl2_pri,
    "wl3" = local.vnet_cidr_wl3_hero
  }

  # Create the secondary virtual network CIDR ranges if the environment has multiple environments defined
  vnet_cidr_tr_sec = contains(keys(var.environment_details), "secondary") ? cidrsubnet(var.environment_details["secondary"].address_space, 3, 0) : null
  vnet_cidr_ss_sec = contains(keys(var.environment_details), "secondary") ? cidrsubnet(var.environment_details["secondary"].address_space, 3, 1) : null
  vnet_cidr_wl1_sec = contains(keys(var.environment_details), "secondary") ? cidrsubnet(var.environment_details["secondary"].address_space, 3, 2) : null
  vnet_cidr_wl2_sec = contains(keys(var.environment_details), "secondary") ? cidrsubnet(var.environment_details["secondary"].address_space, 3, 3) : null
  secondary_region_vnet_cidrs = contains(keys(var.environment_details), "secondary") ? {
    "ss" = local.vnet_cidr_ss_sec,
    "wl1" = local.vnet_cidr_wl1_sec,
    "wl2" = local.vnet_cidr_wl2_sec
  } : {}

  ##### Combine these default zones, regional Private DNS Zones and user-specified zones and filter out secondary environment
  ##### when it isn't present

  default_private_dns_namespaces = {
    acr               = "privatelink.azurecr.io"
    ai_search         = "privatelink.search.windows.net"
    aml_api           = "privatelink.api.azureml.ms"
    aml_notebooks     = "privatelink.notebooks.azure.net"
    apim_private      = "privatelink.azure-api.net"
    azure_sql         = "privatelink.database.windows.net"
    azure_postgres    = "privatelink.postgres.database.azure.com"
    cosmos_sql        = "privatelink.documents.azure.com"
    cosmos_mongo      = "privatelink.mongo.cosmos.azure.com"
    cosmos_table      = "privatelink.table.cosmos.azure.com"
    event_grid        = "privatelink.eventgrid.azure.net"
    foundry_ai        = "privatelink.services.ai.azure.com"
    foundry_cognitive = "privatelink.cognitiveservices.azure.com"
    foundry_openai    = "privatelink.openai.azure.com"
    key_vault         = "privatelink.vaultcore.azure.net"
    service_bus       = "privatelink.servicebus.windows.net"
    storage_blob      = "privatelink.blob.core.windows.net"
    storage_dfs       = "privatelink.dfs.core.windows.net"
    storage_file      = "privatelink.file.core.windows.net"
    storage_queue     = "privatelink.queue.core.windows.net"
    storage_table     = "privatelink.table.core.windows.net"
    web_app           = "privatelink.azurewebsites.net"
  }

  # Construct regional Private DNS Zones
  aks_private_dns_namespace_primary   = "privatelink.${var.environment_details["primary"].region_name}.azmk8s.io"
  aks_private_dns_namespace_secondary = contains(keys(var.environment_details), "secondary") ? "privatelink.${var.environment_details["secondary"].region_name}.azmk8s.io" : null

  acr_private_dns_namespace_primary   = "${var.environment_details["primary"].region_name}.data.privatelink.azurecr.io"
  acr_private_dns_namespace_secondary = contains(keys(var.environment_details), "secondary") ? "${var.environment_details["secondary"].region_name}.data.privatelink.azurecr.io" : null

  container_apps_namespace_primary = "privatelink.${var.environment_details["primary"].region_name}.azurecontainerapps.io"
  container_apps_namespace_secondary = contains(keys(var.environment_details), "secondary") ? "privatelink.${var.environment_details["secondary"].region_name}.azurecontainerapps.io" : null

  # Add regional zones to a map
  regional_private_dns_namespaces_map = {
    aks_primary   = local.aks_private_dns_namespace_primary,
    aks_secondary = contains(keys(var.environment_details), "secondary") ? local.aks_private_dns_namespace_secondary : null,
    acr_primary   = local.acr_private_dns_namespace_primary,
    acr_secondary = contains(keys(var.environment_details), "secondary") ? local.acr_private_dns_namespace_secondary : null,
    ca_primary    = local.container_apps_namespace_primary,
    ca_secondary  = contains(keys(var.environment_details), "secondary") ? local.container_apps_namespace_secondary : null,
  }

  # Merge the user-specified zones with the regional zones
  private_dns_namespaces_with_regional_zones = merge(
    local.default_private_dns_namespaces,
    local.regional_private_dns_namespaces_map,
    var.private_dns_namespaces
  )

  # Filter out null values when secondary environment isn't present
  filtered_private_dns_namespaces_with_regional_zones = {
    for environments, values in local.private_dns_namespaces_with_regional_zones : environments => values if values != null
  }

  # Create a map of environment names to the private DNS zones required for that environment with a key of <environment>:<service>
  private_dns_namespaces_env_map = merge([
    for env_name in keys(var.environment_details) : {
      for service, namespace in local.filtered_private_dns_namespaces_with_regional_zones :
        "${env_name}:${service}" => {
          environment = env_name
          service = service
          namespace = namespace
        }
    }
  # Splat the map to create a single map with all environments
  ]...)

  ##### Create an object that will create two instances of each environment in order to create multiple workloads
  #####
  workload_object = [
    for env_pair in setproduct(keys(var.environment_details),
    [1,2]) :{ 
      environment = env_pair[0]
      workload_number = env_pair[1]
    }
  ]

  ##### Combine required and user-specified tags
  # Add required tags and merge them with the provided tags
  required_tags = {
    created_date = time_static.created.rfc3339
    created_by   = data.azurerm_client_config.identity_config.object_id
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}
