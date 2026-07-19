###############################################################################
# Locals
#
# Launch-time tag propagation. var.tags tags the template itself; tag_specifications
# tag the instances/volumes the template launches. Provider default_tags are NOT
# propagated to ASG/launch-created resources, so when propagate_tags is true we seed
# var.tags onto the "instance" and "volume" resource types. Caller-supplied
# tag_specifications win on key conflict, and empty tag maps are dropped so we never
# render a no-op tag_specifications block.
###############################################################################

locals {
 propagated_resource_types = var.propagate_tags ? ["instance", "volume"]: []

 tag_specification_types = toset(concat(keys(var.tag_specifications), local.propagated_resource_types))

 tag_specifications = {
 for rt in local.tag_specification_types: rt => merge(contains(local.propagated_resource_types, rt) ? var.tags: {},
 try(var.tag_specifications[rt], {}))
 }

 effective_tag_specifications = { for rt, t in local.tag_specifications: rt => t if length(t) > 0 }
}

###############################################################################
# Launch template (keystone)
###############################################################################

resource "aws_launch_template" "this" {
 name = var.name
 name_prefix = var.name_prefix
 description = var.description

 # Core launch configuration
 image_id = var.image_id
 instance_type = var.instance_type
 key_name = var.key_name
 user_data = var.user_data
 vpc_security_group_ids = var.vpc_security_group_ids
 security_group_names = var.security_group_names
 ebs_optimized = var.ebs_optimized
 disable_api_stop = var.disable_api_stop
 disable_api_termination = var.disable_api_termination
 instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
 kernel_id = var.kernel_id
 ram_disk_id = var.ram_disk_id
 default_version = var.default_version
 update_default_version = var.update_default_version

 # Block device mappings — EBS encryption ON by default; CMK falls back to var.kms_key_arn.
 dynamic "block_device_mappings" {
 for_each = var.block_device_mappings
 content {
 device_name = block_device_mappings.value.device_name
 no_device = try(block_device_mappings.value.no_device, null)
 virtual_name = try(block_device_mappings.value.virtual_name, null)

 dynamic "ebs" {
 for_each = try(block_device_mappings.value.ebs, null) != null ? [block_device_mappings.value.ebs]: []
 content {
 delete_on_termination = try(ebs.value.delete_on_termination, "true")
 encrypted = try(ebs.value.encrypted, "true")
 kms_key_id = try(coalesce(ebs.value.kms_key_id, var.kms_key_arn), null)
 iops = try(ebs.value.iops, null)
 throughput = try(ebs.value.throughput, null)
 snapshot_id = try(ebs.value.snapshot_id, null)
 volume_size = try(ebs.value.volume_size, null)
 volume_type = try(ebs.value.volume_type, "gp3")
 volume_initialization_rate = try(ebs.value.volume_initialization_rate, null)
 }
 }
 }
 }

 # IMDSv2 enforced by default (session tokens required, hop limit 1).
 metadata_options {
 http_endpoint = var.metadata_options.http_endpoint
 http_tokens = var.metadata_options.http_tokens
 http_put_response_hop_limit = var.metadata_options.http_put_response_hop_limit
 http_protocol_ipv6 = var.metadata_options.http_protocol_ipv6
 instance_metadata_tags = var.metadata_options.instance_metadata_tags
 }

 # Detailed monitoring
 dynamic "monitoring" {
 for_each = var.monitoring != null ? [var.monitoring]: []
 content {
 enabled = try(monitoring.value.enabled, true)
 }
 }

 # IAM instance profile
 dynamic "iam_instance_profile" {
 for_each = var.iam_instance_profile != null ? [var.iam_instance_profile]: []
 content {
 arn = try(iam_instance_profile.value.arn, null)
 name = try(iam_instance_profile.value.name, null)
 }
 }

 # Placement
 dynamic "placement" {
 for_each = var.placement != null ? [var.placement]: []
 content {
 affinity = try(placement.value.affinity, null)
 availability_zone = try(placement.value.availability_zone, null)
 group_id = try(placement.value.group_id, null)
 group_name = try(placement.value.group_name, null)
 host_id = try(placement.value.host_id, null)
 host_resource_group_arn = try(placement.value.host_resource_group_arn, null)
 spread_domain = try(placement.value.spread_domain, null)
 tenancy = try(placement.value.tenancy, null)
 partition_number = try(placement.value.partition_number, null)
 }
 }

 # CPU options
 dynamic "cpu_options" {
 for_each = var.cpu_options != null ? [var.cpu_options]: []
 content {
 amd_sev_snp = try(cpu_options.value.amd_sev_snp, null)
 core_count = try(cpu_options.value.core_count, null)
 nested_virtualization = try(cpu_options.value.nested_virtualization, null)
 threads_per_core = try(cpu_options.value.threads_per_core, null)
 }
 }

 # Credit specification (burstable T-family)
 dynamic "credit_specification" {
 for_each = var.credit_specification != null ? [var.credit_specification]: []
 content {
 cpu_credits = try(credit_specification.value.cpu_credits, "standard")
 }
 }

 # Nitro Enclaves
 dynamic "enclave_options" {
 for_each = var.enclave_options != null ? [var.enclave_options]: []
 content {
 enabled = try(enclave_options.value.enabled, false)
 }
 }

 # Hibernation
 dynamic "hibernation_options" {
 for_each = var.hibernation_options != null ? [var.hibernation_options]: []
 content {
 configured = try(hibernation_options.value.configured, false)
 }
 }

 # Maintenance / auto-recovery
 dynamic "maintenance_options" {
 for_each = var.maintenance_options != null ? [var.maintenance_options]: []
 content {
 auto_recovery = try(maintenance_options.value.auto_recovery, "default")
 }
 }

 # Network performance (bandwidth weighting)
 dynamic "network_performance_options" {
 for_each = var.network_performance_options != null ? [var.network_performance_options]: []
 content {
 bandwidth_weighting = try(network_performance_options.value.bandwidth_weighting, "default")
 }
 }

 # Private DNS name options
 dynamic "private_dns_name_options" {
 for_each = var.private_dns_name_options != null ? [var.private_dns_name_options]: []
 content {
 enable_resource_name_dns_a_record = try(private_dns_name_options.value.enable_resource_name_dns_a_record, null)
 enable_resource_name_dns_aaaa_record = try(private_dns_name_options.value.enable_resource_name_dns_aaaa_record, null)
 hostname_type = try(private_dns_name_options.value.hostname_type, null)
 }
 }

 # Capacity Reservation targeting
 dynamic "capacity_reservation_specification" {
 for_each = var.capacity_reservation_specification != null ? [var.capacity_reservation_specification]: []
 content {
 capacity_reservation_preference = try(capacity_reservation_specification.value.capacity_reservation_preference, null)

 dynamic "capacity_reservation_target" {
 for_each = try(capacity_reservation_specification.value.capacity_reservation_target, null) != null ? [capacity_reservation_specification.value.capacity_reservation_target]: []
 content {
 capacity_reservation_id = try(capacity_reservation_target.value.capacity_reservation_id, null)
 capacity_reservation_resource_group_arn = try(capacity_reservation_target.value.capacity_reservation_resource_group_arn, null)
 }
 }
 }
 }

 # Spot market options
 dynamic "instance_market_options" {
 for_each = var.instance_market_options != null ? [var.instance_market_options]: []
 content {
 market_type = try(instance_market_options.value.market_type, "spot")

 dynamic "spot_options" {
 for_each = try(instance_market_options.value.spot_options, null) != null ? [instance_market_options.value.spot_options]: []
 content {
 block_duration_minutes = try(spot_options.value.block_duration_minutes, null)
 instance_interruption_behavior = try(spot_options.value.instance_interruption_behavior, null)
 max_price = try(spot_options.value.max_price, null)
 spot_instance_type = try(spot_options.value.spot_instance_type, null)
 valid_until = try(spot_options.value.valid_until, null)
 }
 }
 }
 }

 # License specifications
 dynamic "license_specification" {
 for_each = var.license_specification_arns
 content {
 license_configuration_arn = license_specification.value
 }
 }

 # Attribute-based instance selection (mutually exclusive with instance_type)
 dynamic "instance_requirements" {
 for_each = var.instance_requirements != null ? [var.instance_requirements]: []
 content {
 accelerator_manufacturers = try(instance_requirements.value.accelerator_manufacturers, null)
 accelerator_names = try(instance_requirements.value.accelerator_names, null)
 accelerator_types = try(instance_requirements.value.accelerator_types, null)
 allowed_instance_types = try(instance_requirements.value.allowed_instance_types, null)
 bare_metal = try(instance_requirements.value.bare_metal, null)
 burstable_performance = try(instance_requirements.value.burstable_performance, null)
 cpu_manufacturers = try(instance_requirements.value.cpu_manufacturers, null)
 excluded_instance_types = try(instance_requirements.value.excluded_instance_types, null)
 instance_generations = try(instance_requirements.value.instance_generations, null)
 local_storage = try(instance_requirements.value.local_storage, null)
 local_storage_types = try(instance_requirements.value.local_storage_types, null)
 max_spot_price_as_percentage_of_optimal_on_demand_price = try(instance_requirements.value.max_spot_price_as_percentage_of_optimal_on_demand_price, null)
 on_demand_max_price_percentage_over_lowest_price = try(instance_requirements.value.on_demand_max_price_percentage_over_lowest_price, null)
 require_hibernate_support = try(instance_requirements.value.require_hibernate_support, null)
 spot_max_price_percentage_over_lowest_price = try(instance_requirements.value.spot_max_price_percentage_over_lowest_price, null)

 memory_mib {
 min = instance_requirements.value.memory_mib.min
 max = try(instance_requirements.value.memory_mib.max, null)
 }

 vcpu_count {
 min = instance_requirements.value.vcpu_count.min
 max = try(instance_requirements.value.vcpu_count.max, null)
 }

 dynamic "accelerator_count" {
 for_each = try(instance_requirements.value.accelerator_count, null) != null ? [instance_requirements.value.accelerator_count]: []
 content {
 min = try(accelerator_count.value.min, null)
 max = try(accelerator_count.value.max, null)
 }
 }

 dynamic "accelerator_total_memory_mib" {
 for_each = try(instance_requirements.value.accelerator_total_memory_mib, null) != null ? [instance_requirements.value.accelerator_total_memory_mib]: []
 content {
 min = try(accelerator_total_memory_mib.value.min, null)
 max = try(accelerator_total_memory_mib.value.max, null)
 }
 }

 dynamic "baseline_ebs_bandwidth_mbps" {
 for_each = try(instance_requirements.value.baseline_ebs_bandwidth_mbps, null) != null ? [instance_requirements.value.baseline_ebs_bandwidth_mbps]: []
 content {
 min = try(baseline_ebs_bandwidth_mbps.value.min, null)
 max = try(baseline_ebs_bandwidth_mbps.value.max, null)
 }
 }

 dynamic "memory_gib_per_vcpu" {
 for_each = try(instance_requirements.value.memory_gib_per_vcpu, null) != null ? [instance_requirements.value.memory_gib_per_vcpu]: []
 content {
 min = try(memory_gib_per_vcpu.value.min, null)
 max = try(memory_gib_per_vcpu.value.max, null)
 }
 }

 dynamic "network_bandwidth_gbps" {
 for_each = try(instance_requirements.value.network_bandwidth_gbps, null) != null ? [instance_requirements.value.network_bandwidth_gbps]: []
 content {
 min = try(network_bandwidth_gbps.value.min, null)
 max = try(network_bandwidth_gbps.value.max, null)
 }
 }

 dynamic "network_interface_count" {
 for_each = try(instance_requirements.value.network_interface_count, null) != null ? [instance_requirements.value.network_interface_count]: []
 content {
 min = try(network_interface_count.value.min, null)
 max = try(network_interface_count.value.max, null)
 }
 }

 dynamic "total_local_storage_gb" {
 for_each = try(instance_requirements.value.total_local_storage_gb, null) != null ? [instance_requirements.value.total_local_storage_gb]: []
 content {
 min = try(total_local_storage_gb.value.min, null)
 max = try(total_local_storage_gb.value.max, null)
 }
 }
 }
 }

 # Network interfaces (set device_index explicitly to order them)
 dynamic "network_interfaces" {
 for_each = var.network_interfaces
 content {
 associate_public_ip_address = try(network_interfaces.value.associate_public_ip_address, null)
 associate_carrier_ip_address = try(network_interfaces.value.associate_carrier_ip_address, null)
 delete_on_termination = try(network_interfaces.value.delete_on_termination, null)
 description = try(network_interfaces.value.description, null)
 device_index = try(network_interfaces.value.device_index, null)
 interface_type = try(network_interfaces.value.interface_type, null)
 network_card_index = try(network_interfaces.value.network_card_index, null)
 network_interface_id = try(network_interfaces.value.network_interface_id, null)
 subnet_id = try(network_interfaces.value.subnet_id, null)
 private_ip_address = try(network_interfaces.value.private_ip_address, null)
 primary_ipv6 = try(network_interfaces.value.primary_ipv6, null)
 ipv4_address_count = try(network_interfaces.value.ipv4_address_count, null)
 ipv4_addresses = try(network_interfaces.value.ipv4_addresses, null)
 ipv4_prefix_count = try(network_interfaces.value.ipv4_prefix_count, null)
 ipv4_prefixes = try(network_interfaces.value.ipv4_prefixes, null)
 ipv6_address_count = try(network_interfaces.value.ipv6_address_count, null)
 ipv6_addresses = try(network_interfaces.value.ipv6_addresses, null)
 ipv6_prefix_count = try(network_interfaces.value.ipv6_prefix_count, null)
 ipv6_prefixes = try(network_interfaces.value.ipv6_prefixes, null)
 security_groups = try(network_interfaces.value.security_groups, null)

 dynamic "ena_srd_specification" {
 for_each = try(network_interfaces.value.ena_srd_specification, null) != null ? [network_interfaces.value.ena_srd_specification]: []
 content {
 ena_srd_enabled = try(ena_srd_specification.value.ena_srd_enabled, null)

 dynamic "ena_srd_udp_specification" {
 for_each = try(ena_srd_specification.value.ena_srd_udp_specification, null) != null ? [ena_srd_specification.value.ena_srd_udp_specification]: []
 content {
 ena_srd_udp_enabled = try(ena_srd_udp_specification.value.ena_srd_udp_enabled, null)
 }
 }
 }
 }

 dynamic "connection_tracking_specification" {
 for_each = try(network_interfaces.value.connection_tracking_specification, null) != null ? [network_interfaces.value.connection_tracking_specification]: []
 content {
 tcp_established_timeout = try(connection_tracking_specification.value.tcp_established_timeout, null)
 udp_stream_timeout = try(connection_tracking_specification.value.udp_stream_timeout, null)
 udp_timeout = try(connection_tracking_specification.value.udp_timeout, null)
 }
 }
 }
 }

 # Secondary interfaces
 dynamic "secondary_interfaces" {
 for_each = var.secondary_interfaces
 content {
 delete_on_termination = try(secondary_interfaces.value.delete_on_termination, null)
 device_index = try(secondary_interfaces.value.device_index, null)
 interface_type = try(secondary_interfaces.value.interface_type, null)
 network_card_index = try(secondary_interfaces.value.network_card_index, null)
 private_ip_address_count = try(secondary_interfaces.value.private_ip_address_count, null)
 private_ip_addresses = try(secondary_interfaces.value.private_ip_addresses, null)
 secondary_subnet_id = try(secondary_interfaces.value.secondary_subnet_id, null)
 }
 }

 # Launch-time tags propagated to instances/volumes (var.tags + caller overrides).
 dynamic "tag_specifications" {
 for_each = local.effective_tag_specifications
 content {
 resource_type = tag_specifications.key
 tags = tag_specifications.value
 }
 }

 # Tags on the launch template resource itself.
 tags = var.tags
}
