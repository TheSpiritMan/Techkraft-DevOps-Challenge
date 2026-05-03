output "alb_dns" {
  value = aws_lb.this.dns_name
}

output "app_sg_id" {
  value = aws_security_group.app.id
}