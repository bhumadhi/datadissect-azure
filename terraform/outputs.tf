output "resource_group" {
  description = "Resource group holding everything in this project."
  value       = azurerm_resource_group.rg.name
}

output "storage_account" {
  description = "ADLS Gen2 storage account name."
  value       = azurerm_storage_account.lake.name
}

output "abfss_paths" {
  description = "The abfss:// URIs Spark will read and write. Note: abfss, NOT s3a."
  value = {
    for z in azurerm_storage_data_lake_gen2_filesystem.zones :
    z.name => "abfss://${z.name}@${azurerm_storage_account.lake.name}.dfs.core.windows.net/"
  }
}

output "access_connector_id" {
  description = "Resource ID of the Databricks Access Connector — Unity Catalog needs this in phase 5."
  value       = azurerm_databricks_access_connector.uc.id
}

output "access_connector_principal_id" {
  description = "The managed identity's object ID in Entra. This is the 'who' in the role assignment."
  value       = azurerm_databricks_access_connector.uc.identity[0].principal_id
}

output "private_endpoint_ip" {
  description = "Private IP the storage account now answers on inside the VNet."
  value       = azurerm_private_endpoint.lake_dfs.private_service_connection[0].private_ip_address
}

output "databricks_subnets" {
  description = "Delegated subnets the workspace will be injected into (phase 4)."
  value = {
    host      = azurerm_subnet.databricks_host.name
    container = azurerm_subnet.databricks_container.name
  }
}

output "databricks_workspace_url" {
  description = "Open this in a browser to reach the workspace."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "databricks_workspace_id" {
  description = "Resource ID — the databricks Terraform provider authenticates against this in phase 5."
  value       = azurerm_databricks_workspace.this.id
}

output "nat_egress_ip" {
  description = "Single outbound IP all cluster traffic leaves from. This is what you'd give a partner to allowlist."
  value       = azurerm_public_ip.nat.ip_address
}

output "ci_client_id" {
  description = "Set as GitHub variable AZURE_CLIENT_ID. Not a secret — it is an identifier, useless without a matching OIDC token."
  value       = azurerm_user_assigned_identity.ci.client_id
}
