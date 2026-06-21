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



### 2. Create a Snapshot of its Root Volume:

When we create ec2 instance, the volume gets created along with it. You can see:

Press enter or click to view image in full size

Our volume gets created along with ec2 creation

- In the EC2 console, navigate to Snapshots (under “Elastic Block Store” in the left menu).
- Select the volume.
- Click Create snapshot.
- Go to Snapshots and wait for your new snapshot to reach completed state.




### 3. Terminate the EC2 Instance (Makes Snapshot Stale):

- Go back to Instances in the EC2 console.
- Select the EC2 instance you just launched.
- Click Instance state -> Terminate instance. Confirm termination.
- Crucial: When you terminate an EC2 instance, its root EBS volume is usually deleted automatically. This action makes the snapshot you just created “stale” because its source volume no longer exists and it’s not attached to any running instance.
- Verify this by checking Volumes (the volume should be gone) and Snapshots (your snapshot should remain, but its Volume ID will refer to a non-existent volume).
Press enter or click to view image in full size


## Deploying & Verifying

```tf
terraform init
terraform plan
terraform apply
Enter a value: yes
```


















Here are the rewritten steps for your Medium article. I have made them look highly professional, clear, and used meaningful naming conventions (like `staging-golden-image-v1`) that real DevOps engineers use in production.

Replace your article's testing section with this:

---

## 🚀 Step 2: Simulate an Orphaned Cloud Resource (AWS Console)

To test our automated cleanup pipeline, we need to create an orphaned snapshot that simulates a real-world scenario where a platform engineer deletes an old golden image but forgets the storage backend.

1. **Locate a Test Resource:** Navigate to the **AWS Management Console > EC2 > Instances** and select any existing running or stopped test instance.
2. **Generate a Custom Image (AMI):** Click **Actions > Images and templates > Create image**.
3. **Apply a Production Naming Convention:** Instead of a generic dummy name, use a structured naming convention like:
* **Image name:** `staging-golden-image-v1.0`
* **Description:** `Base golden image deployment for staging environment.`


4. **Track the Creation:** Click **Create image**. Head over to **EC2 > AMIs** and wait a moment until the status changes from `pending` to `available`.

*Note: Behind the scenes, AWS automatically generated a block storage snapshot linked to this AMI.*

5. **Deregister the Image:** Select your new `staging-golden-image-v1.0` AMI, click **Actions**, and choose **Deregister AMI**.
6. **Verify the Orphaned State:** Now, navigate to **EC2 > Snapshots**. You will see that the AMI is gone, but the snapshot remains completely intact with a description starting with `"Created by CreateImage..."`. This is now our **idle target**.

---

## 🔎 Step 3: Witness the Automation in Action

With our automation engine live, we can monitor the event-driven system as it automatically sweeps the region:

* **Watch the Console:** Stay on your **EC2 > Snapshots** dashboard. Because our EventBridge rule is configured to execute at a tight `rate(5 minutes)`, your Lambda function will automatically wake up within a 5-minute window, identify the detached snapshot, and purge it from your account. Refresh the page after a few minutes, and the snapshot will completely vanish.
* **Inspect Execution Logs:** To view exactly how our infrastructure behaves under the hood, navigate to **Amazon CloudWatch > Log Groups > /aws/lambda/DeleteUnusedSnapshots**. Click on the latest log stream to see the clean execution report confirming success:

```text
--- Unused EBS Snapshot Cleanup Process Started ---
Found 0 snapshots linked to active AMIs. These are safe.
Found orphaned AMI snapshot: snap-0abc123def456789. Deleting...
Cleanup completed. Total unused snapshots removed: 1

```

---

## 🧹 Step 4: Tear Down the Lab Infrastructure

To practice responsible cloud cost management and prevent any accidental API execution cycles in your testing environment, tear down the scheduler engine using a singular declarative command:

```bash
terraform destroy --auto-approve

```

> ⚠️ **Important Reminder:** The `terraform destroy` pipeline cleanly unprovisions your custom IAM execution roles, the serverless Lambda instances, and the EventBridge rules. However, make sure to manually terminate the test EC2 instance you used in Step 2 if you no longer need it, as it was managed outside of Terraform's state matrix.

---

### 💡 Why this looks amazing in your article:

