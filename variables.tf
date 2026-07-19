###############################################################################
# Identity
#
# A launch template is identified by either an explicit "name" or a "name_prefix"
# (the provider auto-generates a name when both are null). Supply exactly one. The
# name is FORCE-NEW — changing it replaces the template (and bumps any consumer that
# references it by name). Auto Scaling groups that reference the template by id keep
# working across an in-place version bump; only a name change forces a new template.
###############################################################################

variable "name" {
 description = <<EOT
Name of the launch template. FORCE-NEW — changing this destroys and recreates the
template. Mutually exclusive with name_prefix; leave both null to let AWS auto-generate
a unique name. Prefer an explicit, stable name so ASGs and instances can reference it
predictably.
EOT
 type = string
 default = null
}

variable "name_prefix" {
 description = <<EOT
Creates a unique name beginning with this prefix. FORCE-NEW. Mutually exclusive with
name. Useful for create-before-destroy flows where each revision needs a fresh,
non-colliding template name.
EOT
 type = string
 default = null

 validation {
 condition = !(var.name != null && var.name_prefix != null)
 error_message = "Set at most one of name or name_prefix (they are mutually exclusive)."
 }
}

variable "description" {
 description = "Free-text description of the launch template. Null (default) sets none."
 type = string
 default = null
}

###############################################################################
# Core launch configuration
#
# Every field here mirrors the matching launch_template argument and is optional —
# a launch template may define as much or as little of the instance spec as the
# caller wants, with the rest resolved at launch time (AMI defaults, ASG overrides,
# instance_requirements, etc.).
###############################################################################

variable "image_id" {
 description = <<EOT
AMI id to launch (ami-...), or a Systems Manager parameter reference of the form
"resolve:ssm:<parameter-name>" to resolve the AMI at launch. Null (default) leaves it
unset (the consumer must supply one). AMIs are Region-scoped. Wire from tf_mod_aws_ami.
EOT
 type = string
 default = null

 validation {
 condition = var.image_id == null || can(regex("^(ami-[0-9a-f]{8,}|resolve:ssm:.+)$", coalesce(var.image_id, "x")))
 error_message = "image_id must be an AMI id (ami-...) or a 'resolve:ssm:<parameter>' reference, or null."
 }
}

variable "instance_type" {
 description = <<EOT
EC2 instance type (e.g. "t3.micro", "m6i.large"). Null (default) leaves it unset.
Mutually exclusive with instance_requirements — set one or the other, not both.
EOT
 type = string
 default = null

 validation {
 condition = var.instance_type == null || can(regex("^[a-z0-9]+[0-9]+[a-z]*\\.[0-9a-z]+$", coalesce(var.instance_type, "x")))
 error_message = "instance_type must look like a valid EC2 instance type (e.g. 't3.micro', 'm6i.large'), or null."
 }
}

variable "key_name" {
 description = <<EOT
Name of the EC2 key pair for SSH access. Null (default) — SSM Session Manager is the
preferred, keyless access path for hosts. Wire from tf_mod_aws_key_pair when a key
pair is genuinely required.
EOT
 type = string
 default = null
}

variable "user_data" {
 description = <<EOT
Base64-encoded user data (cloud-init / shell) to run at launch. Null (default) supplies
none. The launch template stores user data already base64-encoded — pass
base64encode("...") or filebase64("$${path.module}/userdata.sh"). Do NOT place secrets
here; user data is readable from the instance metadata service.
EOT
 type = string
 default = null
}

variable "vpc_security_group_ids" {
 description = <<EOT
List of VPC security group IDs to associate with instances launched from this template
(the simple, ENI-less form). Null/empty (default) associates none here. Mutually
exclusive with per-interface security_groups inside network_interfaces — use one model
or the other. Wire from tf_mod_aws_security_group.
EOT
 type = list(string)
 default = null
}

variable "security_group_names" {
 description = <<EOT
List of EC2-Classic / default-VPC security group NAMES. Null (default) sets none. Almost
always wrong for VPC workloads — use vpc_security_group_ids (IDs) instead. Provided only
for completeness.
EOT
 type = list(string)
 default = null
}

