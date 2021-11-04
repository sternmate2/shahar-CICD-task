#############################################################################
# TERRAFORM CONFIG
#############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"
    }
  }
  backend "azurerm" {
        resource_group_name  = "ShaharTF"
        storage_account_name = "shahars"
        container_name       = "tfstate"
        key                  = "terraform.tfstate"
    }
}


#############################################################################
# PROVIDERS
#############################################################################

provider "azurerm" {
  features {}
}

