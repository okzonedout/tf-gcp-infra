variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region for the resources"
  type        = string
}

variable "vpcs" {
  description = "A map of VPC configurations"
  type = map(object({
    name                            = string
    auto_create_subnetworks         = bool
    routing_mode                    = string
    delete_default_routes_on_create = bool
  }))
}

variable "subnets" {
  description = "A map of subnets for the resources"
  type = map(object({
    subnet_name   = string
    ip_cidr_range = string
    region        = string
    network       = string
  }))
}