variable "ebs_optimized" {
 description = <<EOT
Whether instances are EBS-optimized. The launch_template API models this as a STRING:
pass "true" or "false". Null (default) lets the instance type's own default apply (most
current-generation types are EBS-optimized and cannot disable it).
EOT
 type = string
 default = null

 validation {
 condition = var.ebs_optimized == null || contains(["true", "false"], coalesce(var.ebs_optimized, "null"))
 error_message = "ebs_optimized is a string and must be \"true\", \"false\", or null."
 }
}

variable "disable_api_stop" {
 description = "Enables EC2 instance stop protection on launched instances. Defaults to false. Set true to guard against accidental stop."
 type = bool
 default = false
}

variable "disable_api_termination" {
 description = "Enables EC2 instance termination protection on launched instances. Defaults to false. Set true for long-lived pets; Terraform destroy of the instance still requires the protection be cleared first."
 type = bool
 default = false
}

variable "instance_initiated_shutdown_behavior" {
 description = "Behavior on an OS-initiated shutdown: \"stop\" or \"terminate\". Null (default) uses the AWS default (\"stop\")."
 type = string
 default = null

 validation {
 condition = var.instance_initiated_shutdown_behavior == null || contains(["stop", "terminate"], coalesce(var.instance_initiated_shutdown_behavior, "stop"))
 error_message = "instance_initiated_shutdown_behavior must be one of: stop, terminate."
 }
}

variable "kernel_id" {
 description = "Kernel ID for paravirtual (PV) AMIs. Null (default) sets none. Rarely needed on modern HVM AMIs."
 type = string
 default = null
}

variable "ram_disk_id" {
 description = "RAM disk ID for paravirtual (PV) AMIs. Null (default) sets none. Rarely needed on modern HVM AMIs."
 type = string
 default = null
}

variable "default_version" {
 description = <<EOT
The template version to mark as the default. Null (default) lets AWS manage it (version
1 on create). Mutually exclusive with update_default_version. Set this to pin consumers
that reference the "$Default" version to a specific revision.
EOT
 type = number
 default = null
}

variable "update_default_version" {
 description = <<EOT
When true, every apply that creates a new template version also promotes it to the
default. Null (default) leaves the default version unmanaged. Mutually exclusive with
default_version.
EOT
 type = bool
 default = null

 validation {
 condition = !(var.default_version != null && var.update_default_version != null)
 error_message = "Set at most one of default_version or update_default_version (they are mutually exclusive)."
 }
}

###############################################################################
# Encryption (CMK for EBS block devices)
#
# Module-level default CMK applied to every block_device_mappings.ebs entry that
# does not set its own kms_key_id. Null uses the AWS-managed EBS key (aws/ebs).
###############################################################################

variable "kms_key_arn" {
 description = <<EOT
ARN (or key id / alias) of a customer-managed KMS key used to encrypt EBS block devices
defined in block_device_mappings that do not set their own kms_key_id. Null (default)
uses the AWS-managed EBS key (aws/ebs). regulated-industry guidance: prefer a CMK for PII-bearing
hosts so key access is auditable via CloudTrail and revocable independently of the
volume. Wire from tf_mod_aws_kms (arn output). The key policy must allow EC2/EBS to use
it (kms:CreateGrant, kms:GenerateDataKeyWithoutPlaintext).
EOT
 type = string
 default = null

 validation {
 condition = var.kms_key_arn == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:|alias/|[0-9a-f-]{8,})", coalesce(var.kms_key_arn, "x")))
 error_message = "kms_key_arn must be a KMS key ARN, alias, or key id, or null."
 }
}

###############################################################################
# Block device mappings (child collection — repeating block)
#
# Encryption is ON by default for every ebs block (encrypted = "true", the secure
# baseline). Note the launch_template quirk: ebs.encrypted and ebs.delete_on_termination
# are STRINGS ("true"/"false"), not booleans, because the template distinguishes
# "unset" from "false".
###############################################################################

