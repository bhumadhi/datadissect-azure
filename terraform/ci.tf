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
  subject                   = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "pull_request" {
  name                      = "github-pr"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_repo}:pull_request"
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
