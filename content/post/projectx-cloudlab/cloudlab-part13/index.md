---
title: "Part 13 - Attack 4: Hardcoded Secrets in AWS"
date: 2026-05-30
description: "Discovering hardcoded AWS credentials, database passwords, and API keys embedded in a public S3 configuration file and exposed web application endpoints, using Gobuster for directory enumeration."

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


# Attack 4 — Hardcoded Secrets in AWS

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with subnets configured
2. `My-Desktop-Key-Pair` key pair exists
3. AWS CLI configured with appropriate IAM credentials

## Scenario

The attacker discovers a web application running on a public EC2 instance. Using Gobuster for directory enumeration, they discover that the application exposes `/env` and `/config/env` endpoints that serve plaintext `.env` files containing database credentials, AWS access keys, and third-party API keys. Separately, the same application references a public S3 bucket containing a configuration file with additional secrets. The EC2 instance also has IMDSv1 enabled, allowing further metadata extraction.

This exercise is structured like a CTF — each discovery leads to the next.

---

## Overview

### What are Hardcoded Secrets?

A **hardcoded secret** is any sensitive credential — password, API key, token, or private key — embedded directly into source code, configuration files, environment variable files, or infrastructure templates rather than being retrieved securely at runtime from a secrets manager.

The problem with hardcoding is persistence. A credential baked into a `.env` file or a CloudFormation template gets committed to version control, backed up, copied to S3, and potentially exposed through dozens of unintended paths long after the original developer has forgotten it exists.

### Common Places Where Secrets Get Hardcoded

- **Configuration files** — `.env`, `config.yaml`, `appsettings.json` committed to version control or stored in public S3
- **Source code** — credentials embedded directly in application logic, often for "quick testing" that never gets cleaned up
- **EC2 user data** — startup scripts with database passwords or AWS credentials passed at launch time, accessible via the metadata service
- **CloudFormation/Terraform templates** — secrets in infrastructure-as-code that get checked into source control
- **Public repositories** — the most common vector; GitHub scanners like GitGuardian detect thousands of leaked secrets daily

> AWS Secrets Manager and SSM Parameter Store exist precisely to solve this problem. Secrets should never live in files — they should be fetched at runtime through an API call, with access controlled by IAM.

---

## Deploy the Vulnerable Environment

### Step 1 — Deploy via CloudFormation

I navigated to **CloudFormation → Create stack → Choose an existing template**.

