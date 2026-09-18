# ─────────────────────────────────────────────────────────────────────────────
# PHASE 7 — CI/CD identity, via OIDC federation. No secret anywhere.
#
# The old way: create an app registration, generate a client secret, paste it
# into GitHub Secrets, and remember to rotate it. That secret is a long-lived
# credential sitting in a third party's system — the keytab problem again.
#
# Federated credentials remove it. GitHub Actions mints a short-lived OIDC token
# describing the run (repo, branch, workflow). Entra trusts that issuer for this
# specific subject, exchanges the token for an Azure access token, and the job
# proceeds. Nothing is stored. Nothing expires. Nothing to rotate.
#
# Third time this pattern appears in this project:
#   managed identity  → compute has no key
#   Unity Catalog     → the pipeline has no key
#   OIDC federation   → CI has no key
# ─────────────────────────────────────────────────────────────────────────────

# GitHub presents an IMMUTABLE subject claim containing numeric owner and repo
# IDs, not names:
#
#   repo:bhumadhi@19201510/datadissect-azure@1375188840:pull_request
#
# The name-based form (repo:owner/name:ref) is the legacy format and silently
# fails against a repo issuing immutable claims — AADSTS700213, "no matching
# federated identity record". Numeric IDs cannot be re-registered, so deleting a
# repo and reclaiming the name cannot be used to assume this identity.
locals {
  gh_owner = split("/", var.github_repo)[0]
  gh_name  = split("/", var.github_repo)[1]
  gh_sub   = "repo:${local.gh_owner}@${var.github_owner_id}/${local.gh_name}@${var.github_repo_id}"
}

# A user-assigned managed identity rather than an app registration: creating one
# is an ARM operation, so it needs no Entra directory privileges. That matters
# here because my account is a guest (#EXT#) in this tenant.
resource "azurerm_user_assigned_identity" "ci" {
  name                = "${var.prefix}-ci"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
}

# The SUBJECT is the security boundary. Entra will only exchange a token whose
# claims match exactly — a different repo, or a different branch, gets nothing.
resource "azurerm_federated_identity_credential" "main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.gh_sub}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "pull_request" {
  name                      = "github-pr"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.gh_sub}:pull_request"
}

# What CI may do. Contributor at subscription scope is broad — appropriate for a
# config that creates resource groups, too broad for a mature setup, where you
# would scope to the resource group and grant only what the config touches.
resource "azurerm_role_assignment" "ci_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

# CI must read and write the state blob — data plane, separate from the above.
resource "azurerm_role_assignment" "ci_state" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/ddaz-tfstate-rg/providers/Microsoft.Storage/storageAccounts/${var.state_storage_account}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

# ── Unity Catalog access for CI ──────────────────────────────────────────────
# Azure RBAC and Unity Catalog are SEPARATE governance planes.
#
#   Azure RBAC      governs resources — the workspace, the storage account.
#   Unity Catalog   governs data objects — credentials, external locations,
#                   catalogs, tables. Its own owners, its own grants.
#
# The CI identity is Contributor on the whole subscription and still cannot
# read a storage credential, because Contributor is not a Unity Catalog
# privilege. Terraform plan fails with "User does not have any privileges on
# Credential". Azure Owner ≠ metastore admin.
#
# So the CI identity has to exist as a Databricks principal in its own right.

# NOT a resource. Azure Databricks auto-provisions a service principal the
# first time an Azure identity authenticates to the workspace — which the CI
# identity already did during a failed run. Databricks owns that object's
# lifecycle, so Terraform reads it rather than trying to create it.
data "databricks_service_principal" "ci" {
  application_id = azurerm_user_assigned_identity.ci.client_id
}

data "databricks_group" "admins" {
  display_name = "admins"
}

# Workspace admin is broad — appropriate for an identity whose whole job is
# managing this workspace's Unity Catalog objects, too broad for a pipeline
# identity that only needs to read a table. Production would grant specific
# privileges on specific securables instead.
resource "databricks_group_member" "ci_admin" {
  group_id  = data.databricks_group.admins.id
  member_id = data.databricks_service_principal.ci.sp_id
}
