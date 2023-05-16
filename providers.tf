terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstatedemoazureappgw"
    storage_account_name = "tfstateazureappgw34535"
    container_name       = "tfstatedazureappgw"
    key                  = "tfstatedazureappgw.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "ad3a592d-2f32-4013-8b6a-a290a0aafed2"
}
