output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "app_sg_id" {
  value = aws_security_group.ec2_sg.id
}
