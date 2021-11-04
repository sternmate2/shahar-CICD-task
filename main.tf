#############################################################################
# RESOURCES
#############################################################################
# NetWork 
#############################################################################
resource "azurerm_resource_group" "test" {
  name     = var.resource_group_name
  location = var.location
}

module "test" {
  source              = "Azure/vnet/azurerm"
  version             = "~> 2.0"
  resource_group_name = azurerm_resource_group.test.name
  vnet_name           = var.resource_group_name
  address_space       = [var.vnet_cidr_range]
  subnet_prefixes     = var.subnet_prefixes
  subnet_names        = var.subnet_names
  nsg_ids             = {}

  tags = {
    environment = "dev"
    costcenter  = "it"

  }

  depends_on = [azurerm_resource_group.test]
}

##########################################################################


resource "azurerm_network_interface" "test" {
  count               = var.env == "prod" ? 2 : 1      
  name                = "VM1${count.index}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = element(module.test.vnet_subnets, 0)
    private_ip_address_allocation = "Dynamic"
  }
}

  
#############################################################################
# Machines
#############################################################################

# Create Network Security Group and rule
# resource "azurerm_network_security_group" "test" {
#     name                = "NSG"
#     location            = "eastus"
#     resource_group_name = azurerm_resource_group.test.name

#     security_rule {
#         name                       = "SSH"
#         priority                   = 1001
#         direction                  = "Inbound"
#         access                     = "Allow"
#         protocol                   = "Tcp"
#         source_port_range          = "*"
#         destination_port_range     = "22"
#         source_address_prefix      = "*"
#         destination_address_prefix = "*"
#     }

#     tags = {
#         environment = "Terraform Demo"
#     }
# }

# # Connect the security group to the network interface
# resource "azurerm_network_interface_security_group_association" "example" {
#     network_interface_id      = azurerm_network_interface.test[0].id
#     network_security_group_id = azurerm_network_security_group.test.id
# }

#############################################################################
resource "azurerm_virtual_machine" "test" {
  count = var.env == "prod" ? 2 : 1
  name                = "MYVM-${count.index}"
  resource_group_name = azurerm_resource_group.test.name
  location            = var.location
  vm_size               = "Standard_DS1_v2"
  network_interface_ids = [azurerm_network_interface.test[count.index].id]
  availability_set_id   = azurerm_availability_set.test.id
 
 os_profile {
    computer_name  = "hostname"
    admin_username = "shahars"
    #admin_password = "ss310379"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = data.azurerm_key_vault_secret.secret.value
       path     = "/home/shahars/.ssh/authorized_keys"
    }   
  }   

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  
  # provisioner "file" {
  #   source      = "/home/shahars/ShaharTF/test.txt"
  #   destination = "/home/shahars/test.txt"
  # }
  # connection {
  #   type = "ssh"
  #   user = "shahars"
  #   host = azurerm_network_interface.test[count.index].private_ip_address
  #   private_key = file("~/.ssh/id_rsa.pub")
  #   agent    = false
  # }


}
 
 
 

   
  
#   admin_ssh_key {
#       username       = "azureuser"
#       public_key     = file("~/.ssh/id_rsa.pub")    
#   }
  
###########################################################################################################################


  
  # # provisioner "file" {
  #     connection {
  #       type = "ssh"
  #       user = "shahars"
  #       host = azurerm_lb.LB.id
  #       agent    = false
  #       timeout  = "10m"
  #     }
  #     source = "/home/shahars/.ssh/id_rsa"
  #     destination = "/home/shahars/.ssh/id_rsa"
  #   }




 resource "azurerm_virtual_machine_extension" "test" {
   count = var.env == "prod" ? 2 : 1
   name                = "hostname-${count.index}"
   virtual_machine_id   = azurerm_virtual_machine.test[count.index].id
   publisher            = "Microsoft.Azure.Extensions"
   type                 = "CustomScript"
   type_handler_version = "2.0"

   settings = <<SETTINGS
     {
         "commandToExecute": "cd /home/shahars && mkdir ./IaC && sudo apt-get install openjdk-8-jre-headless -y && wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add - && sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list' && sudo apt update -y && sudo apt install jenkins -y"

     }

 SETTINGS

}