variable "block_device_mappings" {
 description = <<EOT
Map of block device mappings keyed by a stable name. Each entry adds one volume (or
suppresses an AMI-defined device). Encryption defaults ON for ebs blocks; ebs.kms_key_id
falls back to var.kms_key_arn when unset.

 - device_name: REQUIRED block-device name (e.g. "/dev/xvda", "/dev/sdf")
 - no_device: set to "" / true-ish to suppress an AMI device (string per the API)
 - virtual_name: instance-store device name (e.g. "ephemeral0")
 - ebs: EBS volume properties (all optional):
 - delete_on_termination: "true" | "false" (STRING; default "true")
 - encrypted: "true" | "false" (STRING; default "true" — keep ON)
 - kms_key_id: per-volume CMK (id/arn/alias); falls back to var.kms_key_arn
 - iops: provisioned IOPS (io1/io2/gp3)
 - throughput: MiB/s (gp3 only)
 - snapshot_id: restore from this snapshot (cannot combine with encrypted)
 - volume_size: size in GiB
 - volume_type: standard|gp2|gp3|io1|io2|sc1|st1 (default "gp3")
 - volume_initialization_rate: MiB/s pre-warm rate (100-300)
EOT
 type = map(object({
 device_name = string
 no_device = optional(string)
 virtual_name = optional(string)
 ebs = optional(object({
 delete_on_termination = optional(string, "true")
 encrypted = optional(string, "true")
 kms_key_id = optional(string)
 iops = optional(number)
 throughput = optional(number)
 snapshot_id = optional(string)
 volume_size = optional(number)
 volume_type = optional(string, "gp3")
 volume_initialization_rate = optional(number)
 }))
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.block_device_mappings: try(v.ebs.volume_type, "gp3") == null ? true: contains(["standard", "gp2", "gp3", "io1", "io2", "sc1", "st1"], try(v.ebs.volume_type, "gp3"))])
 error_message = "Each block_device_mappings[*].ebs.volume_type must be one of: standard, gp2, gp3, io1, io2, sc1, st1."
 }

 validation {
 condition = alltrue([for k, v in var.block_device_mappings: try(v.ebs.encrypted, "true") == null ? true: contains(["true", "false"], try(v.ebs.encrypted, "true"))])
 error_message = "Each block_device_mappings[*].ebs.encrypted is a string and must be \"true\" or \"false\"."
 }

 validation {
 condition = alltrue([for k, v in var.block_device_mappings: try(v.ebs.delete_on_termination, "true") == null ? true: contains(["true", "false"], try(v.ebs.delete_on_termination, "true"))])
 error_message = "Each block_device_mappings[*].ebs.delete_on_termination is a string and must be \"true\" or \"false\"."
 }
}

###############################################################################
# Instance Metadata Service (IMDSv2 secure-by-default)
###############################################################################

variable "metadata_options" {
 description = <<EOT
Instance Metadata Service (IMDS) options for launched instances. Defaults enforce IMDSv2
(the secure baseline): session tokens REQUIRED and a hop limit of 1 so the metadata
service is not reachable from containers or proxied off-box. Relax only with a documented
exception.

 - http_endpoint: "enabled" | "disabled" (default "enabled")
 - http_tokens: "required" (IMDSv2) | "optional" (default "required")
 - http_put_response_hop_limit: 1-64 (default 1)
 - http_protocol_ipv6: "enabled" | "disabled" (default "disabled")
 - instance_metadata_tags: "enabled" | "disabled" (default "disabled")
EOT
 type = object({
 http_endpoint = optional(string, "enabled")
 http_tokens = optional(string, "required")
 http_put_response_hop_limit = optional(number, 1)
 http_protocol_ipv6 = optional(string, "disabled")
 instance_metadata_tags = optional(string, "disabled")
 })
 default = {}

 validation {
 condition = contains(["enabled", "disabled"], var.metadata_options.http_endpoint)
 error_message = "metadata_options.http_endpoint must be one of: enabled, disabled."
 }

 validation {
 condition = contains(["required", "optional"], var.metadata_options.http_tokens)
 error_message = "metadata_options.http_tokens must be one of: required, optional. baseline is 'required' (IMDSv2)."
 }

 validation {
 condition = var.metadata_options.http_put_response_hop_limit >= 1 && var.metadata_options.http_put_response_hop_limit <= 64
 error_message = "metadata_options.http_put_response_hop_limit must be between 1 and 64."
 }

 validation {
 condition = contains(["enabled", "disabled"], var.metadata_options.http_protocol_ipv6)
 error_message = "metadata_options.http_protocol_ipv6 must be one of: enabled, disabled."
 }

 validation {
 condition = contains(["enabled", "disabled"], var.metadata_options.instance_metadata_tags)
 error_message = "metadata_options.instance_metadata_tags must be one of: enabled, disabled."
 }
}

