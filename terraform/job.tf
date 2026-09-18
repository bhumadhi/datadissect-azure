# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6 — The pipeline, as a Databricks job on an ephemeral job cluster.
#
# Terraform DECLARES the job. Databricks EXECUTES it. That's the boundary —
# the same one that separates Terraform from Airflow.
# ─────────────────────────────────────────────────────────────────────────────

# Ask the workspace what's available rather than hardcoding — node type
# availability differs by region and SKUs get retired.
data "databricks_spark_version" "lts" {
  long_term_support = true
}

data "databricks_node_type" "smallest" {
  local_disk = true
  min_cores  = 4
  category   = "General Purpose"
}

resource "databricks_notebook" "medallion" {
  source   = "${path.module}/../notebooks/claims_medallion.py"
  path     = "/Shared/datadissect/claims_medallion"
  language = "PYTHON"
}

resource "databricks_job" "medallion" {
  name        = "${var.prefix}-claims-medallion"
  description = "837P claims: bronze -> silver -> gold, into Unity Catalog"

  task {
    task_key = "run_medallion"

    notebook_task {
      notebook_path = databricks_notebook.medallion.path
    }

    # A JOB CLUSTER: created for this run, terminated when it ends. You pay for
    # the minutes it lives. An all-purpose cluster runs until someone notices —
    # which is how people burn a trial.
    new_cluster {
      spark_version = data.databricks_spark_version.lts.id
      node_type_id  = data.databricks_node_type.smallest.id
      num_workers   = 0 # single node: driver only, cheapest thing that runs

      # Unity Catalog requires SINGLE_USER or USER_ISOLATION. The legacy
      # no-isolation mode cannot see UC tables at all.
      data_security_mode = "SINGLE_USER"

      spark_conf = {
        "spark.databricks.cluster.profile" = "singleNode"
        "spark.master"                     = "local[*]"
      }

      custom_tags = {
        ResourceClass = "SingleNode"
        project       = "datadissect-azure"
      }
    }
  }

  # No schedule. Triggered by hand, like DataDissect's event-driven DAG —
  # claims files don't arrive on a timetable.
}
