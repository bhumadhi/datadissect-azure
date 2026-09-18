# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — Landing zone: a resource group and an ADLS Gen2 storage account.
#
# Cloudera mapping:
#   Resource group   ~ no direct equivalent; a logical container + lifecycle unit
#   Storage account  ~ the cluster's HDFS namespace
#   Filesystem       ~ a top-level HDFS directory
#   is_hns_enabled   ~ THE flag that makes this a real filesystem (directories,
#                      atomic rename) instead of a flat blob store. Without it
#                      you have Blob storage, not ADLS Gen2, and Spark's ABFS
#                      driver will behave badly.
# ─────────────────────────────────────────────────────────────────────────────

# Storage account names are globally unique across all of Azure, so we add
# random characters rather than guessing something unclaimed.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location

  tags = {
    project = "datadissect-azure"
    purpose = "learning"
  }
}

resource "azurerm_storage_account" "lake" {
  name                     = "${var.prefix}lake${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # cheapest; single-region. Fine for learning.

  is_hns_enabled = true # ← this is what makes it ADLS Gen2 rather than Blob

  # Security defaults worth knowing — these are the kinds of controls the
  # "landing zone, networking, security controls" line in a JD refers to.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = azurerm_resource_group.rg.tags
}

# The medallion zones. In DataDissect these were MinIO buckets; here they are
# filesystems (containers) in one ADLS Gen2 account.
resource "azurerm_storage_data_lake_gen2_filesystem" "zones" {
  for_each = toset(["raw", "cleansed", "curated", "managed"])

  name               = each.key
  storage_account_id = azurerm_storage_account.lake.id
}
