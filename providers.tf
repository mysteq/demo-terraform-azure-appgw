terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.115.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
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

provider "azurerm" {
  features {}
  alias           = "dns"
  subscription_id = "646dcda3-7645-475b-8dc3-be6257586e68"
}

provider "azuread" {
  tenant_id = data.azurerm_client_config.current.tenant_id
}

provider "acme" {
  server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
}