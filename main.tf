provider "google" {
  project = var.project_id
  region  = var.region
}

# Create VPCs based on the "vpcs" map in variables
resource "google_compute_network" "vpc_network" {
  for_each                        = var.vpcs
  name                            = each.value.name
  auto_create_subnetworks         = each.value.auto_create_subnetworks
  routing_mode                    = each.value.routing_mode
  delete_default_routes_on_create = each.value.delete_default_routes_on_create
}

# Create subnets for each of th VPC created
# Creating two subnets "webapp" "db"
resource "google_compute_subnetwork" "subnets" {
  for_each                 = var.subnets
  name                     = each.value.subnet_name
  ip_cidr_range            = each.value.ip_cidr_range
  region                   = each.value.region
  network                  = google_compute_network.vpc_network[each.value.network].self_link
  private_ip_google_access = each.value.subnet_name == "db-1" ? true : false
}

# Allocates an internal IP range for VPC peering within the specified VPC network.
resource "google_compute_global_address" "private_ip_address" {
  name          = var.private_ip_address.name
  purpose       = var.private_ip_address.purpose
  address_type  = var.private_ip_address.address_type
  prefix_length = var.private_ip_address.prefix_length
  network       = google_compute_network.vpc_network["vpc1"].id
}

resource "google_service_networking_connection" "private_service_connection" {
  network                 = google_compute_network.vpc_network["vpc1"].name
  service                 = var.private_service_connection
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}
# Firewall rule to allow TCP request on port 8080
resource "google_compute_firewall" "allow_http" {
  name     = var.firewall_rule_name
  network  = google_compute_network.vpc_network["vpc1"].self_link
  priority = 999

  allow {
    protocol = var.allowed_protocol
    ports    = var.allowed_ports
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.tags_for_instances
}

# Create default internet gatewway for a VPC
resource "google_compute_route" "csye6225-vpc-1" {
  name             = "csye6225-vpc-1-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network["vpc1"].self_link
  next_hop_gateway = "default-internet-gateway"
}

# Data block for picking up the latest custom image from the mentioned family 
data "google_compute_image" "my_image" {
  family  = var.custom_images.family
  project = var.custom_images.project
}

# Create instance based on the latest custom image
resource "google_compute_instance" "instance-1" {
  machine_type              = var.webapp_instance.machine_type
  name                      = var.webapp_instance.name
  zone                      = var.webapp_instance.zone
  allow_stopping_for_update = var.webapp_instance.allow_stopping_for_update
  tags                      = var.tags_for_instances
  # Set 100GB of storage disk for the instance
  boot_disk {
    auto_delete = var.webapp_instance.boot_disk_auto_delete
    device_name = var.webapp_instance.boot_disk_device_name

    # Parametes for disk storage
    initialize_params {
      # image = "projects/csye6225-omkar/global/images/centos-csye6225-1708497196"
      image = data.google_compute_image.my_image.self_link
      size  = var.webapp_instance.boot_disk_size
      type  = var.webapp_instance.boot_disk_type
    }

    # Sets mode of the disk
    mode = var.webapp_instance.mode
  }

  service_account {
    email = google_service_account.service_account.email
    scopes = var.service_account_roles
  }

  # Specifies the network attached to the instance 
  network_interface {
    # Access configurations, i.e. IPs via which this instance can be accessed via the Internet.
    access_config {}
    network    = google_compute_network.vpc_network["vpc1"].self_link
    subnetwork = google_compute_subnetwork.subnets["webapp-1"].self_link
  }
  metadata = {
    startup-script = <<-EOF
    #! /bin/bash

    # sudo touch /opt/application.properties

    sudo tee /opt/application.properties <<'EOT'
    spring.datasource.driver-class-name=org.postgresql.Driver
    spring.datasource.url=jdbc:postgresql://${google_sql_database_instance.postgres_instance.private_ip_address}:5432/${google_sql_database.webappdb.name}
    spring.datasource.username=${google_sql_user.users.name}
    spring.datasource.password=${random_password.sql_random_password.result}
    spring.jpa.hibernate.ddl-auto=update
    spring.jooq.sql-dialect=postgres
    spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
    server.port=8080
    spring.jackson.deserialization.fail-on-unknown-properties=true
    spring.sql.init.continue-on-error=true
    # Additional properties can be added here
    EOT

    # Restart or start your Spring Boot application as needed
    # systemctl restart webapp.service
    EOF
  }

}

resource "google_service_account" "service_account" {
  account_id   = var.service_account.account_id
  display_name = var.service_account.display_name
}

resource "google_project_iam_binding" "service_account_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members  = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_project_iam_binding" "service_account_log_admin" {
  project = var.project_id
  role    = "roles/logging.admin"
  members  = ["serviceAccount:${google_service_account.service_account.email}"]
}

# Create a CloudSQL for PostgreSQL Instance
resource "google_sql_database_instance" "postgres_instance" {
  name                = var.postgres_instance.name
  region              = var.region
  database_version    = var.postgres_instance.database_version
  root_password       = var.postgres_instance.root_password
  deletion_protection = var.postgres_instance.deletion_protection
  depends_on          = [google_service_networking_connection.private_service_connection]
  settings {
    tier              = var.postgres_instance.tier
    availability_type = var.postgres_instance.availability_type
    disk_type         = var.postgres_instance.disk_type
    disk_size         = var.postgres_instance.disk_size
    ip_configuration {
      ipv4_enabled    = var.postgres_instance.ipv4_enabled
      private_network = google_compute_network.vpc_network["vpc1"].self_link
    }
  }
}

resource "google_sql_database" "webappdb" {
  name     = var.webappdb.name
  instance = google_sql_database_instance.postgres_instance.name
}

resource "random_password" "sql_random_password" {
  length           = 16
  special          = false
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

output "generated_password" {
  value     = random_password.sql_random_password.result
  sensitive = true
}

resource "google_sql_user" "users" {
  name     = var.webappdb.username
  instance = google_sql_database_instance.postgres_instance.name
  password = random_password.sql_random_password.result
}

resource "google_dns_record_set" "webapp_dns_record_set" {
  name = data.google_dns_managed_zone.webapp-zone.dns_name
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.webapp-zone.name

  rrdatas = [google_compute_instance.instance-1.network_interface[0].access_config[0].nat_ip]
}

data "google_dns_managed_zone" "webapp-zone" {
  name = var.public_zone_name
}