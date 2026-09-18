variable "subscription_id" {
  description = "Azure subscription ID (get it from: az account show --query id -o tsv)"
  type        = string
}

variable "location" {
  description = "Azure region. Pick one near you — eastus2 and westus2 have the widest Databricks support."
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Short prefix for resource names. Lowercase letters/numbers only, <= 10 chars."
  type        = string
  default     = "ddaz"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase letters or digits."
  }
}

variable "alert_email" {
  description = "Email for budget alerts. Use the address you actually read."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget ceiling in USD. Alerts fire against this; it does not cap spend."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "Budget period start. Must be the FIRST day of a month, UTC."
  type        = string
  default     = "2026-09-01T00:00:00Z"
}

variable "github_repo" {
  description = "owner/repo that CI runs from. Scopes the federated credential — no other repo can assume this identity."
  type        = string
  default     = "bhumadhi/datadissect-azure"
}

variable "state_storage_account" {
  description = "Storage account holding Terraform state. CI needs data-plane access to it."
  type        = string
}
