# Surface what later labs need. Lab 2 reads these from `terraform output`.

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet (SageMaker Domain, Glue workers)"
  value       = module.vpc.private_subnet_id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = module.vpc.nat_gateway_id
}

output "security_group_id" {
  description = "ID of the SageMaker / Glue security group"
  value       = module.vpc.security_group_id
}

output "sagemaker_domain_id" {
  description = "ID of the SageMaker Domain"
  value       = module.sagemaker.domain_id
}

output "s3_bucket_name" {
  description = "Name of the data bucket"
  value       = module.storage.bucket_name
}

output "ml_engineer_role_arn" {
  description = "ARN of the MLEngineer role"
  value       = module.iam.ml_engineer_role_arn
}

output "data_engineer_role_arn" {
  description = "ARN of the DataEngineer role"
  value       = module.iam.data_engineer_role_arn
}

output "model_monitor_role_arn" {
  description = "ARN of the ModelMonitor role"
  value       = module.iam.model_monitor_role_arn
}