# git clone git@github.com:eToro-bootcamp/BootcapProject.git

#############################################################################
# Peering
#############################################################################


data "azurerm_virtual_network" "shaharbastion" {
  name                = "bastion1"
  resource_group_name = "bastion1"
}

data "azurerm_resource_group" "shaharpeering" {
   name                = "bastion1"
}


resource "azurerm_virtual_network_peering" "shaharbastion" {
  name                      = "peertobastion1"
  resource_group_name       = azurerm_resource_group.test.name
  virtual_network_name      = module.test.vnet_name
  remote_virtual_network_id = data.azurerm_virtual_network.shaharbastion.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit = false
}

resource "azurerm_virtual_network_peering" "shaharpeering" {
  name                      = "peertoShaharTF"
  resource_group_name       = data.azurerm_resource_group.shaharpeering.name
  virtual_network_name      = data.azurerm_virtual_network.shaharbastion.name
  remote_virtual_network_id = module.test.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit = false
}

#############################################################################
# LoadBalncer + BackEndPool + LB rules
#############################################################################

resource "azurerm_public_ip" "LBIP" {
  name                = "PublicIPForLB"
  location            = var.location
  resource_group_name = azurerm_resource_group.test.name 
  allocation_method   = "Static"
}

resource "azurerm_lb" "LB" {
  name                = "TestLoadBalancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.test.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.LBIP.id 
  }
}

resource "azurerm_lb_backend_address_pool" "test" {
  loadbalancer_id = azurerm_lb.LB.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "test" {
  resource_group_name = azurerm_resource_group.test.name
  loadbalancer_id     = azurerm_lb.LB.id
  name                = "TCP-running-probe"
  port                = 8080
}

resource "azurerm_lb_rule" "test" {
  resource_group_name            = azurerm_resource_group.test.name
  loadbalancer_id                = azurerm_lb.LB.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  probe_id                       = azurerm_lb_probe.test.id
  backend_port                   = 8080
  backend_address_pool_id        = azurerm_lb_backend_address_pool.test.id
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_availability_set" "test" {
  name                = "example-aset"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

}

resource "azurerm_network_interface_backend_address_pool_association" "test" {
  count = var.env == "prod" ? 2 : 1
  network_interface_id    = azurerm_network_interface.test[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.test.id
}

# data "azurerm_public_ip" "test" {
#   name                = azurerm_public_ip.LBIP.name
#   resource_group_name = var.resource_group_name
# }


# resource "null_resource" "readcontentfile" {
#   provisioner "local-exec" {
#    command = "cat ~/.ssh/id_rsa >> test2.txt"
#   }
# }


# resource "null_resource" remoteExecProvisionerWFolder {

#   provisioner "file" {
#     source      = "/home/shahars/ShaharTF/test2.txt"
#     destination = "/home/shahars/.ssh/test.txt"
#   }
#   connection {
#     bastion_host = "13.90.255.58" 
#     host         = "80.0.0.4"
#     user         = "shahars"
#     private_key  = "${file("~/.ssh/id_rsa")}"
#   }

# }
#############################################################################
# OutPut For Debug
#############################################################################

# data "azurerm_key_vault" "key_vault" {
#     name = "ShaharMyKeyVault"
#     resource_group_name = "shahar-azuretask-rg"
# }

# data "azurerm_key_vault_secret" "test" {
#   name      = "SshPrivateKey"
#   key_vault_id = "/subscriptions/0df0b217-e303-4931-bcbf-af4fe070d1ac/resourceGroups/shahar-azuretask-rg/providers/Microsoft.KeyVault/vaults/ShaharMyKeyVault"
# }


# output "secret_value" {
#   value = data.azurerm_key_vault_secret.test.value
# }

data "azurerm_key_vault" "kv" {
  name                = "SternMateKeyVault"
  resource_group_name = "ShaharTF"
}
data "azurerm_key_vault_secret" "secret" {
  name         = "PublicKey"
  key_vault_id = data.azurerm_key_vault.kv.id
}


# test

# output "virtual_network_id" {
#   value = data.azurerm_virtual_network.shaharbastion.id
# } 

# output "vnet_id" {
#   value = module.test.vnet_id
# }

# output "netwrk_id" {
#   value = azurerm_network_interface.test[0].id
# }




