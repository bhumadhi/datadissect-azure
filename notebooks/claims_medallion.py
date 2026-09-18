# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# Claims medallion pipeline — the DataDissect flow, on Azure Databricks.
#
# Local original          →  here
#   MinIO s3a://          →  ADLS Gen2 abfss://
#   .env credentials      →  managed identity (nothing in this file)
#   file-based metastore  →  Unity Catalog  catalog.schema.table
#   spark-submit          →  job cluster
#
# The PySpark itself is essentially unchanged. That was the point.
# ─────────────────────────────────────────────────────────────────────────────

from pyspark.sql import functions as F

CATALOG = "claims"
RAW = "abfss://raw@ddazlake138l8x.dfs.core.windows.net"
SRC = f"{RAW}/BCBS001/837P/PROD/20260312_001/"

spark.sql(f"USE CATALOG {CATALOG}")

# COMMAND ----------
# BRONZE — land as-is, add provenance. No cleaning, no judgement.
# Note there is no credential anywhere below. The cluster's managed identity
# gets a token from the platform; Unity Catalog checks the grant on the
# external location. A key never enters this code.

bronze = (
    spark.read
    .option("header", True)
    .option("inferSchema", True)
    .csv(SRC)
    .withColumn("_ingested_at", F.current_timestamp())
    .withColumn("_source_file", F.input_file_name())
)

bronze.write.mode("overwrite").saveAsTable("bronze.claims_raw")
print(f"bronze.claims_raw: {bronze.count():,} rows")

# COMMAND ----------
# SILVER — validate and de-identify.
# SHA-256 on member_id and provider_npi, originals dropped. One-way but
# deterministic, so a member still joins across files after masking.
# Production adds a salt held in Key Vault to defeat rainbow tables.

silver = (
    spark.table("bronze.claims_raw")
    .filter(F.col("claim_id").isNotNull())
    .filter(F.col("billed_amount") > 0)
    .withColumn("member_id_hash", F.sha2(F.col("member_id"), 256))
    .withColumn("provider_npi_hash", F.sha2(F.col("provider_npi"), 256))
    .drop("member_id", "provider_npi")
    .withColumn("service_date", F.to_date("service_date"))
)

silver.write.mode("overwrite").saveAsTable("silver.claims_cleansed")

rejected = spark.table("bronze.claims_raw").count() - silver.count()
print(f"silver.claims_cleansed: {silver.count():,} rows ({rejected} rejected)")

# COMMAND ----------
# GOLD — curated summaries, the same three DataDissect produces.

(
    spark.table("silver.claims_cleansed")
    .groupBy("member_id_hash")
    .agg(
        F.count("*").alias("total_claims"),
        F.sum("billed_amount").alias("total_billed"),
        F.countDistinct("provider_npi_hash").alias("distinct_providers"),
    )
    .write.mode("overwrite").saveAsTable("gold.member_summary")
)

(
    spark.table("silver.claims_cleansed")
    .groupBy("payer_id")
    .agg(
        F.count("*").alias("total_claims"),
        F.sum("billed_amount").alias("total_billed"),
        F.avg("billed_amount").alias("avg_billed"),
    )
    .write.mode("overwrite").saveAsTable("gold.payer_summary")
)

print("gold.member_summary and gold.payer_summary written")

# COMMAND ----------
# Proof: these are Delta tables governed by Unity Catalog, not files on a path.
display(spark.sql("SELECT payer_id, total_claims, ROUND(total_billed,2) AS total_billed FROM gold.payer_summary ORDER BY total_billed DESC"))
