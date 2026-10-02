output "ml_engineer_role_arn" {
  description = "ARN of the MLEngineer role — later labs pass this to SageMaker"
  value       = aws_iam_role.ml_engineer.arn
}

output "data_engineer_role_arn" {
  description = "ARN of the DataEngineer role (Glue crawler and jobs, Feature Group execution role)"
  value       = aws_iam_role.data_engineer.arn

  # Consumers (the Feature Group, Glue jobs) validate the role's permissions
  # when they are created. Hand out the ARN only once the policy is attached,
  # or a fresh apply can race it and fail with "Invalid S3Uri provided".
  depends_on = [aws_iam_role_policy_attachment.data_engineer]
}

output "model_monitor_role_arn" {
  description = "ARN of the ModelMonitor role"
  value       = aws_iam_role.model_monitor.arn
}
