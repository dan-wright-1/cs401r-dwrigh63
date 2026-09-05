variable "project" {
  description = "Project name, used as the first element of every resource name"
  type        = string
  default     = "northstar"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}