Upload `hardcoded-secrets.yaml` from the exercise files repository (https://github.com/projectsecio/exercise-files/tree/main/cloud-attacks-101/attacks_cf_templates):

[Download Template](hardcoded-secrets.yaml)
[Download Shell](setup-vulnerable-app.sh)

Configure parameters:
- **Stack name:** `hardcoded-secrets`
- **KeyPairName:** `My-Desktop-Key-Pair`
- **VpcId:** `projectx-prod-vpc`
- **SubnetId:** Select the public subnet

I selected **Submit** and wait for **CREATE_COMPLETE**.

> 📝 The CloudFormation template creates: a public S3 bucket with a configuration file (simulating a public code repository), and an EC2 instance with IMDSv1 enabled. You'll manually start the web application in the next step.

---

### Step 2 — SSH into the EC2 Instance and Start the Application

Get the instance's public IP:

```bash
PUBLIC_IP=$(aws cloudformation describe-stacks \
  --stack-name hardcoded-secrets \
  --query 'Stacks[0].Outputs[?OutputKey==`EC2PublicIP`].OutputValue' \
  --output text)

echo "EC2 Public IP: $PUBLIC_IP"
```

SSH into the instance and create the projectx-app directory:

```bash
ssh -i ~/.ssh/My-Desktop-Key-Pair.pem ec2-user@$PUBLIC_IP

sudo mkdir -p /opt/projectx-app
```

Copy and run the setup script from the exercise files:

```bash
# Option 1: Copy setup script from your local machine into home directory first
# First, exit SSH (or open new terminal), then from your local machine:
scp -i ~/.ssh/My-Desktop-Key-Pair.pem setup-vulnerable-app.sh ec2-user@$PUBLIC_IP:~

# Then SSH back in and run:
ssh -i ~/.ssh/My-Desktop-Key-Pair.pem ec2-user@$PUBLIC_IP
sudo mv ~/setup-vulnerable-app.sh /opt/projectx-app/
sudo bash /opt/projectx-app/setup-vulnerable-app.sh

# Troubleshoot: if the script cannot detect S3 Bucket Name
# Bypasses the broken 'aws s3 ls' auto-discovery due to IAM restrictions
sudo S3_BUCKET_NAME="$BUCKET_NAME" bash /opt/projectx-app/setup-vulnerable-app.sh

# Option 2: I created the script directly on the instance
# SSH into the instance and create the file manually or download it from your repository
```

The setup script installs Flask, creates `.env` files with hardcoded secrets, downloads the S3 configuration file, and starts the web application as a systemd service.

I verified the application is running:

```bash
curl http://localhost:8080/health
sudo systemctl status projectx.service
```

![Terminal showing `sudo systemctl status projectx.service` returning `active (running)` — and `curl http://localhost:8080/health` returning a 200 OK response confirming the vulnerable app is live.](screenshot1.png)

The application is accessible at `http://<EC2_PUBLIC_IP>:8080`.

---

## Discovery Phase

### Step 3 — Explore the Web Application

Construct the app URL and check the main page:

```bash
APP_URL="http://$PUBLIC_IP:8080"
curl $APP_URL
```

The main page shows a basic welcome message with no list of available endpoints — by design. You need to discover them.

### Step 4 — Directory Enumeration with Gobuster

Install Gobuster:

```bash
# I downloaded the binary
wget https://github.com/OJ/gobuster/releases/download/v3.6.0/gobuster_Linux_x86_64.tar.gz
tar -xzf gobuster_Linux_x86_64.tar.gz
sudo mv gobuster /usr/local/bin/

# Or via package manager on Kali
sudo apt install gobuster -y
```

Run directory enumeration against the application:

```bash
# Basic directory scan
gobuster dir -u $APP_URL -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt

# With .env extension filter
gobuster dir -u $APP_URL \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
  -x env,json,txt
```

![Terminal showing Gobuster running and returning discovered endpoints — specifically `/env` and `/config/env` appearing in the results with HTTP 200 status codes.](screenshot2.png)

**Key discovery:** The `/env` and `/config/env` endpoints serve `.env` configuration files directly over HTTP. These were accidentally exposed by the developer — the web framework is serving them as public routes without any authentication.

---

### Step 5 — Access the Exposed .env Files

```bash
# Fetch the main .env file
curl $APP_URL/env

# Fetch the config .env file
curl $APP_URL/config/env
```

![Terminal showing `curl $APP_URL/env` returning a plaintext response with `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `API_KEY` values hardcoded — the full contents of the `.env` file served without authentication.](screenshot3.png)

---

### Step 6 — Discover and Access the Public S3 Bucket

Based on hints from the application responses, locate the S3 bucket. There are three ways to find it:

**Method 1 — From the EC2 instance environment:**

```bash
# SSH into the instance if not already connected
ssh -i ~/.ssh/My-Desktop-Key-Pair.pem ec2-user@$PUBLIC_IP

# Check environment variables
export BUCKET_NAME=$(grep S3_BUCKET_NAME /opt/projectx-app/.env | cut -d'=' -f2)
echo $BUCKET_NAME

# Or search for bucket references in the config
cat /tmp/app-secrets.json | grep -i bucket
```

**Method 2 — From CloudFormation outputs:**

```bash
aws cloudformation describe-stacks \
  --stack-name hardcoded-secrets \
  --query 'Stacks[0].Outputs[?OutputKey==`SecretsBucketName`].OutputValue' \
  --output text
```

**Method 3 — From the public config file URL:**

```bash
CONFIG_URL=$(aws cloudformation describe-stacks \
  --stack-name hardcoded-secrets \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigFileURL`].OutputValue' \
  --output text)

curl $CONFIG_URL
```

### Step 7 — Enumerate and I downloaded the S3 Configuration File

List the bucket contents (public access — no credentials required):

```bash
aws s3 ls s3://$BUCKET_NAME --recursive --no-sign-request
```

I downloaded the configuration file:

```bash
aws s3 cp s3://$BUCKET_NAME/config/app-config.json . --no-sign-request
cat app-config.json
```

![Terminal showing `aws s3 ls` listing the bucket contents without credentials, followed by `cat app-config.json` displaying the configuration file with database host, username, password, AWS credentials, and API keys hardcoded in plaintext.](screenshot4.png)

The configuration file contains:
- Database connection credentials (host, user, password, database name)
- AWS access key ID and secret access key
- Third-party API keys (payment processors, external services)

---

### Step 8 — Check EC2 Instance Metadata for Additional Secrets

The EC2 instance has IMDSv1 enabled. From within the instance (via SSH), check the user data for secrets:

```bash
# Access user data (from within the EC2 instance)
curl http://169.254.169.254/latest/user-data
```

In this scenario, the user data is clean — but checking is always worth it since startup scripts commonly contain database passwords or bootstrap credentials passed at launch.

```bash
# Also check the .env files directly on the filesystem
cat /opt/projectx-app/.env
cat /opt/projectx-app/config/.env
cat /tmp/app-secrets.json
```

![Terminal inside the EC2 instance showing `cat /opt/projectx-app/.env` — displaying the hardcoded secrets file on disk. This demonstrates the same secrets are stored both in the file system and being served over HTTP.](screenshot5.png)

---

## Exploitation Phase

With the collected credentials, an attacker could:

- **AWS account access** — the hardcoded AWS access key allows direct CLI or SDK access to any service the key has permissions for. If it's a long-lived IAM user key, it doesn't expire
- **Database access** — connect directly to the production database using the hardcoded host, user, and password — if the database port is not firewalled
- **Third-party service abuse** — use the API keys to make calls on behalf of the application (charging payments, accessing messaging services, reading external data)
- **Lateral movement** — use the AWS credentials to enumerate other resources, assume roles, or pivot to other accounts
- **Persistence** — create new IAM access keys before the original keys are rotated

> 📝 The hardcoded secrets in this exercise are **not real** — they are example values for the lab only. Don't attempt to use them outside this exercise.

---

## Detection and Prevention

**How to detect this:**
- **AWS GuardDuty** — `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` fires when instance credentials are used from outside AWS
- **CloudTrail** — monitor for `GetObject` calls on S3 buckets from unauthenticated principals (`userIdentity.type: Anonymous`)
- **GitHub Advanced Security / GitGuardian** — scans repositories for secrets before they're committed or as part of CI/CD pipelines
- **Trufflehog / Gitleaks** — open-source tools for scanning Git history and S3 buckets for credential patterns

**How to prevent it:**
- **Never hardcode secrets** — use AWS Secrets Manager for database credentials and API keys; use IAM roles for EC2 instances instead of hardcoded AWS credentials
- **Use `.gitignore`** — exclude `.env` files, `config.json`, and other credential files from version control
- **Use IAM roles, not access keys** — EC2 instances should use instance profiles (IAM roles) that provide temporary credentials via the metadata service, not hardcoded long-lived keys
- **Rotate secrets regularly** — even if secrets are discovered, rotation limits the exposure window
- **Block public S3 access** — configuration files should never be stored in public buckets; use Secrets Manager or Parameter Store instead
- **Enable IMDSv2** — prevents SSRF-based metadata access that could be combined with this attack vector

---

## Cleanup

```bash
# Stop the Flask application on EC2
ssh -i ~/.ssh/My-Desktop-Key-Pair.pem ec2-user@$PUBLIC_IP \
  "sudo systemctl stop projectx.service || true"

# Empty the S3 bucket
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name hardcoded-secrets \
  --query 'Stacks[0].Outputs[?OutputKey==`SecretsBucketName`].OutputValue' \
  --output text)

aws s3 rm s3://$BUCKET_NAME --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name hardcoded-secrets
aws cloudformation wait stack-delete-complete --stack-name hardcoded-secrets
```

---

*Next up — Part 14 - Attack 5: Insecure IAM Permissions.*
