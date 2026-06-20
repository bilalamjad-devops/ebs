# Delete Unused AWS EBS Snapshots Automatically Using Terraform, EventBridge Scheduler, and AWS Lambda


https://github.com/mathesh-me/aws-cost-optimization/blob/main/README.md

Real-world companies hamesha aisi cleaning activities ko active production ya development hours ke baad chalati hain taake live environments par koi load na aaye. Friday ki night sabse standard time mana jata hai kyunki uske baad Saturday aur Sunday ko engineering teams off hoti hain.



Bhai, testing ke liye **5-minute rate expression** set karna sabse best choice hai—isse aapka time zaya nahi hoga aur screenshots fauran ready ho jayenge.

Jahan tak real-world companies ka sawal hai, companies hamesha aisi cleaning activities ko active production ya development hours ke baad chalati hain taake live environments par koi load na aaye. Friday ki night sabse standard time mana jata hai kyunki uske baad Saturday aur Sunday ko engineering teams off hoti hain.

Real companies aam tor par niche diye gaye timing strategies use karti hain:

---

### 1. Friday Night Timing Patterns (Enterprise Standards)

Companies apne primary development region ke local time ke mutabiq chalte hain:

* **11:00 PM Local Time:** Yeh sabse common scheduling window hai. Jab engineering teams apna kaam khatam karke ghar ja chuki hoti hain, to automatic jobs backup verify karke cleanup process shuru karti hain.
* **02:00 AM (Midnight/Early Saturday):** Agar company ke paas bohot heavy database assets ya thousands of snapshots hon, to wo is activity ko bilkul midnight par schedule karti hain taake active users ya logs par zero impact ho.

---

### 2. Cron Configuration for Enterprise vs Testing

Jab aap real industry vs testing environments ke liye schedule set karte hain, to Terraform resources mein bus expression ka farq hota hai:

#### Real Enterprise Configuration (Friday Night)

```hashicorp
# Friday Night at 11:00 PM UTC Trigger
resource "aws_cloudwatch_event_rule" "weekly_trigger" {
  name                = "ebs-snapshot-cleaner-schedule"
  schedule_expression = "cron(0 23 ? * FRI *)"
}

```

#### Hamari Lab Testing Configuration (Every 5 Minutes)

Aap apne lab testing ke liye `main.tf` ke resource block mein schedule expression ko change karke yeh text add karein:

```hashicorp
# Testing Schedule: Triggers every 5 minutes automatically
resource "aws_cloudwatch_event_rule" "weekly_trigger" {
  name                = "ebs-snapshot-cleaner-testing"
  schedule_expression = "rate(5 minutes)"
}

```

---

Bhai, 5-minute rate update ke baad, aap apni configuration files run karne ke liye ready hain.

Aap terminal par ja kar:

1. `terraform init` run karein.
2. `terraform apply --auto-approve` execute karke resources deploy karein.
3. Ek test instance bana kar uska snapshot lein, phir instance delete karke 5 minute wait karein taake Lambda khud trigger ho jaye.

Kya aap lab setup execute kar rahe hain? Screenshots ready hote hi batayiye ga, hum Medium post ka final draft complete karenge!



Bhai, yahan aapka complete layout ready hai. Isme humne testing ke liye **`rate(5 minutes)`** configure kar diya hai taake aapki lab fauran execute ho sake aur enterprise policies ke mutabiq saare resources integrate ho jayein.

Aapko sirf do files banani hain: ek script directory aur ek main deployment script.

---

### 1. The Core Automation Script

Apne project folder mein ek sub-folder banayein `python` ke naam se, aur usme yeh file save karein:
📂 **`python/stale_snapshot_cleaner.py`**

```python
import boto3
import botocore

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    print("--- Starting Automated EBS Snapshot Optimization Routine ---")
    
    # Fetch all snapshots owned by this current AWS account
    try:
        snapshots_response = ec2.describe_snapshots(OwnerIds=['self'])
        snapshots = snapshots_response.get('Snapshots', [])
    except Exception as e:
        print(f"Error fetching snapshots: {str(e)}")
        return {'statusCode': 500, 'body': 'Failed to fetch snapshots.'}
        
    print(f"Total snapshots discovered in this region: {len(snapshots)}")
    deleted_count = 0
    
    for snapshot in snapshots:
        snapshot_id = snapshot['SnapshotId']
        volume_id = snapshot.get('VolumeId')
        
        # Skip if snapshot doesn't have an associated volume metadata mapping
        if not volume_id:
            continue
            
        try:
            # Check if the baseline volume still exists in AWS
            ec2.describe_volumes(VolumeIds=[volume_id])
            print(f"Snapshot {snapshot_id} is active. Associated volume {volume_id} is live.")
            
        except botocore.exceptions.ClientError as e:
            # If the error code matches NotFound, the parent asset is gone
            if e.response['Error']['Code'] == 'InvalidVolume.NotFound':
                print(f"Orphaned Snapshot Detected: {snapshot_id} (Reason: Volume {volume_id} no longer exists).")
                try:
                    ec2.delete_snapshot(SnapshotId=snapshot_id)
                    print(f"Successfully purged stale snapshot: {snapshot_id}")
                    deleted_count += 1
                except Exception as del_err:
                    print(f"Failed to delete snapshot {snapshot_id}: {str(del_err)}")
            else:
                print(f"AWS API Error processing validation on volume {volume_id}: {str(e)}")
                
    print(f"--- Optimization Routine Finished. Total Stale Snapshots Purged: {deleted_count} ---")
    return {
        'statusCode': 200,
        'body': f'Optimization complete. Purged {deleted_count} stale snapshots.'
    }

```

---

### 2. The Infrastructure Deployment Engine

Apne primary root project folder mein yeh deployment manifest create karein:
📂 **`main.tf`**

```hashicorp
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
  source_file = "${path.module}/python/stale_snapshot_cleaner.py"
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

```

---

### 🚀 Lab Kaise Execute Karni Hai?

1. Terminal kholein aur `terraform init` karein.
2. Phir `terraform apply --auto-approve` chala kar stack deploy kar dein.
3. Ek test EC2 instance banayein, uske volume ka manual snapshot lein.
4. **EC2 instance ko terminate kar dein** (taake snapshot orphaned ho jaye).
5. 5-7 minutes wait karein, phir Amazon CloudWatch Logs dashboard par ja kar log streams check karein—aapko wahan snapshot delete hone ke verification status logs mil jayenge!

Bhai, aap ye lab test run karein, aur jaise hi aap screenshot frames capture kar lein, mujhe batayiyega, hum aapka agla grand ranking article document framework prepare karenge!



Prepare the Target: Create a Stale Snapshot (Manual)
This is the exact setup you did manually to provide a target for your Lambda function.

1. Launch an EC2 Instance:
- Navigate to the EC2 service.
- Click “Launch instance” -> “Launch instance”.
- Choose a simple AMI (e.g., “Amazon Linux 2 AMI”, Free tier eligible).
- Select an instance type (e.g., `t2.micro`, Free tier eligible).
- Proceed through the steps, leaving storage defaults (which creates a root EBS volume).
- Launch the instance. Wait for it to be in `running` state.
