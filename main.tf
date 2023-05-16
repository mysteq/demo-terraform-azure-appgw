resource "azurerm_resource_group" "demo_rg_terraformazureappgw" {
  name     = "demo-rg-terraformazureappgw"
  location = "West Europe"
}

resource "azurerm_storage_account" "demo_sa_terraformazureappgw" {
  count                    = var.storage_account_count
  name                     = "demoterraformazureappgw${count.index}"
  resource_group_name      = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location                 = azurerm_resource_group.demo_rg_terraformazureappgw.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  static_website {
    index_document = "index.html"
  }

  tags = {
    environment = "demo"
  }
}

data "azurerm_storage_container" "example" {
  count                = var.storage_account_count
  name                 = "$web"
  storage_account_name = "demoterraformazureappgw${count.index}"
}

resource "local_file" "htmlfile" {
  count    = var.storage_account_count
  content  = "demoterraformazureappgw${count.index}"
  filename = "content/index${count.index}.html"
}

resource "azurerm_storage_blob" "example" {
  count                  = var.storage_account_count
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.demo_sa_terraformazureappgw[count.index].name
  storage_container_name = data.azurerm_storage_container.example[count.index].name
  type                   = "Block"
  content_type           = "text/html"
  source                 = "content/index${count.index}.html"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-network"
  resource_group_name = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location            = azurerm_resource_group.demo_rg_terraformazureappgw.location
  address_space       = ["10.254.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "frontend"
  resource_group_name  = azurerm_resource_group.demo_rg_terraformazureappgw.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.254.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = azurerm_resource_group.demo_rg_terraformazureappgw.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.254.2.0/24"]
}

resource "azurerm_public_ip" "example" {
  name                = "example-pip"
  resource_group_name = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location            = azurerm_resource_group.demo_rg_terraformazureappgw.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "demoterraformazureappgw"
}

# since these variables are re-used - a locals block makes this more maintainable
locals {
  backend_address_pool_name      = "${azurerm_virtual_network.example.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.example.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.example.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.example.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.example.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.example.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.example.name}-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
  name                = "example-appgateway"
  resource_group_name = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location            = azurerm_resource_group.demo_rg_terraformazureappgw.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.example.id
  }

  dynamic "backend_address_pool" {
    for_each = azurerm_storage_account.demo_sa_terraformazureappgw[*]
    content {
      name  = "${local.backend_address_pool_name}-${backend_address_pool.value.name}"
      fqdns = ["${backend_address_pool.value.name}.z6.web.core.windows.net"]
    }
  }

  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = "${local.backend_address_pool_name}-demoterraformazureappgw0"
    backend_http_settings_name = local.http_setting_name
    priority                   = 210
  }
}
