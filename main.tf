# !!! This should only be used with a backend that stores encrypted state, like
# Terraform Cloud or AWS S3. Local state is NOT encrypted and should only be
# used to spin up temporary dev testing environments. 

terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.5"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  features {}
}

provider "tls" {}

# Define config variables
variable "labelPrefix" {
  type        = string
  description = "Your college username. This will form the beginning of various resource names."
}

variable "region" {
  default = "westus3"
}

# Define the resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05B-RG"
  location = var.region
}

# Generate an RSA key of size 4096 bits
# This is an in-memory resource. 
# Caution! It is stored in your Terraform state.
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "example" {
  name                = "${var.labelPrefix}-A05B-SSH-publicKey"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  public_key          = tls_private_key.rsa.public_key_openssh
}

output "private_key" {
  sensitive = true
  value     = tls_private_key.rsa.private_key_openssh
}