Using a name like `staging-golden-image-v1.0` instantly shows the reader that you are simulating a **real corporate workflow** (baking images for scaling or disaster recovery) instead of just clicking around randomly. It elevates the entire authority of your post!




















I actually **would not use EBS volume snapshots** for this article.

Your current Lambda code is specifically looking for **snapshots that were created by AMIs (Golden Images)**:

```python
amis = ec2.describe_images(Owners=['self'])
```

and

```python
if "Created by CreateImage" in description:
```

So your article should tell a realistic story about **Golden Images**, not volume backups.

---

# This is the scenario I would demonstrate.

This is something companies actually do.

> A DevOps engineer creates a Golden AMI for deployment.
>
> Later, a newer version of the application is released.
>
> The old AMI is deregistered (deleted).
>
> However, the EBS snapshot that AWS created for that AMI still remains.
>
> Nobody notices it.
>
> Hundreds of these accumulate over months.
>
> AWS continues charging for them.

This is MUCH more realistic.

---

# I would build the lab like this.

## Step 1

Launch EC2.

Name

```
staging-app-server-v1
```

Excellent name.

Exactly what companies use.

---

## Step 2

Create Golden Image

EC2

↓

Actions

↓

Image and templates

↓

Create Image

Name

```
staging-golden-image-v1.0
```

Description

```
Golden image for staging application deployment
```

Perfect.

---

AWS now creates

```
AMI

+

Snapshot
```

---

## Step 3

Wait

Image state

Available

---

## Step 4

Go to

AMI

You will see

```
staging-golden-image-v1.0
```

---

## Step 5

Go to

Snapshots

You will see

```
snap-xxxxxxxx
```

Description

```
Created by CreateImage(i-xxxxxxxx)
```

Exactly what your Lambda checks.

---

## Step 6

Now deregister the AMI.

NOT DELETE SNAPSHOT.

Very important.

Choose

```
Deregister AMI
```

When AWS asks

Delete associated snapshots?

Choose

```
NO
```

This creates your orphan snapshot.

Now

AMI

❌ gone

Snapshot

✅ still exists

This is exactly the business problem.

---

# Now your article becomes interesting.

You can say

> The development team created a Golden Image for version 1.0 of their staging application.

Later,

Version 2.0 was released.

The old AMI was deregistered.

However, its backing snapshot remained in the AWS account.

As more releases were deployed, unused snapshots accumulated, increasing monthly storage costs.

Our Lambda automatically detects these orphan snapshots and deletes them.

Now this sounds like a real company.

---

# Then deploy Terraform.

Run

```
terraform init

terraform plan

terraform apply
```

Terraform creates

✅ IAM

✅ Lambda

✅ EventBridge

---

# Wait five minutes.

EventBridge

↓

Lambda

↓

Finds orphan snapshot

↓

Deletes it

---

# Verify

CloudWatch

```
Found orphaned snapshot

Deleting snapshot...

Cleanup complete.
```

---

# Refresh Snapshot page

Empty.

Success.

---

# Then

```
terraform destroy
```

---

# Architecture

```
Developer

↓

Launch EC2

↓

Create Golden Image

↓

AWS creates Snapshot

↓

Deregister AMI

↓

Snapshot becomes orphan

↓

Terraform

↓

EventBridge

↓

Lambda

↓

Delete orphan snapshot

↓

CloudWatch Logs
```

This architecture tells a story.

---

# I would even rename your project.

Instead of

Delete Unused Snapshots

I'd say

# Delete Orphaned EBS Snapshots Automatically Using Terraform, EventBridge Scheduler, and AWS Lambda

Because "orphaned snapshot" is an AWS term engineers recognize, and it accurately describes the scenario your Lambda handles.

---

## One improvement to your Lambda

Your current Lambda only checks whether a snapshot belongs to an existing AMI. That's a good lab, but in production I'd also avoid deleting snapshots just because they're not tied to an AMI. For example, teams may create manual snapshots for backups that aren't associated with any AMI.

A safer approach is to **scope the cleanup**. For a portfolio project, you could add a tag such as:

```
AutoCleanup=True
```

and make your Lambda delete only snapshots that:

* were created by `CreateImage`,
* are no longer referenced by an AMI,
* **and** have `AutoCleanup=True`.

That small addition demonstrates that you're thinking about production safety, not just making the code work. Recruiters and experienced DevOps engineers tend to appreciate that kind of design decision because it reduces the risk of accidental data loss.
