locals {
  value_list = [for i in range(var.storage_account_count) : "${var.name}${i + 1}"]
}

data "azurerm_client_config" "current" {
}

data "azurerm_client_config" "currentdns" {
  provider = azurerm.dns
}

data "azurerm_dns_zone" "example" {
  name                = var.domain
  provider            = azurerm.dns
  resource_group_name = var.domain_rg
}

resource "azurerm_dns_cname_record" "example" {
  for_each            = toset(local.value_list)
  name                = "asverify.${each.value}"
  provider            = azurerm.dns
  zone_name           = data.azurerm_dns_zone.example.name
  resource_group_name = data.azurerm_dns_zone.example.resource_group_name
  ttl                 = 300
  record              = "asverify.${each.value}.z6.web.core.windows.net"
}

resource "azurerm_resource_group" "demo_rg_terraformazureappgw" {
  name     = "demo-rg-terraformazureappgw"
  location = "West Europe"
}

resource "azurerm_storage_account" "demo_sa_terraformazureappgw" {
  for_each                        = toset(local.value_list)
  name                            = each.value
  resource_group_name             = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location                        = azurerm_resource_group.demo_rg_terraformazureappgw.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = true

  static_website {
    index_document = "index.html"
  }

  custom_domain {
    name          = "${each.value}.${var.domain}"
    use_subdomain = true
  }

  tags = {
    environment = "demo"
  }

  lifecycle {
    ignore_changes = [
      custom_domain.0.use_subdomain,
    ]
  }

  depends_on = [azurerm_dns_cname_record.example]
}

data "azurerm_storage_container" "example" {
  for_each             = toset(local.value_list)
  name                 = "$web"
  storage_account_name = azurerm_storage_account.demo_sa_terraformazureappgw[each.value].name
}

resource "local_file" "htmlfile" {
  for_each = toset(local.value_list)
  content  = each.value
  filename = "content/index-${each.value}.html"
}

resource "azurerm_storage_blob" "example" {
  for_each               = toset(local.value_list)
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.demo_sa_terraformazureappgw[each.value].name
  storage_container_name = data.azurerm_storage_container.example[each.value].name
  type                   = "Block"
  content_type           = "text/html"
  source                 = "content/index-${each.value}.html"
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
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.example.id
  }

  dynamic "backend_address_pool" {
    for_each = toset(local.value_list)
    content {
      name  = "${local.backend_address_pool_name}-${backend_address_pool.value}"
      fqdns = ["${backend_address_pool.value}.z6.web.core.windows.net"]
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

  dynamic "http_listener" {
    for_each = toset(local.value_list)
    content {
      name                           = "${local.listener_name}-${http_listener.value}"
      frontend_ip_configuration_name = local.frontend_ip_configuration_name
      frontend_port_name             = local.frontend_port_name
      protocol                       = "Https"
      host_name                      = "${http_listener.value}.${var.domain}"
      ssl_certificate_name           = "${http_listener.value}-${replace(var.domain, ".", "-")}"
      require_sni                    = true
    }
  }

  dynamic "request_routing_rule" {
    for_each = toset(local.value_list)
    content {
      name                       = "${local.request_routing_rule_name}-${request_routing_rule.value}"
      rule_type                  = "Basic"
      http_listener_name         = "${local.listener_name}-${request_routing_rule.value}"
      backend_address_pool_name  = "${local.backend_address_pool_name}-${request_routing_rule.value}"
      backend_http_settings_name = local.http_setting_name
      priority                   = (index(local.value_list, request_routing_rule.value) + 210)
    }
  }

  dynamic "ssl_certificate" {
    for_each = toset(local.value_list)
    content {
      name                = "${ssl_certificate.value}-${replace(var.domain, ".", "-")}"
      key_vault_secret_id = azurerm_key_vault_certificate.example[ssl_certificate.value].versionless_secret_id
    }
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.example.id,
    ]
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }
}

resource "azurerm_dns_a_record" "example2" {
  for_each            = toset(local.value_list)
  name                = each.value
  provider            = azurerm.dns
  zone_name           = data.azurerm_dns_zone.example.name
  resource_group_name = data.azurerm_dns_zone.example.resource_group_name
  ttl                 = 300
  records             = [azurerm_public_ip.example.ip_address]
}

resource "azuread_application" "example" {
  display_name = "Demo Terraform Azure App Gateway"
}

resource "azuread_service_principal" "example" {
  application_id = azuread_application.example.application_id
}

resource "time_rotating" "example" {
  rotation_days = 7
}

resource "azuread_service_principal_password" "example" {
  service_principal_id = azuread_service_principal.example.object_id
  rotate_when_changed = {
    rotation = time_rotating.example.id
  }
}

resource "azurerm_role_assignment" "example" {
  scope                = data.azurerm_dns_zone.example.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azuread_service_principal.example.object_id
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = "letsencrypt@techie.cloud"
}

resource "random_password" "password" {
  for_each         = toset(local.value_list)
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "acme_certificate" "certificate" {
  for_each                 = toset(local.value_list)
  account_key_pem          = acme_registration.reg.account_key_pem
  common_name              = "${each.value}.${var.domain}"
  certificate_p12_password = random_password.password[each.value].result

  dns_challenge {
    provider = "azure"

    config = {
      AZURE_CLIENT_ID       = azuread_application.example.application_id
      AZURE_CLIENT_SECRET   = azuread_service_principal_password.example.value
      AZURE_ZONE_NAME       = data.azurerm_dns_zone.example.name
      AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.currentdns.subscription_id
      AZURE_TENANT_ID       = data.azurerm_client_config.currentdns.tenant_id
      AZURE_RESOURCE_GROUP  = data.azurerm_dns_zone.example.resource_group_name
    }
  }
}

resource "azurerm_key_vault" "example" {
  name                     = var.name
  resource_group_name      = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location                 = azurerm_resource_group.demo_rg_terraformazureappgw.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled = true
}

resource "azurerm_user_assigned_identity" "example" {
  resource_group_name = azurerm_resource_group.demo_rg_terraformazureappgw.name
  location            = azurerm_resource_group.demo_rg_terraformazureappgw.location
  name                = "${var.name}-identity"
}

resource "azurerm_key_vault_access_policy" "example" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.example.principal_id

  certificate_permissions = [
    "Get", "List"
  ]

  secret_permissions = [
    "Get",
  ]
}

resource "azurerm_key_vault_access_policy" "example2" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  certificate_permissions = [
    "Get", "List", "Create", "Import", "Update", "Delete", "Backup", "Restore", "Recover"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Purge", "Delete", "Backup", "Restore", "Recover"
  ]
}

resource "azurerm_key_vault_certificate" "example" {
  for_each     = toset(local.value_list)
  name         = "${each.value}-${replace(var.domain, ".", "-")}"
  key_vault_id = azurerm_key_vault.example.id

  certificate {
    contents = acme_certificate.certificate[each.value].certificate_p12
    password = random_password.password[each.value].result
  }
  depends_on = [
    azurerm_key_vault_access_policy.example,
    azurerm_key_vault_access_policy.example2,
  ]
}
