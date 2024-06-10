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
  integration_uri    = aws_lb_listener.graylog_lb_listener.arn

}

resource "aws_apigatewayv2_stage" "graylog" {
  api_id      = aws_apigatewayv2_api.graylog_api.id
  name        = "$default"
  auto_deploy = true
}

# Create Load Balancer
resource "aws_lb" "graylog_internal_lb" {
  name               = "${terraform.workspace}-graylog-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.public_subnets
  security_groups    = [var.api_gateway_id]
}

# Create Target Group
resource "aws_lb_target_group" "graylog_target" {
  name     = "${terraform.workspace}-graylog-target-group"
  port     = 80
  protocol = "TCP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_target_group_attachment" "graylog_target_attachment" {
  count              = length(var.mgmt_node_instance_ids)
  target_group_arn   = aws_lb_target_group.graylog_target.arn
  target_id          = var.mgmt_node_instance_ids[count.index]
  port               = 9000
}

# Create Listener
resource "aws_lb_listener" "graylog_lb_listener" {
  load_balancer_arn = aws_lb.graylog_internal_lb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.graylog_target.arn
  }
}

output "graylog_invoke_url" {
  value = "https://${aws_apigatewayv2_api.graylog_api.id}.execute-api.${var.region}.amazonaws.com/"
}
