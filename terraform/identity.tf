# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — Identity and access.
#
# The question this answers: how does Databricks read the lake without anyone
# putting a storage key in a config file?
#
# Prior art I already know:
#   Kerberos keytab  → a credential FILE, distributed to every node, protected,
#                      rotated, and the thing that breaks a prod job at 2am when
#                      it expires.
#   AWS instance profile → EC2 assumes a role, gets short-lived creds, nothing
#                      on the box.
#
# Azure managed identity is the second pattern. Azure holds the credential; the
# compute asks the platform for a short-lived token. There is no secret on disk
# to leak, and nothing to rotate.
#
# Note Azure splits what AWS IAM does in one place:
#   Entra ID     = WHO you are      (the identity below)
#   Azure RBAC   = WHAT you may do  (the role assignments below)
# ─────────────────────────────────────────────────────────────────────────────

# A `data` block READS something that already exists — it never creates or
# manages it. Here: details about whoever ran `az login`.
data "azurerm_client_config" "current" {}

# The Databricks Access Connector is a purpose-built managed identity that a
# Databricks workspace uses to reach storage. "SystemAssigned" means its
# lifecycle is tied to this resource — delete the connector, the identity goes.
resource "azurerm_databricks_access_connector" "uc" {
  name                = "${var.prefix}-dbx-connector"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.rg.tags
}

# ── Role assignments ─────────────────────────────────────────────────────────
# RBAC is three things: WHO (principal) can do WHAT (role) WHERE (scope).
# Scope here is the storage account, so these grants cover every filesystem in
# it and nothing outside it. Scoping to the account rather than the whole
# resource group is least privilege in practice.

# The machine identity — this is how Unity Catalog will reach the lake.
resource "azurerm_role_assignment" "connector_on_lake" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.uc.identity[0].principal_id
}

# The human — pinned by object ID, NOT data.azurerm_client_config.current.
# See variable human_admin_object_id for why that distinction matters once CI
# runs the same config. Same role, same mechanism: RBAC does not
# care whether a principal is a person or a workload.
resource "azurerm_role_assignment" "me_on_lake" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.human_admin_object_id
}
