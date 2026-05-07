locals {
  ##### Create other local values
  compute_instance_name   = "vmci${var.region_code}${var.random_string}"
  compute_cluster_name    = "vmccb${var.region_code}${var.random_string}"
}