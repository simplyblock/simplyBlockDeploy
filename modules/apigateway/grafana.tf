resource "aws_apigatewayv2_api" "grafana_api" {
  name          = "${terraform.workspace}-simplyblock-mgmt-api-grafana"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "grafana" {
  api_id    = aws_apigatewayv2_api.grafana_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.grafana_integration.id}"
}

resource "aws_apigatewayv2_integration" "grafana_integration" {
  api_id             = aws_apigatewayv2_api.grafana_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.vpc_link.id
  integration_uri    = aws_service_discovery_service.grafana_service.arn
}

resource "aws_service_discovery_service" "grafana_service" {
  name         = "${terraform.workspace}-simplyblock-grafana-svc"
  namespace_id = aws_service_discovery_http_namespace.mgmt_api.id
  type         = "HTTP"
}

resource "aws_service_discovery_instance" "grafana_endpoint" {
  instance_id = var.mgmt_node_instance_id
  service_id  = aws_service_discovery_service.grafana_service.id

  attributes = {
    AWS_INSTANCE_IPV4 = var.mgmt_node_private_ip
    AWS_INSTANCE_PORT = "3000"
  }
}

resource "aws_apigatewayv2_stage" "grafana" {
  api_id      = aws_apigatewayv2_api.grafana_api.id
  name        = "$default"
  auto_deploy = true
}

output "grafana_invoke_url" {
  value = "https://${aws_apigatewayv2_api.grafana_api.id}.execute-api.${var.region}.amazonaws.com/"
}
