# Delete Unused AWS EBS Snapshots Automatically Using Terraform AWS EventBridge Scheduler, and AWS Lambda


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
