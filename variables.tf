variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region for the resources"
  type        = string
}

variable "db_subnet_name" {
  description = "The region for the resources"
  type        = string
}

variable "private_ip_address" {
  description = "Private IP address for the Google Compute Global Address"
  type = object({
    name          = string
    purpose       = string
    address_type  = string
    prefix_length = number
  })
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
variable "private_service_connection" {
  description = "Google Service Networking Service Connection"
  type        = string
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

variable "custom_images" {
  description = "Custom images details"
  type = object({
    family  = string
    project = string
  })
}

variable "tags_for_instances" {
  description = "Tags for instances"
  type        = tuple([string])
}

variable "allowed_ports" {
  description = "Allowed ports for instance"
  type        = list(string)
}

variable "allowed_protocol" {
  description = "Porotocols for firewall to allow"
  type        = string
}

variable "firewall_rule_name" {
  description = "Firewall name"
  type        = string
}

variable "webapp_instance" {
  description = "Holds VM instance information"
  type = object({
    machine_type              = string
    name                      = string
    zone                      = string
    allow_stopping_for_update = bool
    boot_disk_device_name     = string
    boot_disk_auto_delete     = bool
    boot_disk_size            = number
    boot_disk_type            = string
    mode                      = string
  })
}

variable "postgres_instance" {
  description = "Holds CloudSQL instance information for postgres"
  type = object({
    name                = string
    database_version    = string
    root_password       = string
    deletion_protection = bool
    tier                = string
    availability_type   = string
    disk_type           = string
    disk_size           = number
    ipv4_enabled        = bool
  })
}

variable "webappdb" {
  description = "PostgreSQL database information"
  type = object({
    name     = string
    username = string
  })
}

variable "service_account_roles" {
  description = "Service account roles for logging and monitoring"
  type = list(string)
}

variable "service_account" {
  description = "Service account information"
  type = object({
    account_id = string
    display_name = string
  })
}

variable "public_zone_name" {
  description = "Public zone name"
  type = string
}