###############################################################################
# Monitoring
###############################################################################

variable "monitoring" {
 description = <<EOT
Detailed (1-minute) CloudWatch monitoring for launched instances. Null (default) leaves
the block unset (basic 5-minute metrics). Set { enabled = true } for closer observability
at additional cost.
EOT
 type = object({
 enabled = optional(bool, true)
 })
 default = null
}

###############################################################################
# IAM instance profile
###############################################################################

variable "iam_instance_profile" {
 description = <<EOT
IAM instance profile to attach to launched instances. Null (default) attaches none.
Supply exactly one of arn or name. Wire from tf_mod_aws_iam_role (instance_profile_arn /
instance_profile_name). Requires the Terraform identity to hold iam:PassRole for the
underlying role.

 - arn: ARN of the instance profile (conflicts with name)
 - name: name of the instance profile (conflicts with arn)
EOT
 type = object({
 arn = optional(string)
 name = optional(string)
 })
 default = null

 validation {
 condition = var.iam_instance_profile == null || !(try(var.iam_instance_profile.arn, null) != null && try(var.iam_instance_profile.name, null) != null)
 error_message = "iam_instance_profile: set at most one of arn or name (they are mutually exclusive)."
 }
}

###############################################################################
# Placement
###############################################################################

variable "placement" {
 description = <<EOT
Placement options for launched instances. Null (default) uses AWS defaults.

 - affinity: Dedicated Host affinity ("default" | "host")
 - availability_zone: AZ to launch in
 - group_id: placement group id (conflicts with group_name)
 - group_name: placement group name (conflicts with group_id)
 - host_id: Dedicated Host id
 - host_resource_group_arn: License Manager host resource group ARN
 - spread_domain: reserved for future use
 - tenancy: "default" | "dedicated" | "host"
 - partition_number: partition number (partition-strategy placement groups only)
EOT
 type = object({
 affinity = optional(string)
 availability_zone = optional(string)
 group_id = optional(string)
 group_name = optional(string)
 host_id = optional(string)
 host_resource_group_arn = optional(string)
 spread_domain = optional(string)
 tenancy = optional(string)
 partition_number = optional(number)
 })
 default = null

 validation {
 condition = var.placement == null || try(var.placement.tenancy, null) == null || contains(["default", "dedicated", "host"], try(var.placement.tenancy, "default"))
 error_message = "placement.tenancy must be one of: default, dedicated, host."
 }

 validation {
 condition = var.placement == null || !(try(var.placement.group_id, null) != null && try(var.placement.group_name, null) != null)
 error_message = "placement: set at most one of group_id or group_name (they are mutually exclusive)."
 }
}

###############################################################################
# CPU options
###############################################################################

variable "cpu_options" {
 description = <<EOT
CPU options for launched instances. Null (default) uses the instance type's defaults.

 - amd_sev_snp: "enabled" | "disabled" (M6a/R6a/C6a only)
 - core_count: number of CPU cores
 - nested_virtualization: "enabled" | "disabled" (8th-gen Intel C8i/M8i/R8i only)
 - threads_per_core: 1 (disable SMT) or 2
EOT
 type = object({
 amd_sev_snp = optional(string)
 core_count = optional(number)
 nested_virtualization = optional(string)
 threads_per_core = optional(number)
 })
 default = null

 validation {
 condition = var.cpu_options == null || try(var.cpu_options.amd_sev_snp, null) == null || contains(["enabled", "disabled"], try(var.cpu_options.amd_sev_snp, "enabled"))
 error_message = "cpu_options.amd_sev_snp must be one of: enabled, disabled."
 }

 validation {
 condition = var.cpu_options == null || try(var.cpu_options.nested_virtualization, null) == null || contains(["enabled", "disabled"], try(var.cpu_options.nested_virtualization, "enabled"))
 error_message = "cpu_options.nested_virtualization must be one of: enabled, disabled."
 }
}

