output "storage_private_ips" {
  value = join(" ", [for inst in aws_instance.storage_nodes : inst.private_ip])
}

output "sec_storage_private_ips" {
  value = join(" ", [for inst in aws_instance.sec_storage_nodes : inst.private_ip])
}

output "mgmt_public_ips" {
  value = join(" ", aws_instance.mgmt_nodes[*].public_ip)
}

output "mgmt_private_ips" {
  value = join(" ", aws_instance.mgmt_nodes[*].private_ip)
}

output "extra_nodes_public_ips" {
  value = join(" ", aws_instance.extra_nodes[*].public_ip)
}

output "extra_nodes_private_ips" {
  value = join(" ", aws_instance.extra_nodes[*].private_ip)
}

output "key_name" {
  value = local.selected_key_name
}

# output "secret_value" {
#   sensitive = true
#   value     = data.aws_secretsmanager_secret_version.simply.secret_string
# }

output "mgmt_node_details" {
  value = { for i, instance in aws_instance.mgmt_nodes :
    instance.tags["Name"] => {
      type       = instance.instance_type
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
    }
  }
  description = "Details of the mgmt nodes."
}

output "storage_node_details" {
  value = { for i, instance in aws_instance.storage_nodes :
    instance.tags["Name"] => {
      type              = instance.instance_type
      public_ip         = instance.public_ip
      private_ip        = instance.private_ip
      availability_zone = instance.availability_zone
    }
  }
  description = "Details of the storage node nodes."
}

output "storage_public_ips" {
  value = join(" ", [for inst in aws_instance.storage_nodes : inst.public_ip])
}

output "sec_storage_node_details" {
  value = { for i, instance in aws_instance.sec_storage_nodes :
    instance.tags["Name"] => {
      type              = instance.instance_type
      public_ip         = instance.public_ip
      private_ip        = instance.private_ip
      availability_zone = instance.availability_zone
    }
  }
  description = "Details of the secondary storage node nodes."
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "api_invoke_url" {
  value = try(module.apigatewayendpoint[0].api_invoke_url, "")
}

output "grafana_invoke_url" {
  value = "${try(module.apigatewayendpoint[0].api_invoke_url, "")}grafana"
}

output "graylog_invoke_url" {
  value = "${try(module.apigatewayendpoint[0].api_invoke_url, "")}graylog"
}
