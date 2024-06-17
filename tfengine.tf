
data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}


resource "aws_autoscaling_group" "tfengine_asg" {
  min_size             = 1
  max_size             = 1
  desired_capacity     = 1
  vpc_zone_identifier  = [module.vpc.private_subnets[0]]
  launch_configuration = aws_launch_configuration.tfengine_lc.name
  tag {
    key                 = "Name"
    value               = "tfengine"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "tfengine_lc" {
  image_id             = data.aws_ami.this.id
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.tfengine_sg.id]
  iam_instance_profile = aws_iam_instance_profile.tfengine.name
  user_data            = <<EOF
#!/bin/bash
dnf install -y docker
systemctl enable docker
systemctl start docker
dnf install -y amazon-ecr-credential-helper
EOF
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
  bucket = "simplyblock-tfengine-logs-${random_id.id.hex}"
}

# A policy to allow the instance to put logs in the bucket
resource "aws_iam_policy" "tfengine_logs_policy" {
  name        = "tfengine_logs_policy"
  description = "S3 policy for tfengine logs"
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
                "arn:aws:s3:::simplyblock-terraform-state-bucket/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::simplyblock-terraform-state-bucket"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "tfengine_ecr_policy" {
  name        = "tfengine_ecr_policy"
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
  name        = "tfengine_dynamodb_policy"
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

# Attach the policy to the instance profile
resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.tfengine.name
}

resource "aws_iam_role_policy_attachment" "sbdeployPolicy" {
  policy_arn = "arn:aws:iam::565979732541:policy/sbdeployPolicy"
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
