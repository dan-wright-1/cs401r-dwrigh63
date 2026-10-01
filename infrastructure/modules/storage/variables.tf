# Every variable needs a description — Task B1 grades this.

variable "project" {
  description = "Project name, used as the first element of every resource name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "prefixes" {
  description = "Top-level S3 prefixes to create in the data bucket"
  type        = list(string)
  default     = ["raw/", "processed/", "features/", "artifacts/"]
}

variable "enable_lifecycle_rules" {
  description = "Create the five S3 lifecycle rules. Set false for LocalStack."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Let terraform destroy delete a non-empty, versioned bucket (every object version). Only for regenerable dev/lab data."
  type        = bool
  default     = false
}
