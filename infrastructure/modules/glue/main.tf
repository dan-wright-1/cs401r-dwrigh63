# ── modules/glue ─────────────────────────────────────────────────────────────
# Lab 2 data pipeline (Tasks 2 and 3). Only these belong in this module:
#
#   aws_glue_catalog_database        <project>_<environment>
#   aws_glue_connection              NETWORK: puts job workers in the private subnet
#   aws_glue_crawler                 raw/customers/ -> catalog table "customers"
#   aws_s3_object                    job scripts uploaded to artifacts/glue/
#   aws_glue_job                     transform (Task 2), feature-engineer (Task 3)
#
# Every job and crawler runs as the DataEngineer role passed in from
# modules/iam; nothing here creates IAM.

data "aws_region" "current" {}

locals {
  prefix = "${var.project}-${var.environment}"

  # Glue catalog names allow only lowercase letters, digits, and underscores.
  database_name = replace(lower("${var.project}_${var.environment}"), "-", "_")

  bucket_uri  = "s3://${var.bucket_name}"
  scripts_key = trimsuffix(var.scripts_prefix, "/")
}

resource "aws_glue_catalog_database" "this" {
  name        = local.database_name
  description = "${var.project} ${var.environment} data catalog - raw and processed customer data"
}

# ── Network connection ───────────────────────────────────────────────────────
# A NETWORK connection is how a Glue job gets ENIs in our VPC. Three things
# must already be true or the job fails at provisioning, before the script
# runs: the role has glue:GetConnection, the security group has a
# self-referencing all-ports ingress rule, and the role may tag ENIs. All
# three are handled in modules/iam and modules/vpc. The subnet reaches S3 and
# the Glue APIs through the NAT Gateway.

resource "aws_glue_connection" "network" {
  name            = "${local.prefix}-network"
  description     = "Places Glue job workers in the private subnet"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = var.availability_zone
    subnet_id              = var.subnet_id
    security_group_id_list = [var.security_group_id]
  }
}

# ── Crawler ──────────────────────────────────────────────────────────────────
# Targets raw/customers/ (not raw/) so the table is named after that prefix:
# "customers", not "raw_customers". On-demand only (no schedule).

resource "aws_glue_crawler" "raw" {
  name          = "${local.prefix}-raw-crawler"
  description   = "Discovers the schema of raw customer transaction CSVs"
  database_name = aws_glue_catalog_database.this.name
  role          = var.data_engineer_role_arn

  s3_target {
    path = "${local.bucket_uri}/${var.raw_prefix}"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# ── Job scripts ──────────────────────────────────────────────────────────────
# Uploaded on every apply; etag makes Terraform re-upload when the local file
# changes, so editing transform.py and re-applying is enough to deploy it.

resource "aws_s3_object" "transform_script" {
  bucket = var.bucket_name
  key    = "${local.scripts_key}/${var.transform_script_name}"
  source = "${var.scripts_dir}/${var.transform_script_name}"
  etag   = filemd5("${var.scripts_dir}/${var.transform_script_name}")
}

# ── Transform job (Task 2) ───────────────────────────────────────────────────
# raw/customers/ (via the catalog) -> processed/customers/ as Parquet.

resource "aws_glue_job" "transform" {
  name              = "${local.prefix}-transform"
  description       = "Type casting, null imputation, dedup: raw/customers -> processed/customers"
  role_arn          = var.data_engineer_role_arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.job_timeout_minutes
  max_retries       = 0
  connections       = [aws_glue_connection.network.name]

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "${local.bucket_uri}/${aws_s3_object.transform_script.key}"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--database_name"                    = aws_glue_catalog_database.this.name
    "--table_name"                       = var.raw_table_name
    "--output_path"                      = "${local.bucket_uri}/${var.processed_prefix}"
  }

  execution_property {
    max_concurrent_runs = 1
  }
}

# ── Feature engineering job (Task 3) ────────────────────────────────────────
# processed/customers/ -> features/customers/ (Parquet) + Feature Store
# PutRecord. Same role, network connection, and sizing as the transform job.
# PutRecord goes to the SageMaker Feature Store runtime endpoint, reached from
# the private subnet through the NAT Gateway.

resource "aws_s3_object" "feature_script" {
  bucket = var.bucket_name
  key    = "${local.scripts_key}/${var.feature_script_name}"
  source = "${var.scripts_dir}/${var.feature_script_name}"
  etag   = filemd5("${var.scripts_dir}/${var.feature_script_name}")
}

resource "aws_glue_job" "feature_engineer" {
  name              = "${local.prefix}-feature-engineer"
  description       = "RFM features, loyalty tier, churn proxy and label: processed/customers -> features/customers + Feature Store"
  role_arn          = var.data_engineer_role_arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.job_timeout_minutes
  max_retries       = 0
  connections       = [aws_glue_connection.network.name]

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "${local.bucket_uri}/${aws_s3_object.feature_script.key}"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--input_path"                       = "${local.bucket_uri}/${var.processed_prefix}"
    "--output_path"                      = "${local.bucket_uri}/${var.features_prefix}"
    "--feature_group_name"               = var.feature_group_name
    "--region"                           = data.aws_region.current.name
  }

  execution_property {
    max_concurrent_runs = 1
  }
}
