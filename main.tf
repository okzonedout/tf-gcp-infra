provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.public_zone_name
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
  project       = var.project_id
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

# Create instance group manager - MIG
resource "google_compute_region_instance_group_manager" "webapp_instance_group_manager" {
  name                      = "webapp-instance-group-manager"
  base_instance_name        = "webapp"
  region                    = var.region
  distribution_policy_zones = ["us-east1-b", "us-east1-c", "us-east1-d"]
  # target_pools = []
  target_size = 1
  version {
    instance_template = google_compute_region_instance_template.webapp_instance_template.self_link
    name              = "primary"
  }
  named_port {
    name = "http"
    port = 8080
  }
  auto_healing_policies {
    health_check      = google_compute_region_health_check.autohealing.id
    initial_delay_sec = 60
  }

}

resource "google_compute_region_health_check" "autohealing" {
  name                = "autohealing-health-check"
  check_interval_sec  = 60
  timeout_sec         = 60
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  http_health_check {
    request_path = "/healthz"
    port         = "8080"
  }
}

resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name       = "webapp-autoscaler"
  region     = var.region
  target     = google_compute_region_instance_group_manager.webapp_instance_group_manager.id
  depends_on = [google_compute_region_instance_group_manager.webapp_instance_group_manager]
  autoscaling_policy {
    mode            = "ON"
    max_replicas    = 9
    min_replicas    = 1
    cooldown_period = 60
    # load_balancing_utilization {
    #   target = 0.5
    # }
    cpu_utilization {
      target = 0.5
    }
  }
}

# Create instance template
resource "google_compute_region_instance_template" "webapp_instance_template" {
  name_prefix  = "webapp-template"
  tags         = var.tags_for_instances
  labels       = { env = "production" }
  region       = var.region
  machine_type = var.webapp_instance.machine_type
  lifecycle {
    create_before_destroy = true
  }

  disk {
    # source_image = google_compute_disk.webapp_disk.source_image_id
    source_image = data.google_compute_image.my_image.family
    auto_delete  = false
    boot         = false
    disk_size_gb = 100
  }

  network_interface {
    network    = google_compute_network.vpc_network["vpc1"].self_link
    subnetwork = google_compute_subnetwork.subnets["webapp-1"].self_link
  }
  service_account {
    email = google_service_account.service_account.email
    # scopes = var.service_account_roles
    scopes = ["cloud-platform"]
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

resource "google_compute_disk" "webapp_disk" {
  name  = "webapp-disk"
  image = data.google_compute_image.my_image.self_link
  type  = var.webapp_instance.boot_disk_type
  size  = var.webapp_instance.boot_disk_size
  zone  = var.webapp_instance.zone
}

# Create instance based on the latest custom image
# resource "google_compute_instance" "instance-1" {
#   machine_type              = var.webapp_instance.machine_type
#   name                      = var.webapp_instance.name
#   zone                      = var.webapp_instance.zone
#   allow_stopping_for_update = var.webapp_instance.allow_stopping_for_update
#   tags                      = var.tags_for_instances
#   # Set 100GB of storage disk for the instance
#   boot_disk {
#     auto_delete = var.webapp_instance.boot_disk_auto_delete
#     device_name = var.webapp_instance.boot_disk_device_name

#     # Parametes for disk storage
#     initialize_params {
#       # image = "projects/csye6225-omkar/global/images/centos-csye6225-1708497196"
#       image = data.google_compute_image.my_image.self_link
#       size  = var.webapp_instance.boot_disk_size
#       type  = var.webapp_instance.boot_disk_type
#     }

#     # Sets mode of the disk
#     mode = var.webapp_instance.mode
#   }

#   service_account {
#     email = google_service_account.service_account.email
#     # scopes = var.service_account_roles
#     scopes = ["cloud-platform"]
#   }

#   # Specifies the network attached to the instance 
#   network_interface {
#     # Access configurations, i.e. IPs via which this instance can be accessed via the Internet.
#     access_config {}
#     network    = google_compute_network.vpc_network["vpc1"].self_link
#     subnetwork = google_compute_subnetwork.subnets["webapp-1"].self_link
#   }
#   metadata = {
#     startup-script = <<-EOF
#     #! /bin/bash

#     # sudo touch /opt/application.properties

#     sudo tee /opt/application.properties <<'EOT'
#     spring.datasource.driver-class-name=org.postgresql.Driver
#     spring.datasource.url=jdbc:postgresql://${google_sql_database_instance.postgres_instance.private_ip_address}:5432/${google_sql_database.webappdb.name}
#     spring.datasource.username=${google_sql_user.users.name}
#     spring.datasource.password=${random_password.sql_random_password.result}
#     spring.jpa.hibernate.ddl-auto=update
#     spring.jooq.sql-dialect=postgres
#     spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
#     server.port=8080
#     spring.jackson.deserialization.fail-on-unknown-properties=true
#     spring.sql.init.continue-on-error=true
#     # Additional properties can be added here
#     EOT

#     # Restart or start your Spring Boot application as needed
#     # systemctl restart webapp.service
#     EOF
#   }

# }

resource "google_service_account" "service_account" {
  account_id                   = var.service_account.account_id
  display_name                 = var.service_account.display_name
  create_ignore_already_exists = true
}

resource "google_project_service" "project" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_binding" "service_account_log_admin" {
  project = var.project_id
  role    = "roles/logging.admin"
  members = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_project_iam_binding" "service_account_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_project_iam_binding" "service_account_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = ["serviceAccount:${google_service_account.service_account.email}"]
}

# Create a CloudSQL for PostgreSQL Instance
resource "google_sql_database_instance" "postgres_instance" {
  name                = var.postgres_instance.name
  project             = var.project_id
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
      ipv4_enabled                                  = var.postgres_instance.ipv4_enabled
      private_network                               = google_compute_network.vpc_network["vpc1"].self_link
      enable_private_path_for_google_cloud_services = true
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

data "google_dns_managed_zone" "webapp-zone" {
  name = var.public_zone_name
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.function.project
  location       = google_cloudfunctions2_function.function.location
  cloud_function = google_cloudfunctions2_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  project  = google_cloudfunctions2_function.function.project
  location = google_cloudfunctions2_function.function.location
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudfunctions2_function_iam_binding" "binding" {
  cloud_function = google_cloudfunctions2_function.function.name
  location       = google_cloudfunctions2_function.function.location
  role           = "roles/viewer"
  members        = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_pubsub_subscription_iam_binding" "editor" {
  subscription = google_pubsub_subscription.webapp_subscription.name
  role         = "roles/editor"
  members      = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_pubsub_topic_iam_binding" "binding" {
  project = google_pubsub_topic.webapp_topic.project
  topic   = google_pubsub_topic.webapp_topic.name
  role    = "roles/pubsub.editor"
  members = ["serviceAccount:${google_service_account.service_account.email}"]
}

# Create a topic
resource "google_pubsub_topic" "webapp_topic" {
  name                       = "verify_email"
  message_retention_duration = "604800s"
}

# Create subscription
resource "google_pubsub_subscription" "webapp_subscription" {
  name                       = "webapp_subscription"
  topic                      = google_pubsub_topic.webapp_topic.id
  message_retention_duration = "604800s"
  retain_acked_messages      = true
  expiration_policy {
    ttl = "604800s"
  }
  enable_exactly_once_delivery = true
  enable_message_ordering      = true
}

# Create bucket to store Cloud function
resource "google_storage_bucket" "bucket" {
  name                        = "${var.project_id}-gcf-source"
  location                    = "US"
  uniform_bucket_level_access = true
}

# Store Cloud function in the bucket
resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "function-source.zip" # Add path to the zipped function source code
}

resource "google_project_iam_binding" "service_account_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  members = ["serviceAccount:${google_service_account.service_account.email}"]
}

