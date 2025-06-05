

data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_autoscaling_group" "tfengine_asg" {
  min_size            = 0
  max_size            = 1
  desired_capacity    = 0
  vpc_zone_identifier = [module.vpc.private_subnets[0]]
  tag {
    key                 = "Name"
    value               = "${terraform.workspace}-tfengine"
    propagate_at_launch = true
  }
  tag {
    key                 = "long-term-test"
    value               = "true"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
  launch_template {
    id      = aws_launch_template.tfengine_lc.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "tfengine_lc" {
  name_prefix   = "tfengine"
  image_id      = data.aws_ami.this.id
  instance_type = "t3.medium"

  lifecycle {
    create_before_destroy = true
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.tfengine_sg.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.tfengine.name
  }

  user_data = base64encode(<<EOF
#!/bin/bash
dnf install -y docker
systemctl enable docker
systemctl start docker
dnf install -y amazon-ecr-credential-helper
mkdir -p ~/.docker
echo '{"credsStore": "ecr-login"}' > ~/.docker/config.json
EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${terraform.workspace}-tfengine"
    }
  }
}

resource "aws_security_group" "tfengine_sg" {
  description = "tfEngine security group"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "tfengine" {
  role = aws_iam_role.tfengine.name
}

resource "aws_iam_role" "tfengine" {

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

# random 5 bit
resource "random_id" "id" {
  byte_length = 5
}

# A bucket for store terraform execution output logs
resource "aws_s3_bucket" "tfengine_logs" {
  bucket        = "simplyblock-tfengine-logs-${random_id.id.hex}"
  force_destroy = true
}

# A policy to allow the instance to put logs in the bucket
resource "aws_iam_policy" "tfengine_logs_policy" {
  name        = "${terraform.workspace}-tfengine_logs_policy"
  description = "S3 policy for tfengine ${terraform.workspace} logs"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": [
                "${aws_s3_bucket.tfengine_logs.arn}/*",
                "arn:aws:s3:::${var.tf_state_bucket_name}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${var.tf_state_bucket_name}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "tfengine_ecr_policy" {
  name        = "${terraform.workspace}-tfengine_ecr_policy"
  description = "S3 policy for tfengine ecr"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetAuthorizationToken"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "tfengine_dynamodb_policy" {
  name        = "${terraform.workspace}-tfengine_dynamodb_policy"
  description = "S3 policy for tfengine dynamodb"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "sbdeployPolicy" {
  name        = "${terraform.workspace}-sbdeployPolicyy"
  description = "sbdeployPolicy"
  policy      = file("${path.module}/aws-policy.json")
}

# Attach the policy to the instance profile
resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.tfengine.name
}

# NOTE: Terraform uses the same role that we use to deploy the cluster to the customer's account
resource "aws_iam_role_policy_attachment" "sbdeployPolicy" {
  policy_arn = aws_iam_policy.sbdeployPolicy.arn
  role       = aws_iam_role.tfengine.name
}

# attach policy
resource "aws_iam_role_policy_attachment" "s3policy" {
  policy_arn = aws_iam_policy.tfengine_logs_policy.arn
  role       = aws_iam_role.tfengine.name
}

resource "aws_iam_role_policy_attachment" "ecrpolicy" {
  policy_arn = aws_iam_policy.tfengine_ecr_policy.arn
  role       = aws_iam_role.tfengine.name
}

resource "aws_iam_role_policy_attachment" "tfengine_dynamodb_policy" {
  policy_arn = aws_iam_policy.tfengine_dynamodb_policy.arn
  role       = aws_iam_role.tfengine.name
}

output "tfengine_logs" {
  value = try(aws_s3_bucket.tfengine_logs.bucket, "")
}
