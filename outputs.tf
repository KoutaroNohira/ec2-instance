output "instance_public_ip" {
  description = "EC2 instance's public ip address"
  value       = aws_eip.web[*].public_ip
}

output "instance_private_ip" {
  description = "EC2 instance's private ip address"
  value       = aws_instance.web[*].private_ip
}

output "alb_dns" {
  value = aws_lb.alb.dns_name
}
