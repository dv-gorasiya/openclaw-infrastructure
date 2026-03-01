data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "openclaw-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "openclaw-igw" })
}

# Public subnet with IGW route. Security is enforced at the SG level
# (no inbound rules) rather than via NAT Gateway, saving ~$32/month.
# Access is only possible through Tailscale VPN or SSM Session Manager.
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "openclaw-subnet" })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "openclaw-rt" })
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Instance SG — no inbound rules by default. Tailscale and SSM use
# outbound connections so the instance is not reachable from the internet.
resource "aws_security_group" "instance" {
  name        = "openclaw-instance-sg"
  description = "Security group for OpenClaw instance"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "openclaw-instance-sg" })
}

resource "aws_security_group" "vpn_clients" {
  name        = "openclaw-vpn-clients-sg"
  description = "Source group for VPN clients accessing OpenClaw"
  vpc_id      = aws_vpc.main.id
  tags        = merge(var.tags, { Name = "openclaw-vpn-clients-sg" })
}

resource "aws_security_group_rule" "gateway_from_vpn" {
  type                     = "ingress"
  from_port                = var.openclaw_ports.gateway
  to_port                  = var.openclaw_ports.gateway
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpn_clients.id
  security_group_id        = aws_security_group.instance.id
  description              = "OpenClaw Gateway from VPN"
}

resource "aws_security_group_rule" "browser_from_vpn" {
  type                     = "ingress"
  from_port                = var.openclaw_ports.browser_control
  to_port                  = var.openclaw_ports.browser_control
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpn_clients.id
  security_group_id        = aws_security_group.instance.id
  description              = "Browser Control from VPN"
}

# S3 Gateway Endpoint (free — avoids data transfer charges for S3 access)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.main.id]

  tags = merge(var.tags, { Name = "openclaw-s3-endpoint" })
}
