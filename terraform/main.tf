terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "ssh_key_name" {
  description = "Name of SSH key pair for EC2 access"
  type        = string
  default     = "housing-ml-key"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2"
  type        = string
  default     = "0.0.0.0/0"  # Change this to your IP for better security
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repository to clone onto EC2 (e.g. https://github.com/org/repo.git)"
  type        = string
}

# ECR Repository for training Docker image
resource "aws_ecr_repository" "training" {
  name                 = "housing-ml-training"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "Housing ML Training Image"
    Environment = var.environment
  }
}

# S3 Bucket for ML artifacts
resource "aws_s3_bucket" "ml_bucket" {
  bucket = "house-forecast"

  tags = {
    Name        = "Housing ML Bucket"
    Environment = var.environment
    Project     = "housing-regression-mle"
  }
}

resource "aws_s3_bucket_versioning" "ml_bucket_versioning" {
  bucket = aws_s3_bucket.ml_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "ml_bucket_public_access" {
  bucket = aws_s3_bucket.ml_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC - Use default VPC for free tier
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# Security Group for EC2 Instance
resource "aws_security_group" "ec2_ml" {
  name        = "housing-ml-ec2-sg-${var.environment}"
  description = "Security group for ML EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH access"
  }

  # API access
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "FastAPI access"
  }

  # HTTP (optional, for future web interface)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "Housing ML EC2 Security Group"
    Environment = var.environment
  }
}

# CloudWatch Log Group for EC2
resource "aws_cloudwatch_log_group" "ec2_ml" {
  name              = "/ec2/housing-ml"
  retention_in_days = 30

  tags = {
    Name        = "Housing ML EC2 Logs"
    Environment = var.environment
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_ml_role" {
  name = "housing-ec2-ml-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "EC2 ML Role"
    Environment = var.environment
  }
}

# S3 Access Policy for EC2
resource "aws_iam_policy" "s3_access_policy" {
  name        = "housing-s3-access-policy-${var.environment}"
  description = "Allow EC2 instance to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_bucket.arn,
          "${aws_s3_bucket.ml_bucket.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs Policy for EC2
resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name        = "housing-cloudwatch-logs-policy-${var.environment}"
  description = "Allow EC2 instance to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.ec2_ml.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_policy" {
  role       = aws_iam_role.ec2_ml_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_ml_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

# SSM Managed Instance Core (for Systems Manager Session Manager)
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_ml_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR pull policy — allows ephemeral training EC2 to pull the training image
resource "aws_iam_policy" "ecr_pull_policy" {
  name        = "housing-ecr-pull-policy-${var.environment}"
  description = "Allow EC2 to pull training images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_policy" {
  role       = aws_iam_role.ec2_ml_role.name
  policy_arn = aws_iam_policy.ecr_pull_policy.arn
}

# SSM SendCommand policy — allows the training container to restart the API EC2
resource "aws_iam_policy" "ec2_ssm_send_policy" {
  name        = "housing-ec2-ssm-send-policy-${var.environment}"
  description = "Allow EC2 to send SSM commands (for training container to restart API)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_send_policy" {
  role       = aws_iam_role.ec2_ml_role.name
  policy_arn = aws_iam_policy.ec2_ssm_send_policy.arn
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_ml_profile" {
  name = "housing-ec2-ml-profile-${var.environment}"
  role = aws_iam_role.ec2_ml_role.name

  tags = {
    Name        = "EC2 ML Instance Profile"
    Environment = var.environment
  }
}

# EC2 Instance for ML workloads
resource "aws_instance" "ml_instance" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"  # Free tier eligible

  iam_instance_profile = aws_iam_instance_profile.ec2_ml_profile.name
  key_name             = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.ec2_ml.id]

  user_data = templatefile("${path.module}/user_data.sh", {
    s3_bucket       = aws_s3_bucket.ml_bucket.bucket
    aws_region      = var.aws_region
    log_group       = aws_cloudwatch_log_group.ec2_ml.name
    github_repo_url = var.github_repo_url
  })

  root_block_device {
    volume_size = 20  # GB - Adjust based on your needs
    volume_type = "gp3"
  }

  tags = {
    Name        = "Housing ML Instance"
    Environment = var.environment
    Project     = "housing-regression-mle"
  }
}

# Elastic IP for consistent access
resource "aws_eip" "ml_instance_eip" {
  instance = aws_instance.ml_instance.id
  domain   = "vpc"

  tags = {
    Name        = "Housing ML Instance EIP"
    Environment = var.environment
  }
}

# EventBridge Rule for Scheduled Training
resource "aws_cloudwatch_event_rule" "training_schedule" {
  name                = "housing-training-schedule-${var.environment}"
  description         = "Trigger housing model training monthly"
  schedule_expression = "cron(0 2 1 * ? *)" # 2 AM on 1st of each month (UTC)

  tags = {
    Name        = "Training Schedule Rule"
    Environment = var.environment
  }
}

# Lambda function to trigger training on EC2
resource "aws_iam_role" "lambda_training_role" {
  name = "housing-lambda-training-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "Lambda Training Trigger Role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "lambda_training_policy" {
  name        = "housing-lambda-training-policy-${var.environment}"
  description = "Allow Lambda to launch ephemeral training EC2"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:RunInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        # PassRole allows Lambda to attach the EC2 instance profile to the ephemeral instance
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.ec2_ml_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_training_policy_attach" {
  role       = aws_iam_role.lambda_training_role.name
  policy_arn = aws_iam_policy.lambda_training_policy.arn
}

# Lambda function code (inline for simplicity)
resource "aws_lambda_function" "trigger_training" {
  filename      = "${path.module}/lambda_trigger.zip"
  function_name = "housing-trigger-training-${var.environment}"
  role          = aws_iam_role.lambda_training_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      S3_BUCKET             = aws_s3_bucket.ml_bucket.bucket
      ECR_IMAGE_URI         = "${aws_ecr_repository.training.repository_url}:latest"
      INSTANCE_PROFILE_NAME = aws_iam_instance_profile.ec2_ml_profile.name
      SECURITY_GROUP_ID     = aws_security_group.ec2_ml.id
      SUBNET_ID             = tolist(data.aws_subnets.default.ids)[0]
      AMI_ID                = data.aws_ami.amazon_linux_2023.id
      API_INSTANCE_ID       = aws_instance.ml_instance.id
    }
  }

  tags = {
    Name        = "Housing Training Trigger"
    Environment = var.environment
  }
}

# EventBridge target for Lambda
resource "aws_cloudwatch_event_target" "training_target" {
  rule      = aws_cloudwatch_event_rule.training_schedule.name
  target_id = "TriggerTraining"
  arn       = aws_lambda_function.trigger_training.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_training.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.training_schedule.arn
}

# Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for ML artifacts"
  value       = aws_s3_bucket.ml_bucket.bucket
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ml_instance.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance (Elastic IP)"
  value       = aws_eip.ml_instance_eip.public_ip
}

output "api_url" {
  description = "URL of the FastAPI service"
  value       = "http://${aws_eip.ml_instance_eip.public_ip}:8000"
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.ml_instance_eip.public_ip}"
}

output "iam_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2_ml_role.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for training trigger"
  value       = aws_lambda_function.trigger_training.function_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the training Docker image"
  value       = aws_ecr_repository.training.repository_url
}

output "security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2_ml.id
}

