# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4 — Databricks workspace, VNet-injected, secure cluster connectivity.
#
# Two things people conflate, and they are unrelated:
#
#   no_public_ip = true            → CLUSTER VMs get no public IP.
#                                    Nothing inbound can reach your compute.
#   public_network_access_enabled  → the WORKSPACE UI/API is reachable from
#                                    the internet. Left true so I can open the
#                                    workspace from my laptop. Locking this down
#                                    needs a private endpoint on the workspace
#                                    itself plus a route in (VPN/bastion).
#
# With no public IPs, clusters still must dial OUT to the Databricks control
# plane. That's what the NAT gateway below is for.
# ─────────────────────────────────────────────────────────────────────────────

# ── Outbound path for private clusters ───────────────────────────────────────
# A NAT gateway gives the subnets a single, stable egress IP. Nothing can
# initiate a connection inbound through it — it only does source NAT for
# outbound flows. That asymmetry is the whole point.
#
# 💸 This is the most expensive resource in the project: ~$0.045/hour plus
#    ~$0.045/GB processed. `terraform destroy` between sessions.

resource "azurerm_public_ip" "nat" {
  name                = "${var.prefix}-nat-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.rg.tags
}

resource "azurerm_nat_gateway" "dbx" {
  name                    = "${var.prefix}-nat"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = azurerm_resource_group.rg.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.dbx.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "dbx_host" {
  subnet_id      = azurerm_subnet.databricks_host.id
  nat_gateway_id = azurerm_nat_gateway.dbx.id
}

resource "azurerm_subnet_nat_gateway_association" "dbx_container" {
  subnet_id      = azurerm_subnet.databricks_container.id
  nat_gateway_id = azurerm_nat_gateway.dbx.id
}

# ── The workspace ────────────────────────────────────────────────────────────
resource "azurerm_databricks_workspace" "this" {
  name                = "${var.prefix}-dbx"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # PREMIUM IS REQUIRED — Unity Catalog does not exist on Standard, and phase 5
  # is entirely Unity Catalog. Premium also brings table ACLs and SCIM.
  sku = "premium"

  # Databricks creates a second, LOCKED resource group in my subscription
  # holding cluster VMs, disks and its own NSG. I can see it; I must not edit
  # it. That's the compute plane living in my tenant.
  managed_resource_group_name = "${var.prefix}-dbx-managed-rg"

  public_network_access_enabled         = true
  network_security_group_rules_required = "AllRules"

  custom_parameters {
    no_public_ip = true # ← secure cluster connectivity

    virtual_network_id  = azurerm_virtual_network.vnet.id
    public_subnet_name  = azurerm_subnet.databricks_host.name
    private_subnet_name = azurerm_subnet.databricks_container.name

    # Databricks validates that the NSG associations exist before it will
    # inject into the subnets, so these references are load-bearing.
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbx_host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbx_container.id
  }

  tags = azurerm_resource_group.rg.tags

  depends_on = [
    azurerm_subnet_nat_gateway_association.dbx_host,
    azurerm_subnet_nat_gateway_association.dbx_container,
  ]
}
