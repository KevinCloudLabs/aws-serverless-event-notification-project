output "api_endpoint" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "s3_bucket_name" {
  description = "S3 bucket storing events"
  value       = aws_s3_bucket.events.bucket
}

output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.events.arn
}
