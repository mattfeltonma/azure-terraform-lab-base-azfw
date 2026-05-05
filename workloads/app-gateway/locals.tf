locals {
    app_gateway_subnet_parsed = provider::azurerm::parse_resource_id(var.subnet_id_app_gateway)
    app_gateway_virtual_network_id = "/subscriptions/${local.app_gateway_subnet_parsed["subscription_id"]}/resourceGroups/${local.app_gateway_subnet_parsed["resource_group_name"]}/providers/Microsoft.Network/virtualNetworks/${local.app_gateway_subnet_parsed["parent_resources"]["virtualNetworks"]}"

    backend_pool_web_default = "bepoolwebdef"
    backend_pool_tcp_proxy_default = "bepooltcpdef"
    backend_http_settings_http_default = "behttpsethttpdef"
    backend_http_settings_https_default = "behttpsethttpsdef"
    backend_tcp_settings_tcp_proxy_default = "betcpsettcpdef"
    backend_tls_settings_tls_proxy_default = "betlssettlsdef"

    frontend_ip_configuration_public_name = "feipcfgpubdef"
    frontend_ip_configuration_private_name = "feipcfgprivdef"
    frontend_port_http_name = "feporthttpdef"
    frontend_port_https_name = "feporthttpsdef"
    frontend_port_tcp_proxy_name_private = "feporttcpprivdef"
    frontend_port_tls_proxy_name_private = "feporttlsprivdef"
    frontend_port_tcp_proxy_name_public = "feporttcppubdef"
    frontend_port_tls_proxy_name_public = "feporttlspubdef"

    gateway_ip_configuration_name = "gipcfgdef"

    listener_http_name_public = "listhttppubdef"
    listener_https_name_public = "listhttpspubdef"
    listener_http_name_private = "listhttpprivdef"
    listener_https_name_private = "listhttpsprivdef"
    listener_tcp_proxy_name_public = "listcppropubdef"
    listener_tls_proxy_name_public = "listtlspropubdef"
    listener_tcp_proxy_name_private = "listcpproprivdef"
    listener_tls_proxy_name_private = "listtlsproprivdef"

    probe_tcp_name = "probetcpdef"
    probe_tls_name = "probetlsdef"
    probe_http_name = "probehttpdef"
    probe_https_name = "probehttpsdef"

    routing_rule_http_name = "rulhttpprodef"
    routing_rule_https_name = "rulhttpsprodef"
    routing_rule_tcp_proxy_name = "rultcpprodef"
    routing_rule_tls_proxy_name = "rultlsprodef"

    ssl_certificate_name = "sslcertdef"

}