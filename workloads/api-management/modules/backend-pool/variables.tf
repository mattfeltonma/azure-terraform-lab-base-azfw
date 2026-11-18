variable "apim_id" {
  description = "The resource id of the API Management instance"
  type        = string
}

variable "backends" {
  description = "The list of backends"
  type = list(object({
    id       = string
    priority = number
  }))
}

variable "session_affinity" {
  description = "Set to true to use session affinity for the backend pool based on a session cookie"
  type        = bool
  default     = false
}

variable "pool_name" {
  description = "The name of the backend"
  type        = string
}