###############################################################################
# Credit specification (burstable T-family)
###############################################################################

variable "credit_specification" {
 description = <<EOT
CPU credit specification for burstable (T-family) instances. Null (default) uses the type
default (T3 launches "unlimited", T2 launches "standard"). cpu_credits is "standard" or
"unlimited". Ignored for non-burstable types.
EOT
 type = object({
 cpu_credits = optional(string, "standard")
 })
 default = null

 validation {
 condition = var.credit_specification == null || contains(["standard", "unlimited"], try(var.credit_specification.cpu_credits, "standard"))
 error_message = "credit_specification.cpu_credits must be one of: standard, unlimited."
 }
}

###############################################################################
# Enclave / hibernation / maintenance / network performance / private DNS
###############################################################################

variable "enclave_options" {
 description = "Nitro Enclaves options. Null (default) disables enclaves. Set { enabled = true } to launch instances with Nitro Enclaves support."
 type = object({
 enabled = optional(bool, false)
 })
 default = null
}

variable "hibernation_options" {
 description = <<EOT
Hibernation options. Null (default) leaves it unset. Set { configured = true } to allow
hibernation — requires a supported instance type and an encrypted root volume (this module
encrypts EBS block devices by default).
EOT
 type = object({
 configured = optional(bool, false)
 })
 default = null
}

variable "maintenance_options" {
 description = <<EOT
Instance maintenance options. Null (default) uses AWS defaults. auto_recovery is
"default" (recover on hardware impairment where supported) or "disabled".
EOT
 type = object({
 auto_recovery = optional(string, "default")
 })
 default = null

 validation {
 condition = var.maintenance_options == null || contains(["default", "disabled"], try(var.maintenance_options.auto_recovery, "default"))
 error_message = "maintenance_options.auto_recovery must be one of: default, disabled."
 }
}

variable "network_performance_options" {
 description = <<EOT
Network performance (bandwidth weighting) options. Null (default) uses "default".
bandwidth_weighting is "default", "vpc-1" (boost networking, reduce EBS baseline), or
"ebs-1" (boost EBS, reduce networking baseline). Supported only on select instance types.
EOT
 type = object({
 bandwidth_weighting = optional(string, "default")
 })
 default = null

 validation {
 condition = var.network_performance_options == null || contains(["default", "vpc-1", "ebs-1"], try(var.network_performance_options.bandwidth_weighting, "default"))
 error_message = "network_performance_options.bandwidth_weighting must be one of: default, vpc-1, ebs-1."
 }
}

variable "private_dns_name_options" {
 description = <<EOT
Private DNS name options for launched instances. Null (default) inherits subnet defaults.

 - enable_resource_name_dns_a_record: answer A records for the resource name
 - enable_resource_name_dns_aaaa_record: answer AAAA records for the resource name
 - hostname_type: "ip-name" | "resource-name"
EOT
 type = object({
 enable_resource_name_dns_a_record = optional(bool)
 enable_resource_name_dns_aaaa_record = optional(bool)
 hostname_type = optional(string)
 })
 default = null

 validation {
 condition = var.private_dns_name_options == null || try(var.private_dns_name_options.hostname_type, null) == null || contains(["ip-name", "resource-name"], try(var.private_dns_name_options.hostname_type, "ip-name"))
 error_message = "private_dns_name_options.hostname_type must be one of: ip-name, resource-name."
 }
}

###############################################################################
# Capacity reservation targeting
###############################################################################

