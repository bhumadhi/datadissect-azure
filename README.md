# datadissect-azure

Porting a slice of [DataDissect](https://github.com/bhumadhi/datadissect) onto **Azure
Databricks**, provisioned entirely with **Terraform**.

The point isn't the pipeline — that part I already know. The point is the platform
underneath it: ADLS Gen2, managed identity, Unity Catalog, and infrastructure as code.

---

## Why this project, specifically

DataDissect runs on MinIO + local Spark + a file-based metastore. Every one of those has
an Azure counterpart, and the counterparts are exactly where my gaps are:

| DataDissect (local) | Azure | What's genuinely new |
|---|---|---|
| MinIO buckets | ADLS Gen2 filesystems | `abfss://` driver, **not** `s3a://` |
| `.env` credentials | Managed identity | No secret on disk at all |
| Docker Compose | Terraform | Declarative cloud provisioning + state |
| Trino file metastore | Unity Catalog | Storage credential → external location → grants |
| `spark-submit` local | Databricks job cluster | Ephemeral compute, per-run |

Delta Lake, PySpark and the medallion layout carry over unchanged. That's the half I
don't need to relearn.

---

## Definition of done

My resume currently carries this line:

> **Currently developing:** Azure Databricks, ADLS Gen2, Unity Catalog, Terraform

This project is finished when that line can be deleted and its contents moved up into
the real skills section — because I will have built each of them, not read about them.

### Coverage against the job description

| JD requirement | Phase | Covered by |
|---|---|---|
| ADLS Gen2 | 1 | Storage account with `is_hns_enabled`, three medallion filesystems |
| Terraform / Bicep | 1–7 | Every resource here is provisioned in code; nothing clicked in a portal |
| Managed identities | 2 | Databricks Access Connector + `Storage Blob Data Contributor` role assignment |
| Azure networking | 3 | VNet, subnet, and a **private endpoint** on the storage account |
| Azure Databricks | 4 | Workspace provisioned by Terraform |
| Unity Catalog | 5 | Storage credential → external location → catalog → schema → `GRANT` |
| PySpark on Databricks | 6 | Claims CSV → Delta table, run on an ephemeral **job cluster** |
| GitHub Actions CI/CD | 7 | `terraform plan` on PR, `apply` on merge |
| Healthcare data | all | X12 837P claims schema, carried over from DataDissect |

---

## Phases

Each phase is one `terraform apply` and one concept. Don't skip ahead — phase 2 is the
one that matters most and only makes sense after 1.

- **0 — Tooling.** `az`, `terraform`, `databricks` CLIs. ✅ done
- **1 — Landing zone.** ✅ Resource group + ADLS Gen2 + raw/cleansed/curated filesystems.
  Teaches: Terraform provider/resource/state/plan/apply, and what `is_hns_enabled`
  actually changes.
- **2 — Identity.** ✅ Databricks Access Connector (a managed identity) + an RBAC role
  assignment. **The Kerberos analogy** — a keytab is a credential file you distribute,
  protect and rotate; a managed identity is Azure holding it and compute fetching a
  short-lived token. Same problem, no file on disk. Also the same idea as an AWS EC2
  instance profile.
- **3 — Networking.** ✅ VNet + subnet + a private endpoint on the storage account, so the
  lake is reachable privately rather than over its public endpoint. This is the
  "networking and security controls" line in the JD.
- **4 — Databricks workspace.** ✅ Provisioned by Terraform, not clicked in a portal.
- **5 — Unity Catalog.** ✅ storage credential → external location → catalog → schema →
  `GRANT`. Replaces the Hive Metastore + Ranger model.
- **6 — The pipeline.** Upload synthetic 837P claims to `raw`, read via `abfss://`,
  write a Delta table registered in Unity Catalog, run it on a **job cluster**.
- **7 — CI/CD.** GitHub Actions running `terraform plan` on pull request and `apply` on
  merge, authenticating with an Entra service principal (OIDC, no stored secret).
- **8 — `terraform destroy`.** Not optional. See cost.

---

## 💸 Cost — read this before phase 1

The Azure free account gives **$200 of credit for 30 days**. Databricks bills **DBUs on
top of the VM compute**, so a cluster left running overnight is the standard way people
burn a trial.

Rules for this project:

1. **`terraform destroy` when you stop for the day.** That is the whole reason this is
   in Terraform rather than clicked together by hand — teardown is one command and it
   actually removes everything.
2. **Use job clusters, not all-purpose clusters.** A job cluster starts, runs, and
   terminates. An all-purpose cluster runs until you notice it.
3. **Set auto-termination** on anything interactive. 10 minutes.
4. Check spend: `az consumption usage list --top 5` or the portal's Cost Management blade.

Storage itself is pennies. Compute is what costs money.

---

## Navigating Terraform

Four commands, and you'll use them in this order every time:

```bash
terraform init      # download providers — once per project, or after changing versions
terraform plan      # show me what WOULD change. Read this. Always.
terraform apply     # make it so (prompts for confirmation)
terraform destroy   # remove everything this config created
```

The mental model that makes it click:

- **Config** (`*.tf`) is the desired state you wrote.
- **State** (`terraform.tfstate`) is Terraform's record of what it actually created.
- **`plan`** diffs those two against the real cloud, and shows the delta.

State is the part people get wrong. It contains resource IDs and sometimes secrets — it
is **gitignored here and should never be committed**. In a team you'd put it in a remote
backend (an Azure storage account with locking), which is itself a good interview answer
to "how do you manage Terraform state across a team?"

`plan` before `apply`, every time. It's the equivalent of reading a migration before
running it against prod.

---

## Layout

```
terraform/     infrastructure as code — the actual subject of this project
scripts/       local Python helpers (synthetic data, uploads)
notebooks/     PySpark that runs ON Databricks
data/          generated sample claims (gitignored)
docs/concepts/ notes per concept, same discipline as DataDissect's ADRs
```

Python is thin here on purpose — see `requirements.txt`.
