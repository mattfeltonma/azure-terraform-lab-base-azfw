variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "subnet_id_web" {
  description = "The subnet id to deploy the virtual machines acting as web servers"
  type        = string
}

variable "subnet_cidr_web" {
  description = "The CIDR block assigned to the subnet where the virtual machines acting as web servers are deployed"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "trusted_ip" {
  description = "The trusted IP address or CIDR block to allow access to the Front Door"
  type        = string
}

variable "vm_admin_password" {
  description = "The admin password to use for the virtual machines acting as web servers"
  type        = string
  sensitive   = true
}

variable "vm_admin_username" {
  description = "The admin username to use for the virtual machines acting as web servers"
  type        = string
}

variable "vm_size" {
  description = "The size of the virtual machines acting as web servers"
  type        = string
  default     = "Standard_DS2_v2"
}
