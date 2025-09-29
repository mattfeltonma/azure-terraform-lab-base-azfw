variable "environments" {
  description = "A list of environments to deploy the resources to. The first environment in the list will be used as the primary environment."
  type = map(object({
    region_name = string
    region_code = string
    region_resource_group_name = string
  }))
}

variable "purpose" {
  description = "Three character code to identify the purpose of the resource"
  type = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type = string
}

variable "retention_in_days" {
  description = "The retention in days for the log analytics workspace"
  type = number
  default = 30
}

variable "tags" {
  description = "The tags to apply to the resource"
  type = map(string)
}