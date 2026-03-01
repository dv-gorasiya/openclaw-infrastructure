data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

resource "aws_launch_template" "main" {
  name_prefix   = "openclaw-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  vpc_security_group_ids = [var.instance_sg_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = false
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region               = data.aws_region.current.name
    secrets_manager_name = var.secrets_manager_name
    ebs_volume_id        = var.ebs_volume_id
    gateway_port         = var.openclaw_ports.gateway
    browser_port         = var.openclaw_ports.browser_control
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 15
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "openclaw-instance" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "openclaw-root-volume" })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "openclaw-launch-template" })
}

resource "aws_autoscaling_group" "main" {
  name                = "openclaw-asg"
  vpc_zone_identifier = [var.subnet_id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      instance_warmup        = 300
    }
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "openclaw-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

data "aws_instances" "openclaw" {
  filter {
    name   = "tag:Name"
    values = ["openclaw-instance"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "pending"]
  }

  depends_on = [aws_autoscaling_group.main]
}