variable "capacity_reservation_specification" {
 description = <<EOT
Capacity Reservation targeting for launched instances. Null (default) uses the AWS
default ("open"). When a target id/ARN is supplied, set preference to
"capacity-reservations-only" or omit it.

 - capacity_reservation_preference: "open" | "none" | "capacity-reservations-only"
 - capacity_reservation_target:
 - capacity_reservation_id: target reservation id (cr-...)
 - capacity_reservation_resource_group_arn: target reservation resource-group ARN
EOT
 type = object({
 capacity_reservation_preference = optional(string)
 capacity_reservation_target = optional(object({
 capacity_reservation_id = optional(string)
 capacity_reservation_resource_group_arn = optional(string)
 }))
 })
 default = null

 validation {
 condition = var.capacity_reservation_specification == null || try(var.capacity_reservation_specification.capacity_reservation_preference, null) == null || contains(["open", "none", "capacity-reservations-only"], try(var.capacity_reservation_specification.capacity_reservation_preference, "open"))
 error_message = "capacity_reservation_specification.capacity_reservation_preference must be one of: open, none, capacity-reservations-only."
 }
}

###############################################################################
# Spot market options
###############################################################################

variable "instance_market_options" {
 description = <<EOT
Spot-instance market options. Null (default) launches On-Demand instances.

 - market_type: "spot" (the only valid value)
 - spot_options:
 - block_duration_minutes: required duration in minutes (multiple of 60)
 - instance_interruption_behavior: "hibernate" | "stop" | "terminate" (default "terminate")
 - max_price: maximum hourly price (string)
 - spot_instance_type: "one-time" | "persistent"
 - valid_until: RFC3339 expiry timestamp
EOT
 type = object({
 market_type = optional(string, "spot")
 spot_options = optional(object({
 block_duration_minutes = optional(number)
 instance_interruption_behavior = optional(string)
 max_price = optional(string)
 spot_instance_type = optional(string)
 valid_until = optional(string)
 }))
 })
 default = null

 validation {
 condition = var.instance_market_options == null || contains(["spot"], try(var.instance_market_options.market_type, "spot"))
 error_message = "instance_market_options.market_type must be \"spot\"."
 }

 validation {
 condition = var.instance_market_options == null || try(var.instance_market_options.spot_options.spot_instance_type, null) == null || contains(["one-time", "persistent"], try(var.instance_market_options.spot_options.spot_instance_type, "one-time"))
 error_message = "instance_market_options.spot_options.spot_instance_type must be one of: one-time, persistent."
 }

 validation {
 condition = var.instance_market_options == null || try(var.instance_market_options.spot_options.instance_interruption_behavior, null) == null || contains(["hibernate", "stop", "terminate"], try(var.instance_market_options.spot_options.instance_interruption_behavior, "terminate"))
 error_message = "instance_market_options.spot_options.instance_interruption_behavior must be one of: hibernate, stop, terminate."
 }
}

###############################################################################
# License specifications (repeating block)
###############################################################################

variable "license_specification_arns" {
 description = <<EOT
Set of License Manager license-configuration ARNs to associate with launched instances.
Empty (default) associates none. Each ARN renders one license_specification block.
EOT
 type = set(string)
 default = []

 validation {
 condition = alltrue([for a in var.license_specification_arns: can(regex("^arn:aws[a-zA-Z-]*:license-manager:", a))])
 error_message = "Each license_specification_arns entry must be a License Manager license-configuration ARN (arn:aws:license-manager:...)."
 }
}

###############################################################################
# Instance requirements (attribute-based instance selection)
#
# Mutually exclusive with instance_type. memory_mib.min and vcpu_count.min are required
# by the API when this block is present.
###############################################################################

