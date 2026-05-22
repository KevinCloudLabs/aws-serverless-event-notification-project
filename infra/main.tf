provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ================================================
# S3
# ================================================

resource "aws_s3_bucket" "events" {
  bucket        = "${var.project_name}-events-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-events-bucket" }
}

resource "aws_s3_bucket_public_access_block" "events" {
  bucket                  = aws_s3_bucket.events.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "events_json" {
  bucket       = aws_s3_bucket.events.id
  key          = "events.json"
  content      = jsonencode({ events = [] })
  content_type = "application/json"
}

# ================================================
# SNS
# ================================================

resource "aws_sns_topic" "events" {
  name = "${var.project_name}-announcements"
  tags = { Name = "${var.project_name}-sns-topic" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "email"
  endpoint  = var.subscriber_email
}

# ================================================
# IAM
# ================================================

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.events.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ================================================
# LAMBDA
# ================================================

data "archive_file" "process_event" {
  type        = "zip"
  source_file = "${path.module}/lambda/process_event.py"
  output_path = "${path.module}/lambda/process_event.zip"
}

data "archive_file" "get_events" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_events.py"
  output_path = "${path.module}/lambda/get_events.zip"
}

resource "aws_lambda_function" "process_event" {
  filename         = data.archive_file.process_event.output_path
  function_name    = "${var.project_name}-process-event"
  role             = aws_iam_role.lambda.arn
  handler          = "process_event.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.process_event.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.events.bucket
      SNS_TOPIC_ARN = aws_sns_topic.events.arn
    }
  }

  tags = { Name = "${var.project_name}-process-event" }
}

resource "aws_lambda_function" "get_events" {
  filename         = data.archive_file.get_events.output_path
  function_name    = "${var.project_name}-get-events"
  role             = aws_iam_role.lambda.arn
  handler          = "get_events.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.get_events.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.events.bucket
    }
  }

  tags = { Name = "${var.project_name}-get-events" }
}

# ================================================
# API GATEWAY
# ================================================

resource "aws_apigatewayv2_api" "events" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }

  tags = { Name = "${var.project_name}-api" }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.events.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "process_event" {
  api_id                 = aws_apigatewayv2_api.events.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.process_event.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_events" {
  api_id                 = aws_apigatewayv2_api.events.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_events.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_events" {
  api_id    = aws_apigatewayv2_api.events.id
  route_key = "POST /events"
  target    = "integrations/${aws_apigatewayv2_integration.process_event.id}"
}

resource "aws_apigatewayv2_route" "get_events" {
  api_id    = aws_apigatewayv2_api.events.id
  route_key = "GET /events"
  target    = "integrations/${aws_apigatewayv2_integration.get_events.id}"
}

resource "aws_lambda_permission" "process_event" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_event.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.events.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_events" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_events.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.events.execution_arn}/*/*"
}