resource "google_vpc_access_connector" "connector" {
  name          = "connector"
  ip_cidr_range = "10.8.0.0/28"
  region        = var.region
  network       = google_compute_network.vpc_network["vpc1"].self_link
}

# Create cloud function based on the zip in bucket
resource "google_cloudfunctions2_function" "function" {
  name        = "webapp-email"
  location    = "us-east1"
  description = "webapp-function"

  # Cloud function build configuration
  build_config {
    runtime     = "java21"
    entry_point = "gcfv2pubsub.PubSubFunction" # Set the entry point 
    # Cloud function source
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  # Service configuration linked to service account
  service_config {
    max_instance_count               = 1
    available_memory                 = "128Mi"
    timeout_seconds                  = 120
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    service_account_email            = google_service_account.service_account.email
    vpc_connector                    = google_vpc_access_connector.connector.name
    vpc_connector_egress_settings    = "PRIVATE_RANGES_ONLY"
    all_traffic_on_latest_revision   = true
    environment_variables = {
      DB_USER       = "${google_sql_user.users.name}"
      DB_PASS       = "${random_password.sql_random_password.result}"
      DB_NAME       = "${google_sql_database.webappdb.name}"
      INSTANCE_HOST = "${google_sql_database_instance.postgres_instance.private_ip_address}"
      DB_PORT       = "5432"
    }

  }

  # Event Trigger linked to service account
  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.webapp_topic.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.service_account.email
  }

}

module "gce-lb-http" {
  source  = "terraform-google-modules/lb-http/google"
  version = "~> 10.0"
  name    = "loadbalancer"
  project = var.project_id

  ssl                             = true
  managed_ssl_certificate_domains = ["omkar-sde.me"]
  http_forward                    = false

  create_address = true

  network = google_compute_network.vpc_network["vpc1"].name

  # firewall_networks = [google_compute_network.vpc_network["vpc1"].name]

  backends = {
    default = {

      protocol    = "HTTP"
      port_name   = "http"
      timeout_sec = 60
      enable_cdn  = false

      health_check = {
        request_path        = "/healthz"
        port                = 8080
        healthy_threshold   = 3
        unhealthy_threshold = 5
        logging             = true
      }

      log_config = {
        enable      = true
        sample_rate = 1.0
      }

      groups = [
        {
          group = google_compute_region_instance_group_manager.webapp_instance_group_manager.instance_group
        }
      ]

      iap_config = {
        enable = false
      }
    }
  }
}


resource "google_dns_record_set" "webapp_dns_record_set" {
  name         = data.google_dns_managed_zone.webapp-zone.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.webapp-zone.name
  rrdatas      = [module.gce-lb-http.external_ip]
}
