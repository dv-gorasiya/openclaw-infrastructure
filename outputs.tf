output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.networking.subnet_id
}

output "instance_id" {
  description = "ID of the OpenClaw EC2 instance"
  value       = module.compute.instance_id
}

output "instance_private_ip" {
  description = "Private IP address of the OpenClaw instance"
  value       = module.compute.instance_private_ip
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.asg_name
}

output "secrets_manager_name" {
  description = "Name of the Secrets Manager secret"
  value       = module.security.secrets_manager_name
}

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = module.security.secrets_manager_arn
  sensitive   = true
}

output "gateway_token" {
  description = "Generated gateway token for OpenClaw"
  value       = module.security.gateway_token
  sensitive   = true
}

output "ebs_volume_id" {
  description = "ID of the OpenClaw data EBS volume"
  value       = module.storage.ebs_volume_id
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = module.storage.backup_plan_id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = module.monitoring.sns_topic_arn
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "connection_info" {
  description = "How to connect to OpenClaw after deployment"
  sensitive   = true
  value       = <<-EOT

    Instance: ${module.compute.instance_id}
    Private IP: ${module.compute.instance_private_ip}

    Connect via SSM:
      aws ssm start-session --target ${module.compute.instance_id}

    After Tailscale joins your tailnet:
      http://<tailscale-ip>:${var.openclaw_ports.gateway}

    Update secrets:
      ./scripts/update-secrets.sh

    Dashboard:
      ${module.monitoring.dashboard_url}
  EOT
}
