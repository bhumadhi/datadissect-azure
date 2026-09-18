# Teardown and cost

## Stopping for the day

```bash
cd terraform
terraform destroy          # shows a plan of everything to remove, then asks
```

Everything in this project lives in one resource group plus the Databricks
managed resource group, and Terraform removes both. That is the entire reason
this is in code rather than clicked together — teardown is one command that
actually finds everything, including resources you forgot existed.

To bring it back: `terraform apply`. Same infrastructure, new random suffix on
the storage account. Data in the lake is NOT recreated — re-upload it.

## What actually costs money

| Resource | Rate | Notes |
|---|---|---|
| NAT gateway | ~$0.045/hr (~$1/day) | the expensive one; required for secure cluster connectivity |
| Private endpoint | ~$0.01/hr | |
| Public IP (standard) | ~$0.005/hr | |
| Private DNS zone | ~$0.50/mo | |
| Storage | pennies at this volume | |
| Databricks **workspace** | **$0** | you pay for clusters, not the workspace |
| Job cluster (single node) | ~$0.50/hr while alive | DBUs + VM; self-terminates |

Idle cost is roughly **$1.30/day**. A pipeline run adds about **5 cents**.

## Destroying selectively

To keep the lake but drop the expensive networking:

```bash
terraform destroy -target=azurerm_nat_gateway.dbx \
                  -target=azurerm_private_endpoint.lake_dfs
```

`-target` is a debugging tool, not a workflow. It skips dependency analysis, so
overusing it leaves state inconsistent with reality. Fine for cost control on a
learning project; avoid it in a real pipeline.

## Checking spend

```bash
az consumption usage list --top 10 \
  --query "[].{date:usageStart, meter:meterName, cost:pretaxCost}" -o table
```

Usage data lags 8–24 hours, so this won't show a cluster you started an hour
ago. The budget alert configured in `budget.tf` is the real safety net.
