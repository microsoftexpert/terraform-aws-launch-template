# terraform-aws-launch-template — SCOPE

Standalone module for a single, secure-by-default Amazon EC2 **launch template** — the
reusable instance blueprint consumed by Auto Scaling groups, EC2 Fleet, Spot Fleet, and
`aws_instance`. One module call produces an IMDSv2-enforced, EBS-encrypted-by-default
template whose governance tags propagate to launched instances and volumes, aligned with the
Casey's (NPI / GLBA / FCA) baseline.

- **Module type:** Standalone (single resource)
- **Resource managed:** `aws_launch_template.this`

## In-scope resources

- `aws_launch_template` — the only resource this module manages.

## Out-of-scope resources (consumed by reference)

Referenced by `id`/`arn`/`name`, never created here:

- AMI — `image_id` (from `terraform-aws-ami`, or a public/marketplace/SSM-resolved AMI)
- Security groups — `vpc_security_group_ids` / per-interface `security_groups` (from `terraform-aws-security-group`)
- SSH key pair — `key_name` (from `terraform-aws-key-pair`)
- IAM instance profile — `iam_instance_profile` (from `terraform-aws-iam-role`)
- KMS CMK for EBS encryption — `kms_key_arn` / per-volume `kms_key_id` (from `terraform-aws-kms`)
- Subnet — per-interface `subnet_id` (from `terraform-aws-vpc`)
- Placement group — `placement.group_id` / `group_name` (from `terraform-aws-placement-group`)
- Capacity reservation — `capacity_reservation_specification` target (from `terraform-aws-capacity-reservation`)
- License configurations — `license_specification_arns` (License Manager)
- Consuming compute — `terraform-aws-autoscaling-group`, EC2/Spot Fleet, `aws_instance`

## Consumes

| Input | Type | Source module |
|---|---|---|
| `image_id` | `string` (AMI id / `resolve:ssm:`) | `terraform-aws-ami` |
| `vpc_security_group_ids` | `list(string)` (SG ids) | `terraform-aws-security-group` |
| `iam_instance_profile` | `object({arn, name})` | `terraform-aws-iam-role` |
| `kms_key_arn` | `string` (KMS key ARN/alias/id) | `terraform-aws-kms` |
| `key_name` | `string` (key pair name) | `terraform-aws-key-pair` |
| `network_interfaces[*].subnet_id` | `string` (subnet id) | `terraform-aws-vpc` |
| `placement.group_id` / `group_name` | `string` | `terraform-aws-placement-group` |

## Required IAM permissions

Least-privilege actions the Terraform identity needs. A launch template only *stores* an
instance spec — it never calls `RunInstances` — so the action set is narrow.

| Action | Required for |
|---|---|
| `ec2:CreateLaunchTemplate` | Creating the template |
| `ec2:CreateLaunchTemplateVersion` | New version on every spec change |
| `ec2:ModifyLaunchTemplate` | `default_version` / `update_default_version` promotion |
| `ec2:DeleteLaunchTemplate` | Destroy |
| `ec2:DeleteLaunchTemplateVersions` | Version pruning on update/destroy |
| `ec2:DescribeLaunchTemplates`, `ec2:DescribeLaunchTemplateVersions` | Plan / refresh (read-only) |
| `ec2:CreateTags`, `ec2:DeleteTags` | Tagging the template + `tag_specifications` (scope with `ec2:CreateAction = CreateLaunchTemplate`) |

**Not required by the template creator:**
- **`iam:PassRole`** — storing an `iam_instance_profile` reference does not pass the role.
  `iam:PassRole` (scoped to the role ARN, condition `iam:PassedToService = ec2.amazonaws.com`)
  is enforced against the **consumer** (`RunInstances` / ASG SLR / `aws_instance`).
- **KMS actions** — the CMK is only stored as a string; `kms:CreateGrant` /
  `kms:GenerateDataKeyWithoutPlaintext` are exercised at instance-launch time, by the consumer.

## AWS Prerequisites

- **No service-linked role** is required to create a launch template. (The consuming EC2
  Auto Scaling service uses `AWSServiceRoleForAutoScaling`, created with the ASG — not here.)
- **Referenced resources** (`image_id`, security groups, `key_name`, instance profile,
  placement/capacity targets) must exist and be in the target Region/VPC. AMIs are Region-scoped.
- **CMK (optional):** when `kms_key_arn` / `kms_key_id` is supplied, the key policy must allow
  the EC2/EBS service to use it at launch — validated at instance launch, not template creation.
- **Quotas:** default **5,000 launch templates per Region** and **10,000 versions per template**
  (both raisable via Service Quotas). Instance-type vCPU quotas apply to the consumer at launch.
- **Region:** regional resource — **no us-east-1 global-service constraint**.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Launch template id (`lt-...`) — **primary** | `terraform-aws-autoscaling-group`, EC2/Spot Fleet, `aws_instance` |
| `arn` | Launch template ARN — **primary**, cross-resource reference type | IAM policies, resource-level `ec2:RunInstances` conditions |
| `name` | Template name (explicit/prefix/auto) | ASG/fleet references by name |
| `latest_version` | Latest version number (increments per change) | Consumers pinning a specific revision |
| `default_version` | Default version number | Consumers referencing `"$Default"` |
| `tags_all` | All tags incl. provider `default_tags` (resource tags win) — **primary** | Governance / audit / cost allocation |

## Provider gotchas (from authoring)

- **Versioning, not replacement.** Most spec changes create a new **version** of the same
  template; `id`/`arn` stay stable and `latest_version` increments. Only `name` / `name_prefix`
  are **FORCE-NEW** (changing `name` recreates the template and its `id`/`arn`).
- **String-typed "booleans".** The API distinguishes unset from false, so `ebs_optimized`,
  `block_device_mappings[*].ebs.{encrypted,delete_on_termination}`, and
  `network_interfaces[*].{associate_public_ip_address,associate_carrier_ip_address,delete_on_termination,primary_ipv6}`
  are **strings** (`"true"`/`"false"`), not booleans. Validations enforce this.
- **`tags` vs `tag_specifications`.** `var.tags` tags the template object; `tag_specifications`
  tag launched instances/volumes. Provider `default_tags` are **NOT** propagated to
  ASG/launch-created resources — `propagate_tags` (default `true`) seeds `var.tags` onto the
  `instance` and `volume` types; caller `tag_specifications` win on conflict; empty tag maps are dropped.
- **`tags` ↔ `tags_all` ↔ `default_tags`.** `tags_all` is the merge of resource tags over
  provider `default_tags`, resource tags winning. `default_tags` is the caller's provider-block
  concern, never set in the module.
- **Mutually-exclusive inputs** (validated): `name`⊕`name_prefix`; `instance_type`⊕`instance_requirements`;
  `default_version`⊕`update_default_version`; `vpc_security_group_ids`⊕per-interface `security_groups`;
  `iam_instance_profile.{arn,name}`; `placement.{group_id,group_name}`.
- **`instance_requirements` required mins.** `memory_mib.min` and `vcpu_count.min` are required
  by the API when the block is present.
- **`encrypted` + `snapshot_id` conflict.** An unencrypted snapshot cannot be combined with
  `encrypted = "true"`; restoring from one requires `encrypted = "false"`.
- **Destroy ordering.** A template cannot be deleted while an ASG/fleet/instance references it —
  destroy consumers first (Terraform orders this when both are managed together).
- **No `iam:PassRole` / KMS at create.** See Required IAM permissions — both are consumer-side.
- **No `region` variable / no `provider {}` block / no credential variables** — provider inheritance only.
