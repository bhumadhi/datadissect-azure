# ─────────────────────────────────────────────────────────────────────────────
# Cost guardrail.
#
# This does NOT cap spending — Azure budgets are alerting, not enforcement.
# It emails you when actual spend crosses a threshold, and again when the
# FORECAST says you're heading past one. The forecast alert is the useful one:
# it fires while you still have time to run `terraform destroy`.
#
# Cost control belongs in the platform definition, not in someone's memory.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_consumption_budget_subscription" "guard" {
  name            = "${var.prefix}-budget"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  # Actual spend crossed half the ceiling.
  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  # Projected to cross 80% — fires early, while you can still act.
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }
}
