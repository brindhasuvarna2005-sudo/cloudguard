# ============================================================
# Phase 7 additions — Dashboard (S3 static site + API Gateway + Lambda)
# ============================================================

# ---------- S3 bucket for the static dashboard site ----------
resource "aws_s3_bucket" "dashboard_site" {
  bucket = "cloudguard-dashboard-042186225776"
  tags   = { Project = "cloudguard" }
}

resource "aws_s3_bucket_public_access_block" "dashboard_site_access" {
  bucket                  = aws_s3_bucket.dashboard_site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "dashboard_site_config" {
  bucket = aws_s3_bucket.dashboard_site.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "dashboard_site_policy" {
  bucket = aws_s3_bucket.dashboard_site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.dashboard_site.arn}/*"
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.dashboard_site_access]
}

# ---------- Dashboard API Lambda (read-only, scans audit_log) ----------
resource "aws_iam_role" "dashboard_lambda_role" {
  name = "cloudguard-dashboard-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Project = "cloudguard" }
}

resource "aws_iam_role_policy_attachment" "dashboard_lambda_basic_logs" {
  role       = aws_iam_role.dashboard_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dashboard_lambda_scan_policy" {
  name = "cloudguard-dashboard-lambda-scan-policy"
  role = aws_iam_role.dashboard_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Scan"]
        Resource = aws_dynamodb_table.audit_log.arn
      }
    ]
  })
}

data "archive_file" "dashboard_api_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/dashboard_api.py"
  output_path = "${path.module}/lambdas/dashboard_api.zip"
}

resource "aws_lambda_function" "dashboard_api" {
  function_name    = "cloudguard-dashboard-api"
  role             = aws_iam_role.dashboard_lambda_role.arn
  handler          = "dashboard_api.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.dashboard_api_zip.output_path
  source_code_hash = data.archive_file.dashboard_api_zip.output_base64sha256

  environment {
    variables = {
      AUDIT_TABLE = aws_dynamodb_table.audit_log.name
    }
  }

  tags = { Project = "cloudguard" }
}

# ---------- API Gateway (HTTP API) fronting the dashboard Lambda ----------
resource "aws_apigatewayv2_api" "dashboard_http_api" {
  name          = "cloudguard-dashboard-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_integration" "dashboard_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.dashboard_http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dashboard_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dashboard_findings_route" {
  api_id    = aws_apigatewayv2_api.dashboard_http_api.id
  route_key = "GET /findings"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "dashboard_default_stage" {
  api_id      = aws_apigatewayv2_api.dashboard_http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard_http_api.execution_arn}/*/*"
}

# ---------- Upload the dashboard HTML, with the API URL baked in ----------
resource "aws_s3_object" "dashboard_index" {
  bucket       = aws_s3_bucket.dashboard_site.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/website/index.html.tpl", {
    api_url = aws_apigatewayv2_api.dashboard_http_api.api_endpoint
  })
}

output "dashboard_website_url" {
  value = aws_s3_bucket_website_configuration.dashboard_site_config.website_endpoint
}

output "dashboard_api_url" {
  value = aws_apigatewayv2_api.dashboard_http_api.api_endpoint
}
