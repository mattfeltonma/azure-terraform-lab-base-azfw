locals {
  parsed_transit_vnet_id = provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks",var.vnet_id_transit)
  vnet_name_transit = local.parsed_transit_vnet_id["name"]
}
