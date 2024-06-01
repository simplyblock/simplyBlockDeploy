resource "aws_apigatewayv2_api" "graylog_api" {
  name          = "${terraform.workspace}-simplyblock-mgmt-api-graylog"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "graylog" {
  api_id    = aws_apigatewayv2_api.graylog_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.graylog_integration.id}"
}

resource "aws_apigatewayv2_integration" "graylog_integration" {
  api_id             = aws_apigatewayv2_api.graylog_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.vpc_link.id
  integration_uri    = aws_service_discovery_service.graylog_service.arn
}

resource "aws_service_discovery_service" "graylog_service" {
  name         = "${terraform.workspace}-simplyblock-graylog-svc"
  namespace_id = aws_service_discovery_http_namespace.mgmt_api.id
  type         = "HTTP"
}

resource "aws_service_discovery_instance" "graylog_endpoint" {
  instance_id = var.mgmt_node_instance_id
  service_id  = aws_service_discovery_service.graylog_service.id

  attributes = {
    AWS_INSTANCE_IPV4 = var.mgmt_node_private_ip
    AWS_INSTANCE_PORT = "9000"
  }
}

resource "aws_apigatewayv2_stage" "graylog" {
  api_id      = aws_apigatewayv2_api.graylog_api.id
  name        = "$default"
  auto_deploy = true
}

output "graylog_invoke_url" {
  value = "https://${aws_apigatewayv2_api.graylog_api.id}.execute-api.${var.region}.amazonaws.com/"
}
