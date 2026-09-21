# ============================================================
# Phase 4 additions — Drift Detector Lambda + EventBridge
# ============================================================

resource "aws_dynamodb_table" "audit_log" {
  name         = "cloudguard-audit-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = {
    Environment = "dev"
    Project     = "cloudguard"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "cloudguard-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = { Project = "cloudguard" }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_drift_policy" {
  name = "cloudguard-lambda-drift-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::cloudguard-tfstate-042186225776/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketTagging"]
        Resource = "arn:aws:s3:::cloudguard-demo-042186225776"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeTable", "dynamodb:ListTagsOfResource"]
        Resource = "arn:aws:dynamodb:ap-south-1:042186225776:table/cloudguard-demo-table"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:ListRoleTags"]
        Resource = "arn:aws:iam::042186225776:role/cloudguard-demo-role"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
            {
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeTable", "dynamodb:ListTagsOfResource", "dynamodb:CreateTable"]
        Resource = "arn:aws:dynamodb:ap-south-1:042186225776:table/cloudguard-demo-table"
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild"]
        Resource = aws_codebuild_project.drift_remediation.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutBucketTagging"]
        Resource = "arn:aws:s3:::cloudguard-demo-042186225776"
      },
      {
              
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.audit_log.arn
      
      }
    ]
  })
}

data "archive_file" "drift_detector_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/drift_detector.py"
  output_path = "${path.module}/lambdas/drift_detector.zip"
}

resource "aws_lambda_function" "drift_detector" {
  function_name    = "cloudguard-drift-detector"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "drift_detector.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.drift_detector_zip.output_path
  source_code_hash = data.archive_file.drift_detector_zip.output_base64sha256

  environment {
    variables = {
      STATE_BUCKET = "cloudguard-tfstate-042186225776"
      STATE_KEY    = "cloudguard/app/desired_state.json"
      DEMO_BUCKET  = "cloudguard-demo-042186225776"
      DEMO_TABLE   = "cloudguard-demo-table"
      DEMO_ROLE    = "cloudguard-demo-role"
      AUDIT_TABLE  = aws_dynamodb_table.audit_log.name
      CODEBUILD_PROJECT = aws_codebuild_project.drift_remediation.name
      SNS_TOPIC_ARN     = aws_sns_topic.drift_alerts.arn
    }
  }

  tags = { Project = "cloudguard" }
}

resource "aws_cloudwatch_event_rule" "drift_schedule" {
  name                = "cloudguard-drift-schedule"
  description         = "Triggers drift detection every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "drift_lambda_target" {
  rule      = aws_cloudwatch_event_rule.drift_schedule.name
  target_id = "cloudguard-drift-detector"
  arn       = aws_lambda_function.drift_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.drift_schedule.arn
}

output "audit_log_table_name" {
  value = aws_dynamodb_table.audit_log.id
}

output "lambda_function_name" {
  value = aws_lambda_function.drift_detector.function_name
}