# ============================================================
# Phase 5 additions — SNS alerts + CodeBuild auto-remediation
# ============================================================

# ---------- SNS topic for high-risk drift alerts ----------
resource "aws_sns_topic" "drift_alerts" {
  name = "cloudguard-drift-alerts"
  tags = { Project = "cloudguard" }
}

resource "aws_sns_topic_subscription" "drift_alerts_email" {
  topic_arn = aws_sns_topic.drift_alerts.arn
  protocol  = "email"
  endpoint  = "brindhasuvarna2005@gmail.com"
}

# ---------- Package current .tf files + buildspec as CodeBuild source ----------
data "archive_file" "codebuild_source_zip" {
  type        = "zip"
  output_path = "${path.module}/codebuild_source.zip"

  source {
    content  = file("${path.module}/main.tf")
    filename = "main.tf"
  }
  source {
    content  = file("${path.module}/backend.tf")
    filename = "backend.tf"
  }
  source {
    content  = file("${path.module}/lambda.tf")
    filename = "lambda.tf"
  }
  source {
    content  = file("${path.module}/remediation.tf")
    filename = "remediation.tf"
  }
  source {
    content  = file("${path.module}/outputs.tf")
    filename = "outputs.tf"
  }
  source {
    content  = <<-EOT
      version: 0.2
      phases:
        install:
          commands:
            - curl -s -o terraform.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
            - unzip -o terraform.zip -d /usr/local/bin
        build:
          commands:
            - terraform init -input=false
            - terraform apply -target=$TARGET_RESOURCE -auto-approve
    EOT
    filename = "buildspec.yml"
  }
}

resource "aws_s3_object" "codebuild_source" {
  bucket = "cloudguard-tfstate-042186225776"
  key    = "cloudguard/app/codebuild_source.zip"
  source = data.archive_file.codebuild_source_zip.output_path
  etag   = filemd5(data.archive_file.codebuild_source_zip.output_path)
}

# ---------- CodeBuild execution role ----------
resource "aws_iam_role" "codebuild_role" {
  name = "cloudguard-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })

  tags = { Project = "cloudguard" }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "cloudguard-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::cloudguard-tfstate-042186225776",
          "arn:aws:s3:::cloudguard-tfstate-042186225776/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:ap-south-1:042186225776:table/cloudguard-tf-lock"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutBucketTagging", "s3:GetBucketTagging",
          "s3:PutBucketVersioning", "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::cloudguard-demo-042186225776"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable", "dynamodb:TagResource", "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource", "dynamodb:CreateTable", "dynamodb:DeleteTable"
        ]
        Resource = "arn:aws:dynamodb:ap-south-1:042186225776:table/cloudguard-demo-table"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags"]
        Resource = "arn:aws:iam::042186225776:role/cloudguard-demo-role"
      }
    ]
  })
}

# ---------- CodeBuild project ----------
resource "aws_codebuild_project" "drift_remediation" {
  name          = "cloudguard-drift-remediation"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 10

  source {
    type     = "S3"
    location = "cloudguard-tfstate-042186225776/cloudguard/app/codebuild_source.zip"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TARGET_RESOURCE"
      value = "none"
    }
  }

  tags = { Project = "cloudguard" }
}

# ---------- Let the Lambda trigger CodeBuild and publish to SNS ----------
resource "aws_iam_role_policy" "lambda_remediation_policy" {
  name = "cloudguard-lambda-remediation-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild"]
        Resource = aws_codebuild_project.drift_remediation.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.drift_alerts.arn
      }
    ]
  })
}

output "sns_topic_arn" {
  value = aws_sns_topic.drift_alerts.arn
}

output "codebuild_project_name" {
  value = aws_codebuild_project.drift_remediation.name
}
