resource "aws_apigatewayv2_api" "simplyblock_api" {
  name          = "${terraform.workspace}-simplyblock-mgmt-api-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "vpc_link" {
  name               = "${terraform.workspace}-simplyblock-vpclink"
  security_group_ids = [var.container_inst_sg_id]
  subnet_ids         = var.public_subnets
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.simplyblock_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.root_integration.id}"
}

resource "aws_apigatewayv2_integration" "root_integration" {
  api_id             = aws_apigatewayv2_api.simplyblock_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.vpc_link.id
  integration_uri    = aws_service_discovery_service.root_service.arn
}

resource "aws_service_discovery_http_namespace" "mgmt_api" {
  name = "${terraform.workspace}-simplyblock-mgmt-api"
}

resource "aws_service_discovery_service" "root_service" {
  name         = "${terraform.workspace}-simplyblock-root-svc"
  namespace_id = aws_service_discovery_http_namespace.mgmt_api.id
  type         = "HTTP"
}

resource "aws_service_discovery_instance" "root_endpoint" {
  instance_id = var.mgmt_node_instance_id
  service_id  = aws_service_discovery_service.root_service.id

  attributes = {
    AWS_INSTANCE_IPV4 = var.mgmt_node_private_ip
    AWS_INSTANCE_PORT = "80"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.simplyblock_api.id
  name        = "$default"
  auto_deploy = true
}

output "api_invoke_url" {
  value = "https://${aws_apigatewayv2_api.simplyblock_api.id}.execute-api.${var.region}.amazonaws.com/"
}
