variable "apim_management_name" {
  description = "The name of the API Management instance"
  type        = string
}

variable "apim_resource_group_name" {
  description = "The name of the resource group containing the API Management instance"
  type        = string
}

variable "backend_name" {
  description = "The name of the backend"
  type        = string
}

variable "url" {
  description = "The url of the backend"
  type        = string
}