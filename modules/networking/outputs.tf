output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.main.id
}

output "instance_sg_id" {
  value = aws_security_group.instance.id
}

output "vpn_clients_sg_id" {
  value = aws_security_group.vpn_clients.id
}
