variable "name" {
  description = "Short name used in Azure resource names."
  type        = string
  default     = "webserver"
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into."
  type        = string
  default     = "rg-webserver"
}

variable "running" {
  description = "true starts the service, false stops it."
  type        = bool
}

variable "image" {
  description = "Full image reference. Required when running = true."
  type        = string
  default     = ""
}

variable "min_replicas" {
  description = "0 scales to zero when idle (cheapest, short cold start). 1 keeps it warm."
  type        = number
  default     = 0
}
