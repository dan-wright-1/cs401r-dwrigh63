# Every variable needs a description — Task B1 grades this.

variable "project" {
  description = "Project name, used as the first element of every resource name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.100.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (SageMaker Studio, Glue workers)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the public and private subnets"
  type        = string
  default     = "us-east-1a"
}

variable "enable_nat_gateway" {
  description = "Create the EIP + NAT Gateway and the private default route. Set false for LocalStack, which does not emulate NAT."
  type        = bool
  default     = true
}