variable "instance_requirements" {
 description = <<EOT
Attribute-based instance type selection. Null (default) uses instance_type instead.
Mutually exclusive with instance_type. memory_mib.min and vcpu_count.min are REQUIRED
when set. The min/max sub-blocks each take { min, max } numbers. See the AWS docs for the
full attribute set; all fields are optional except the two required mins.

 - memory_mib: { min (REQUIRED), max }
 - vcpu_count: { min (REQUIRED), max }
 - bare_metal / burstable_performance / local_storage: "included" | "excluded" | "required"
 - allowed_instance_types / excluded_instance_types: wildcard instance-type patterns
 - *_manufacturers / *_names / *_types / instance_generations / local_storage_types: filter lists
 - the various min/max range blocks (accelerator_count, baseline_ebs_bandwidth_mbps,
 memory_gib_per_vcpu, network_bandwidth_gbps, network_interface_count,
 total_local_storage_gb, accelerator_total_memory_mib)
EOT
 type = object({
 memory_mib = object({
 min = number
 max = optional(number)
 })
 vcpu_count = object({
 min = number
 max = optional(number)
 })
 accelerator_manufacturers = optional(set(string))
 accelerator_names = optional(set(string))
 accelerator_types = optional(set(string))
 allowed_instance_types = optional(set(string))
 bare_metal = optional(string)
 burstable_performance = optional(string)
 cpu_manufacturers = optional(set(string))
 excluded_instance_types = optional(set(string))
 instance_generations = optional(set(string))
 local_storage = optional(string)
 local_storage_types = optional(set(string))
 max_spot_price_as_percentage_of_optimal_on_demand_price = optional(number)
 on_demand_max_price_percentage_over_lowest_price = optional(number)
 require_hibernate_support = optional(bool)
 spot_max_price_percentage_over_lowest_price = optional(number)
 accelerator_count = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 accelerator_total_memory_mib = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 baseline_ebs_bandwidth_mbps = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 memory_gib_per_vcpu = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 network_bandwidth_gbps = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 network_interface_count = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 total_local_storage_gb = optional(object({
 min = optional(number)
 max = optional(number)
 }))
 })
 default = null

 validation {
 condition = var.instance_requirements == null || !(var.instance_type != null)
 error_message = "instance_requirements and instance_type are mutually exclusive — set only one."
 }

 validation {
 condition = var.instance_requirements == null || alltrue([
 for f in [
 try(var.instance_requirements.bare_metal, null),
 try(var.instance_requirements.burstable_performance, null),
 try(var.instance_requirements.local_storage, null),
 ]: f == null || contains(["included", "excluded", "required"], f)
 ])
 error_message = "instance_requirements bare_metal, burstable_performance, and local_storage must each be one of: included, excluded, required."
 }
}

###############################################################################
# Network interfaces (child collection — repeating block)
#
# launch_template models several "boolean" NIC fields as STRINGS ("true"/"false"):
# associate_public_ip_address, associate_carrier_ip_address, delete_on_termination,
# primary_ipv6. They are left unset (null) by default — secure baseline keeps launched
# instances private unless a public address is explicitly requested.
###############################################################################

variable "network_interfaces" {
 description = <<EOT
Map of network interfaces to attach at launch, keyed by a stable name. Set device_index
explicitly to control ordering (the primary interface is index 0). String-typed booleans
(associate_public_ip_address, associate_carrier_ip_address, delete_on_termination,
primary_ipv6) take "true"/"false". Conflicts: vpc_security_group_ids (top-level) vs
security_groups (here) — use one model.

 - associate_public_ip_address: "true" | "false" (STRING; default unset → private)
 - associate_carrier_ip_address: "true" | "false" (STRING; Wavelength only)
 - delete_on_termination: "true" | "false" (STRING)
 - description / device_index / interface_type / network_card_index / network_interface_id
 - subnet_id / private_ip_address / primary_ipv6
 - ipv4_address_count / ipv4_addresses / ipv4_prefix_count / ipv4_prefixes
 - ipv6_address_count / ipv6_addresses / ipv6_prefix_count / ipv6_prefixes
 - security_groups: set of security group IDs
 - ena_srd_specification: { ena_srd_enabled, ena_srd_udp_specification = { ena_srd_udp_enabled } }
 - connection_tracking_specification: { tcp_established_timeout, udp_stream_timeout, udp_timeout }
EOT
 type = map(object({
 associate_public_ip_address = optional(string)
 associate_carrier_ip_address = optional(string)
 delete_on_termination = optional(string)
 description = optional(string)
 device_index = optional(number)
 interface_type = optional(string)
 network_card_index = optional(number)
 network_interface_id = optional(string)
 subnet_id = optional(string)
 private_ip_address = optional(string)
 primary_ipv6 = optional(string)
 ipv4_address_count = optional(number)
 ipv4_addresses = optional(set(string))
 ipv4_prefix_count = optional(number)
 ipv4_prefixes = optional(set(string))
 ipv6_address_count = optional(number)
 ipv6_addresses = optional(set(string))
 ipv6_prefix_count = optional(number)
 ipv6_prefixes = optional(set(string))
 security_groups = optional(set(string))
 ena_srd_specification = optional(object({
 ena_srd_enabled = optional(bool)
 ena_srd_udp_specification = optional(object({
 ena_srd_udp_enabled = optional(bool)
 }))
 }))
 connection_tracking_specification = optional(object({
 tcp_established_timeout = optional(number)
 udp_stream_timeout = optional(number)
 udp_timeout = optional(number)
 }))
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.network_interfaces: alltrue([
 for f in [
 try(v.associate_public_ip_address, null),
 try(v.associate_carrier_ip_address, null),
 try(v.delete_on_termination, null),
 try(v.primary_ipv6, null),
 ]: f == null || contains(["true", "false"], f)
 ])
 ])
 error_message = "network_interfaces string-boolean fields (associate_public_ip_address, associate_carrier_ip_address, delete_on_termination, primary_ipv6) must be \"true\" or \"false\"."
 }
}

