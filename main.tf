# Configure the Terraform runtime requirements.
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    # Azure Resource Manager REST API for features not supported by AzureRM
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  features {}
}

provider "azapi" {
}

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

resource "azapi_resource" "ssh_key_pair" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = "${var.labelPrefix}-SSH-publicKey"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
}

# This should only be used with a backend that stores encrypted state, like
# Terraform Cloud or AWS S3. Local state is NOT encrypted and should only be
# used to spin up temporary dev testing environments. 
resource "azapi_resource_action" "gen_ssh_keys" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_key_pair.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

output "public_key" {
  value = jsondecode(azapi_resource_action.gen_ssh_keys.output).publicKey
}

output "private_key" {
  value = jsondecode(azapi_resource_action.gen_ssh_keys.output).privateKey
}
