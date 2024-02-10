# Configure the Terraform runtime requirements.
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.5"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  # Leave the features block empty to accept all defaults
  features {}
}
provider "cloudinit" {
  # Configuration options
}
# !!! This should only be used with a backend that stores encrypted state, like
# Terraform Cloud or AWS S3. Local state is NOT encrypted and should only be
# used to spin up temporary dev testing environments. 
provider "tls" {}

# Define config variables
variable "labelPrefix" {
  type        = string
  description = "Your college username. This will form the beginning of various resource names."
}

variable "assignmentCode" {
  type    = string
  default = "A05B"
}

variable "region" {
  type    = string
  default = "westus3"
}

variable "vmUsername" {
  type        = string
  default     = "azureadmin"
  description = "The username for the local user account on the VMs."
}

# Define the resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-${var.assignmentCode}-RG"
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
  name                = "${var.labelPrefix}-${var.assignmentCode}-SSH-publicKey"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  public_key          = tls_private_key.rsa.public_key_openssh
}

# Define a public IP address
resource "azurerm_public_ip" "webserver" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-WebIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}
resource "azurerm_public_ip" "bastion" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-BastionIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}
# Define the virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-VNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Define the subnets
resource "azurerm_subnet" "bastion" {
  name                 = "${var.labelPrefix}-${var.assignmentCode}-BastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "webserver" {
  name                 = "${var.labelPrefix}-${var.assignmentCode}-WebSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Define network security groups and rules
resource "azurerm_network_security_group" "bastion" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-BastionSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "webserver" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-WebSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = azurerm_subnet.bastion.address_prefixes
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Define the network interfaces
resource "azurerm_network_interface" "bastion" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-bastion-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "bastion-NIC-Config"
    subnet_id                     = azurerm_subnet.bastion.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_network_interface" "webserver" {
  name                = "${var.labelPrefix}-${var.assignmentCode}-webserver-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "webserver-NIC-Config"
    subnet_id                     = azurerm_subnet.webserver.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.webserver.id
  }
}

# Link the security groups to the NICs
resource "azurerm_network_interface_security_group_association" "bastion" {
  network_interface_id      = azurerm_network_interface.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_network_interface_security_group_association" "webserver" {
  network_interface_id      = azurerm_network_interface.webserver.id
  network_security_group_id = azurerm_network_security_group.webserver.id
}

# Define the init script template
data "cloudinit_config" "initWebserver" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "init.sh"
    content_type = "text/x-shellscript"

    content = file("${path.module}/init.sh")
  }
}

data "cloudinit_config" "initBastion" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = <<eof
#cloud-config

# Send pre-generated SSH private keys to the server
# If these are present, they will be written to /etc/ssh and
# new random keys will not be generated
#  in addition to 'rsa' as shown below, 'ecdsa' is also supported
ssh_keys:
  rsa_private: |
    ${indent(4, tls_private_key.rsa.private_key_openssh)}

  rsa_public: ${tls_private_key.rsa.public_key_openssh}

# By default, the fingerprints of the authorized keys for the users
# cloud-init adds are printed to the console. Setting
# no_ssh_fingerprints to true suppresses this output.
no_ssh_fingerprints: false

# By default, (most) ssh host keys are printed to the console. Setting
# emit_keys_to_console to false suppresses this output.
ssh:
  emit_keys_to_console: false

# Run commands on first boot
# https://cloudinit.readthedocs.io/en/latest/reference/examples.html#run-commands-on-first-boot
runcmd:
  - cp /etc/ssh/ssh_host_rsa_key /home/azureadmin/.ssh/id_rsa
  - chown azureadmin:azureadmin /home/azureadmin/.ssh/id_rsa
  - chmod 600 /home/azureadmin/.ssh/id_rsa

eof
  }
}

# Define the virtual machine
resource "azurerm_linux_virtual_machine" "bastion" {
  name                  = "${var.labelPrefix}-${var.assignmentCode}-bastion-VM"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  network_interface_ids = [azurerm_network_interface.bastion.id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "${var.labelPrefix}-${var.assignmentCode}-bastionOSDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "bastion"
  admin_username                  = var.vmUsername
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vmUsername
    public_key = file("~/.ssh/id_rsa.pub")
  }

  custom_data = data.cloudinit_config.initBastion.rendered
}

resource "azurerm_linux_virtual_machine" "webserver" {
  name                  = "${var.labelPrefix}-${var.assignmentCode}-webserver-VM"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  network_interface_ids = [azurerm_network_interface.webserver.id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "${var.labelPrefix}-${var.assignmentCode}-webserverOSDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "webserver"
  admin_username                  = var.vmUsername
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vmUsername
    public_key = tls_private_key.rsa.public_key_openssh
  }

  custom_data = data.cloudinit_config.initWebserver.rendered
}

# Define output values for use by other modules
output "webserver_public_ip" {
  value = azurerm_linux_virtual_machine.webserver.public_ip_address
}

output "webserver_private_ip" {
  value = azurerm_linux_virtual_machine.webserver.private_ip_address
}

output "bastion_public_ip" {
  value = azurerm_linux_virtual_machine.bastion.public_ip_address
}