###############################################################################
# Secondary interfaces (repeating block)
###############################################################################

variable "secondary_interfaces" {
 description = <<EOT
Map of secondary interfaces to associate with launched instances, keyed by a stable name.
Empty (default) associates none. interface_type only supports "secondary";
delete_on_termination only supports true.

 - delete_on_termination: only true is supported
 - device_index / network_card_index
 - interface_type: only "secondary"
 - private_ip_address_count / private_ip_addresses
 - secondary_subnet_id
EOT
 type = map(object({
 delete_on_termination = optional(bool)
 device_index = optional(number)
 interface_type = optional(string)
 network_card_index = optional(number)
 private_ip_address_count = optional(number)
 private_ip_addresses = optional(set(string))
 secondary_subnet_id = optional(string)
 }))
 default = {}
}

###############################################################################
# Tag specifications (tags propagated to resources created AT LAUNCH)
#
# Distinct from var.tags (which tags the template itself): tag_specifications tag the
# instances/volumes/ENIs that the template launches. Provider default_tags are NOT
# propagated to ASG-created resources, so propagate_tags (default true) seeds var.tags
# onto the instance and volume resource types for consistent governance tagging.
###############################################################################

variable "tag_specifications" {
 description = <<EOT
Map of launch-time tags keyed by resource_type. Each value is a map of tags applied to
that resource type when an instance is launched from the template. Valid resource_type
keys: instance, volume, network-interface, spot-instances-request, elastic-gpu.
Caller-supplied tags here win over module tags propagated via propagate_tags.
EOT
 type = map(map(string))
 default = {}

 validation {
 condition = alltrue([for rt in keys(var.tag_specifications): contains(["instance", "volume", "network-interface", "spot-instances-request", "elastic-gpu"], rt)])
 error_message = "tag_specifications keys (resource_type) must be one of: instance, volume, network-interface, spot-instances-request, elastic-gpu."
 }
}

variable "propagate_tags" {
 description = <<EOT
When true (default), the module-level tags (var.tags) are also applied as launch-time
tag_specifications for the "instance" and "volume" resource types, so resources launched
from the template carry the same governance tags as the template. Caller-supplied
tag_specifications win on key conflict. Set false to tag only the template itself.
Provider default_tags are NOT propagated to launch-created resources, which is why this
defaults to true for a regulated FI.
EOT
 type = bool
 default = true
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to the launch template resource itself. These merge with
provider-level default_tags; resource tags win on key conflict. The computed tags_all
output reflects the merged set. When propagate_tags is true these tags are also seeded
onto the instance and volume tag_specifications so launched resources inherit them.
EOT
 type = map(string)
 default = {}
}
