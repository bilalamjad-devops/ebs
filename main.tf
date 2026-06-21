terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.74.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1" # Set your preferred target AWS region
}

# --- IAM Role for Lambda ---
# This role allows the Lambda function to assume execution permissions
resource "aws_iam_role" "snapshot_cleaner_role" {
  name = "SnapshotCleanerLambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# --- IAM Policy for Permissions ---
# Grants explicit permissions to query images, manage snapshots, and write CloudWatch logs
resource "aws_iam_role_policy" "snapshot_cleaner_policy" {
  name = "SnapshotCleanerLambdaPolicy"
  role = aws_iam_role.snapshot_cleaner_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot",
        "ec2:DescribeImages",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

# --- Zip Code Package ---
# Dynamically packages the Python microservice script into a deployment zip archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/python/delete_unused_snapshots.py"
  output_path = "${path.module}/python/delete_unused_snapshots.zip"
}

# --- AWS Lambda Function ---
# Serverless compute block containing the execution logic with 5 minutes timeout threshold
resource "aws_lambda_function" "snapshot_cleaner_lambda" {
  function_name    = "DeleteUnusedSnapshots"
  role             = aws_iam_role.snapshot_cleaner_role.arn
  handler          = "delete_unused_snapshots.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300 
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# --- EventBridge Rule: Lab Testing Schedule (Runs every 5 minutes) ---
resource "aws_cloudwatch_event_rule" "cleanup_schedule" {
  name        = "ebs-snapshot-cleanup-lab-schedule"
  description = "Triggers Lambda every 5 minutes for stable lab testing"
  
  schedule_expression = "rate(5 minutes)" 
}

# --- EventBridge Target assignment ---
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cleanup_schedule.name
  target_id = "SnapshotCleanerTarget"
  arn       = aws_lambda_function.snapshot_cleaner_lambda.arn
}

# --- Lambda Permission Resource mapping ---
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleaner_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_schedule.arn
}
