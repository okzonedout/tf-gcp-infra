provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc_network" {
  for_each                        = var.vpcs
  name                            = each.value.name
  auto_create_subnetworks         = each.value.auto_create_subnetworks
  routing_mode                    = each.value.routing_mode
  delete_default_routes_on_create = each.value.delete_default_routes_on_create
}

resource "google_compute_subnetwork" "subnets" {
  for_each      = var.subnets
  name          = each.value.subnet_name
  ip_cidr_range = each.value.ip_cidr_range
  region        = each.value.region
  network       = google_compute_network.vpc_network[each.value.network].self_link
}

resource "google_compute_route" "csye6225-vpc-1" {
  name             = "csye6225-vpc-1-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network["vpc1"].self_link
  next_hop_gateway = "default-internet-gateway"
}

data "google_compute_image" "my_image" {
  family  = "centos-csye6225"
  project = "csye6225-omkar"
}

resource "google_compute_instance" "instance-1" {
  machine_type              = "n1-standard-1"
  name                      = "instance-1"
  zone                      = "us-east1-b"
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    device_name = "instance-1"

    initialize_params {
      # image = "projects/csye6225-omkar/global/images/centos-csye6225-1708497196"
      image = data.google_compute_image.my_image.self_link
      size  = 100
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  network_interface {
    access_config {}
    network    = google_compute_network.vpc_network["vpc1"].self_link
    subnetwork = google_compute_subnetwork.subnets["webapp-1"].self_link
  }
}

resource "google_compute_firewall" "allow_http" {
  name     = "allow-8080"
  network  = google_compute_network.vpc_network["vpc1"].self_link
  priority = 999

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_all" {
  name     = "deny-all"
  network  = google_compute_network.vpc_network["vpc1"].self_link
  priority = 1000

  deny {
    protocol = "all"
    ports    = []
  }

  source_ranges = ["0.0.0.0/0"]
}
