output "launch_template_id" {
  value = aws_launch_template.main.id
}

output "asg_name" {
  value = aws_autoscaling_group.main.name
}

output "instance_id" {
  value = length(data.aws_instances.openclaw.ids) > 0 ? data.aws_instances.openclaw.ids[0] : ""
}

output "instance_private_ip" {
  value = length(data.aws_instances.openclaw.private_ips) > 0 ? data.aws_instances.openclaw.private_ips[0] : ""
}

output "ami_id" {
  value = data.aws_ami.ubuntu.id
}
