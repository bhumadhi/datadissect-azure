# Pins the providers. Terraform downloads these on `terraform init` and records
# exact versions in .terraform.lock.hcl so every run uses the same code.
terraform {
  required_version = ">= 1.5"

  # REMOTE STATE.
  # Local state is a single file on one laptop: no locking, no history, and
  # invisible to CI. This moves it to blob storage with versioning (recover a
  # bad apply) and native blob leases for locking (two applies cannot race).
  #
  # This storage lives in its own resource group, created OUTSIDE Terraform, so
  # `terraform destroy` can never delete the record of what it built.
  backend "azurerm" {
    resource_group_name  = "ddaz-tfstate-rg"
    storage_account_name = "ddaztfstate956d3d"
    container_name       = "tfstate"
    key                  = "datadissect-azure.tfstate"
    use_azuread_auth     = true # my Entra identity, not an account key
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.50"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Authenticates to the WORKSPACE using my Azure CLI login. No token to store —
# same no-credential-on-disk idea as managed identity, applied to my own session.
provider "databricks" {
  host                        = "https://${azurerm_databricks_workspace.this.workspace_url}"
  azure_workspace_resource_id = azurerm_databricks_workspace.this.id
}
