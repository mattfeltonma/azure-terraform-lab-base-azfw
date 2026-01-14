variable "address_space_onpremises" {
  description = "The address space on-premises"
  type        = string
}

variable "address_space_cloud" {
  description = "The address space in the cloud"
  type        = string
}

variable "environment_details" {
  description = "The environment details including environment name, region name and address space. This should include primary and secondary if multi-region is required"
  type = map(object({
    region_name = string
    address_space = string
  }))
}

variable "key_vault_admin" {
  description = "The object id of the user or service principal to assign the Key Vault Administrator role to"
  type        = string

}

variable "network_watcher_name_prefix" {
  description = "The prefix name of the network watcher resource"
  type        = string
  default     = "NetworkWatcher_"
}

variable "network_watcher_resource_group_name" {
  description = "The name of the network watcher resource group"
  type        = string
  default     = "NetworkWatcherRG"
}

variable "private_dns_namespaces" {
  description = "The private DNS zones to create and link to the shared services virtual network"
  type        = map(string)
  default = {
    acr = "privatelink.azurecr.io",
    ai_search = "privatelink.search.windows.net"
    aml_api = "privatelink.api.azureml.ms"
    aml_instances = "instances.azureml.ms"
    aml_notebooks = "privatelink.notebooks.azure.net"
    apim = "privatelink.azure-api.net"
    azure_sql = "privatelink.database.windows.net"
    azure_postgres = "privatelink.postgres.database.azure.com"
    azure_mysql = "privatelink.mysql.database.azure.com"
    azure_mariadb = "privatelink.mariadb.database.azure.com"
    cosmos_sql = "privatelink.documents.azure.com"
    cosmos_sqlx = "privatelink.sqlx.cosmos.azure.com"
    cosmos_cassandra = "privatelink.cassandra.cosmos.azure.com"
    cosmos_gremlin = "privatelink.gremlin.cosmos.azure.com"
    cosmos_mongo = "privatelink.mongo.cosmos.azure.com"
    cosmos_table = "privatelink.table.cosmos.azure.com"
    cosmos_analytics = "privatelink.analytics.cosmos.azure.com"
    cosmos_postgres = "privatelink.postgres.cosmos.azure.com"
    event_grid = "privatelink.eventgrid.azure.net"
    foundry_ai = "privatelink.services.ai.azure.com"
    foundry_cognitive = "privatelink.cognitiveservices.azure.com"
    foundry_openai = "privatelink.openai.azure.com"
    key_vault = "privatelink.vaultcore.azure.net"
    service_bus = "privatelink.servicebus.windows.net"
    storage_blob = "privatelink.blob.core.windows.net"
    storage_dfs = "privatelink.dfs.core.windows.net"
    storage_file = "privatelink.file.core.windows.net"
    storage_queue = "privatelink.queue.core.windows.net"
    storage_table = "privatelink.table.core.windows.net"
    synapse_main = "privatelink.azuresynapse.net"
    synapse_dev = "privatelink.dev.azuresynapse.net"
    synapse_sql = "privatelink.sql.azuresynapse.net"
    web_app ="privatelink.azurewebsites.net"
  }
}

variable "vm_sku_size" {
  description = "The SKU size to use for any virtual machines created by the lab"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vm_admin_username" {
  description = "The username to assign to the virtual machine"
  type        = string
}

variable "vm_admin_password" {
  description = "The password to assign to the virtual machine"
  type        = string
  sensitive   = true
}

variable "trusted_ip" {
  description = "This is the trusted IP address that will be allowed through service firewalls for Key Vault"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resources"
  type        = map(string)
}
