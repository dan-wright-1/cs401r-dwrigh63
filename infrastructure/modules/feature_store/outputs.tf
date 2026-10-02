output "feature_group_name" {
  description = "Name of the customer feature group (passed to the feature engineering job)"
  value       = aws_sagemaker_feature_group.customer.feature_group_name
}

output "feature_group_arn" {
  description = "ARN of the customer feature group"
  value       = aws_sagemaker_feature_group.customer.arn
}

output "offline_store_uri" {
  description = "S3 URI the offline store writes under"
  value       = "s3://${var.bucket_name}/${var.offline_store_prefix}"
}
