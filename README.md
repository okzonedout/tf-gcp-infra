# GCP Networking with Terraform and GitHub Actions

This repository contains Terraform configurations for setting up networking infrastructure on Google Cloud Platform (GCP), along with a GitHub Actions workflow for automating Terraform operations.

## Overview

We use Terraform to create and manage a Virtual Private Cloud (VPC) along with subnets and internet access routes in GCP. The setup includes creating multiple VPCs, configuring subnets within these VPCs, and ensuring connectivity with the internet.

Additionally, we leverage GitHub Actions to automate the Terraform plan and apply stages, providing a CI/CD approach to infrastructure management.

## Prerequisites

- A GCP account and a GCP project.
- Google Cloud SDK and Terraform installed on your local machine for testing and initial setup.
- Basic understanding of Terraform and GitHub Actions.

## Terraform Configuration

The Terraform setup involves creating:

- **VPCs**: Virtual Private Clouds to isolate network environments within GCP.
- **Subnets**: Sub-networks within each VPC to organize resources logically.
- **Internet Gateway Route**: A route to allow outbound internet access from resources within the subnets.

### Variables

Variables are used to ensure flexibility and reusability of the Terraform configurations. You need to define variables for project ID, region, VPCs, and subnets in your Terraform configurations.

### Directory Structure

```
.
├── main.tf          # Main Terraform configuration file
├── variables.tf     # Variable definitions
├── terraform.tfvars # Variable values
└── terraform.auto.tfvars # Variable values
```

## GitHub Actions Workflow

The `.github/workflows/build.yml` file defines the GitHub Actions workflow to automate Terraform operations:

- **Setup Terraform**: Install the specified version of Terraform.
- **Terraform Init**: Initialize the Terraform project.
- **Terraform Plan**: Execute a plan to show potential changes.
- **Terraform Apply**: Apply the changes (commented out by default for safety).

## Getting Started

1. **Configure GCP Credentials**: Ensure your GitHub Actions runner has access to GCP credentials, typically by setting secrets in the GitHub repository.

2. **Initialize Terraform Locally** (optional for testing):

   ```
   terraform init
   terraform plan
   terraform apply
   ```
