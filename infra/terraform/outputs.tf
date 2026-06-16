output "instance_public_ip" {
  description = "IP publique de l'instance EC2"
  value       = aws_instance.yokozuna_serverweb.public_ip
}

output "instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.yokozuna_serverweb.id
}

output "subnet_id" {
  description = "ID du subnet"
  value       = aws_subnet.yokozuna_subnet.id
}

output "security_group_id" {
  description = "ID du security group"
  value       = aws_security_group.yokozuna_sg.id
}
