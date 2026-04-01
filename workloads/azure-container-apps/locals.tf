locals {
    load_balancer_fe_config_web_name = "lbfecfgweb"
    vm_count = 2

    # FrontDoor variables
    fd_be_pool_load_balancer_name = "fdlbpoolweb"
    fd_be_pool_health_probe_name = "fdlbprobeweb"
    fd_be_pool_name = "fdbepoolweb"
    fd_fe_name = "fdfeweb"
}