# ── modules/feature_store ────────────────────────────────────────────────────
# Lab 2 Task 3. Only this belongs in this module:
#
#   aws_sagemaker_feature_group      <project>-<environment>-customer-features
#
# One labeled row per customer: 2 keys (customer_id, event_time), 13 features,
# 1 label. The feature engineering Glue job writes records with PutRecord;
# Labs 3-4 read them for training.
#
# Two apply-time traps, both caused by the execution role, not by this file:
#   "The execution role ARN is invalid" -> role must trust sagemaker.amazonaws.com
#   "Invalid S3Uri provided"            -> role needs s3:GetBucketAcl on the bucket
# Both are handled in modules/iam (DataEngineer).

resource "aws_sagemaker_feature_group" "customer" {
  feature_group_name             = "${var.project}-${var.environment}-${var.feature_group_suffix}"
  description                    = "Customer churn features (observation window) and churn_label (outcome window)"
  record_identifier_feature_name = var.record_identifier_name
  event_time_feature_name        = var.event_time_feature_name
  role_arn                       = var.execution_role_arn

  # event_time MUST be Fractional (epoch seconds), matching what the job sends.
  # On a type mismatch PutRecord rejects the call with a ValidationError naming
  # the feature, and the feature engineering job fails at the ingest step.
  dynamic "feature_definition" {
    for_each = var.feature_definitions
    content {
      feature_name = feature_definition.value.name
      feature_type = feature_definition.value.type
    }
  }

  online_store_config {
    enable_online_store = true
  }

  # Its own prefix, separate from the job's features/customers/ Parquet: the
  # offline store builds its own <account>/sagemaker/<region>/offline-store/...
  # tree under whatever URI it is given.
  offline_store_config {
    s3_storage_config {
      s3_uri = "s3://${var.bucket_name}/${var.offline_store_prefix}"
    }
  }

  tags = {
    Name = "${var.project}-${var.environment}-${var.feature_group_suffix}"
  }
}
