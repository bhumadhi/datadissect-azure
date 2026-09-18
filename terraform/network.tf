# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — Networking.
#
# Right now the lake is reachable over its PUBLIC endpoint from anywhere on the
# internet, protected only by identity. That's fine for a demo and unacceptable
# for PHI. Production wants the data path to never traverse the public internet.
#
# What we build:
#   VNet                  ~ your on-prem network, software-defined
#   Subnets               ~ subnets. Same thing. (RHCE knowledge applies.)
#   NSG                   ~ firewall rules (iptables/firewalld, per-subnet)
#   Private endpoint      ~ gives the storage account a private IP INSIDE the VNet
#   Private DNS zone      ~ makes the storage hostname resolve to that private IP
#
# The DNS piece is the part people miss. A private endpoint without private DNS
# gives you an IP nothing knows how to find.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = azurerm_resource_group.rg.tags
}

# ── Subnet 1: private endpoints ──────────────────────────────────────────────
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# ── Subnets 2 & 3: Databricks (phase 4) ──────────────────────────────────────
# A VNet-injected Databricks workspace requires exactly two dedicated subnets,
# both DELEGATED to Microsoft.Databricks/workspaces. Delegation hands subnet
# management to that service — nothing else may live in them.
#
#   host      ("public")  — cluster nodes' outbound path
#   container ("private") — where the cluster containers actually run
#
# The names are Databricks' convention and are misleading: neither gets a public
# IP when secure cluster connectivity is on.

resource "azurerm_network_security_group" "databricks" {
  name                = "${var.prefix}-dbx-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = azurerm_resource_group.rg.tags
}

resource "azurerm_subnet" "databricks_host" {
  name                 = "snet-dbx-host"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]

  delegation {
    name = "databricks-del"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet" "databricks_container" {
  name                 = "snet-dbx-container"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.3.0/24"]

  delegation {
    name = "databricks-del"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

# Databricks requires an NSG on BOTH of its subnets. It injects its own rules.
resource "azurerm_subnet_network_security_group_association" "dbx_host" {
  subnet_id                 = azurerm_subnet.databricks_host.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_subnet_network_security_group_association" "dbx_container" {
  subnet_id                 = azurerm_subnet.databricks_container.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

# ── Private DNS ──────────────────────────────────────────────────────────────
# Without this, ddazlake....dfs.core.windows.net resolves to a PUBLIC IP and the
# private endpoint is never used. Azure overrides that lookup inside the VNet by
# creating an A record in this zone pointing at the endpoint's private IP.
resource "azurerm_private_dns_zone" "dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = azurerm_resource_group.rg.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dfs" {
  name                  = "${var.prefix}-dfs-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dfs.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

# ── The private endpoint itself ──────────────────────────────────────────────
resource "azurerm_private_endpoint" "lake_dfs" {
  name                = "${var.prefix}-lake-dfs-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = azurerm_resource_group.rg.tags

  private_service_connection {
    name                           = "lake-dfs-connection"
    private_connection_resource_id = azurerm_storage_account.lake.id
    subresource_names              = ["dfs"] # the ADLS Gen2 endpoint, not blob
    is_manual_connection           = false
  }

  # Auto-creates the A record in the zone above.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dfs.id]
  }
}

# NOTE ON PUBLIC ACCESS
# ---------------------
# public_network_access_enabled is still true on the storage account, so my
# laptop can keep uploading files. In production you would set it to false and
# reach the lake only from inside the VNet — at which point CI/CD and any
# human access need a jump host, VPN, or a self-hosted runner in the VNet.
# That tradeoff is the real reason "just lock it down" is harder than it sounds.
