# resource "aws_efs_file_system" "efs" {
#   for_each = local.efs_file_systems

#   performance_mode = "generalPurpose"

#   tags = {
#     Name = "${aws_instance.mgmt_nodes[0].id}/monitoring_${each.value}"
#   }
# }

# resource "aws_efs_mount_target" "efs_mt" {
#   for_each = local.efs_file_systems

#   file_system_id  = aws_efs_file_system.efs[each.key].id
#   subnet_id       = module.vpc.private_subnets[local.az_index]
#   security_groups = [aws_security_group.mgmt_node_sg.id]

#   lifecycle {
#     ignore_changes = [
#       subnet_id,
#     ]
#   }
# }
