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
