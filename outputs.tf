###############################################################################
# Primary outputs (id + arn)
###############################################################################

output "id" {
 description = "The ID of the launch template (lt-...). Consumed by Auto Scaling groups, EC2 fleets, and aws_instance launch_template references."
 value = aws_launch_template.this.id
}

output "arn" {
 description = <<EOT
The ARN of the launch template (cross-resource reference type:
arn:aws:ec2:<region>:<account>:launch-template/lt-...). Consumed by IAM policies and
resource-level permissions.
EOT
 value = aws_launch_template.this.arn
}

###############################################################################
# Key computed attributes
###############################################################################

output "name" {
 description = "The name of the launch template (explicit, prefix-generated, or AWS auto-generated). Consumed by ASG/fleet references that target the template by name."
 value = aws_launch_template.this.name
}

output "latest_version" {
 description = "The latest version number of the launch template. Increments on every change. Reference \"$Latest\" in consumers to always track this, or pin a specific number."
 value = aws_launch_template.this.latest_version
}

output "default_version" {
 description = "The default version number of the launch template. Consumers that reference \"$Default\" resolve to this version."
 value = aws_launch_template.this.default_version
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the launch template, including those inherited from provider default_tags (resource tags win on key conflict). Note: default_tags are NOT propagated to instances launched from the template — see the propagate_tags input."
 value = aws_launch_template.this.tags_all
}
