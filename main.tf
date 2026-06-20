terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Aap apna preferred region set kar sakte hain
}

# 1. Package the Python source file automatically on run execution
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/stale_snapshot_cleaner.py"
  output_path = "${path.module}/stale_snapshot_cleaner.zip"
}

# 2. Serverless Execution Core Identity Mapping
resource "aws_iam_role" "lambda_role" {
  name = "ebs-snapshot-cleaner-execution-role"

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
}

# 3. Least-Privilege IAM Policy Block to secure the automation track
resource "aws_iam_policy" "lambda_policy" {
  name        = "ebs-snapshot-cleaner-execution-policy"
  description = "Allows engine runtime to list configurations and drop orphaned snapshots safely."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
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

# 4. Bind policy context to runtime core role profile
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# 5. The Core Serverless Lambda Resource Lifecycle block
resource "aws_lambda_function" "snapshot_cleaner" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "automated-ebs-snapshot-cleaner"
  role             = aws_iam_role.lambda_role.arn
  handler          = "stale_snapshot_cleaner.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60 
}

# 6. EventBridge Orchestrator Schedule - Set to trigger every 5 minutes for direct laboratory validation
resource "aws_cloudwatch_event_rule" "cleanup_trigger" {
  name                = "ebs-snapshot-cleaner-testing-schedule"
  description         = "FinOps optimization engine cron pacing loop set to execute every 5 minutes."
  schedule_expression = "rate(5 minutes)"
}

# 7. Bind Orchestrator event emission target channel to the Lambda system
resource "aws_cloudwatch_event_target" "target_lambda" {
  rule      = aws_cloudwatch_event_rule.cleanup_trigger.name
  target_id = "TriggerSnapshotCleanerLambdaRoutine"
  arn       = aws_lambda_function.snapshot_cleaner.arn
}

# 8. Define resource invocation access capabilities from EventBridge over to Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeOrchestrator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleaner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_trigger.arn
}

# --- Runtime Status Outputs ---
output "deployed_lambda_arn" {
  value       = aws_lambda_function.snapshot_cleaner.arn
  description = "Target Resource Access Signature map for the serverless automation block."
}

output "active_eventbridge_rule" {
  value       = aws_cloudwatch_event_rule.cleanup_trigger.arn
  description = "Target Resource Access Signature map for the cloud watch chron engine trigger."
}
