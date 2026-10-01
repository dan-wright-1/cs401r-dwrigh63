# Downstream modules and environments/dev/main.tf consume these.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "private_subnet_availability_zone" {
  description = "AZ of the private subnet (a Glue NETWORK connection must name it)"
  value       = aws_subnet.private.availability_zone
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway, or null when enable_nat_gateway = false"
  value       = var.enable_nat_gateway ? aws_nat_gateway.this[0].id : null
}

output "security_group_id" {
  description = "ID of the default security group"
  value       = aws_security_group.this.id
}
