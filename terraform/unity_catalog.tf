# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5 — Unity Catalog.
#
# This replaces the Hive Metastore + Ranger model. The chain is four objects and
# it only makes sense read in order:
#
#   1. STORAGE CREDENTIAL   wraps the managed identity from phase 2.
#                           "Here is an identity UC may use."
#   2. EXTERNAL LOCATION    binds that credential to an abfss:// path.
#                           "That identity may be used for THIS path."
#   3. CATALOG / SCHEMA     the three-level namespace: catalog.schema.table
#   4. GRANT                who may do what. This is Ranger policies, relocated.
#
# The credential/location split is the important design: one identity, many
# paths, each governed separately. You grant on the location, not the key —
# which is why nobody ever needs the storage key again.
# ─────────────────────────────────────────────────────────────────────────────

resource "databricks_storage_credential" "lake" {
  name    = "${var.prefix}-lake-cred"
  comment = "Managed identity from the Databricks Access Connector (phase 2)"

  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.uc.id
  }

  depends_on = [azurerm_role_assignment.connector_on_lake]
}

# One external location per medallion zone. Governing each separately means a
# team could be granted read on curated without ever seeing raw PHI.
resource "databricks_external_location" "zones" {
  for_each = toset(["raw", "cleansed", "curated", "managed"])

  name            = "${var.prefix}-${each.key}"
  url             = "abfss://${each.key}@${azurerm_storage_account.lake.name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.lake.name
  comment         = "${each.key} zone"

  depends_on = [azurerm_storage_data_lake_gen2_filesystem.zones]
}

# ── The three-level namespace ────────────────────────────────────────────────
resource "databricks_catalog" "claims" {
  name    = "claims"
  comment = "Healthcare claims, ported from DataDissect"

  # Azure's auto-provisioned metastore has no root storage, so the catalog must
  # declare where its MANAGED tables live.
  storage_root = databricks_external_location.zones["managed"].url

  properties = {
    purpose = "datadissect-azure"
  }

  depends_on = [databricks_external_location.zones]
}

# bronze/silver/gold — the same medallion layers as DataDissect, now as schemas
# instead of bucket prefixes.
resource "databricks_schema" "layers" {
  for_each = {
    bronze = "Raw 837P claims as ingested, no transformation"
    silver = "Validated and PHI-masked claims"
    gold   = "Curated member, payer and provider summaries"
  }

  catalog_name = databricks_catalog.claims.name
  name         = each.key
  comment      = each.value
}

# ── Governance ───────────────────────────────────────────────────────────────
# In Cloudera this was an AD group mapped to a Ranger policy. Here it's a grant
# on a catalog to a Databricks account group. Same model, different surface.
resource "databricks_grants" "claims_catalog" {
  catalog = databricks_catalog.claims.name

  grant {
    principal  = "account users"
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}

# Read-only on raw. Nobody gets to write into the landing zone by hand.
resource "databricks_grants" "raw_location" {
  external_location = databricks_external_location.zones["raw"].id

  grant {
    principal  = "account users"
    privileges = ["READ_FILES"]
  }
}
