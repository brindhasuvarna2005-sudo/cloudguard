# 1. S3 Bucket
resource "aws_s3_bucket" "demo_bucket" {
  bucket = "cloudguard-demo-042186225776"

  tags = {
    Environment = "dev"
    Project     = "cloudguard"
  }
}

resource "aws_s3_bucket_versioning" "demo_bucket_versioning" {
  bucket = aws_s3_bucket.demo_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. DynamoDB Table
resource "aws_dynamodb_table" "demo_table" {
  name         = "cloudguard-demo-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = "dev"
    Project     = "cloudguard"
  }
}

# 3. IAM Role
resource "aws_iam_role" "demo_role" {
  name = "cloudguard-demo-role"

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
    Project = "cloudguard"
  }
}

# 4. Security Group
resource "aws_security_group" "demo_sg" {
  name        = "cloudguard-demo-sg"
  description = "Demo security group for drift detection"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "dev"
    Project     = "cloudguard"
  }
}