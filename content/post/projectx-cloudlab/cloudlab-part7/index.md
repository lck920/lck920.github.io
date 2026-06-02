---
title: "Part 7: Wazuh Index State Management (ISM) Policy"
date: 2026-05-28
description: "Installing and configuring the AWS CLI on project-x-sec-box, and setting up an Index State Management policy in Wazuh to automatically delete indices older than 14 days."

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


# Monitoring & Logging — Wazuh Index State Management (ISM) Policy

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with subnets configured
2. `projectx-prod-jumpbox` EC2 instance exists and is accessible
3. AWS CLI configured with `projectx-prod-admin` credentials on your local machine
4. `project-x-sec-box` is configured and running Wazuh 4.9.2
5. The S3 security datalake bucket has been created and is receiving logs from CloudTrail and VPC Flow Logs

> 📝 This guide is written for **Wazuh version 4.9.2**. UI elements and navigation paths may differ in other versions.

---

## Overview

### What is Index State Management (ISM)?

As logs flow into Wazuh from CloudTrail, VPC Flow Logs, and other sources, Wazuh stores them in **OpenSearch indices** — time-based data structures that back the Wazuh dashboard and alert engine. Over time, these indices grow and consume disk space on `project-x-sec-box`.

**Index State Management (ISM)** is an OpenSearch feature built into Wazuh that lets you automate routine index lifecycle tasks. You define a **policy** made up of **states** and **transitions** — conditions that move an index from one state to another based on criteria like age or size — and ISM applies it automatically to matching indices.

For this homelab, the use case is simple but essential: automatically delete Wazuh alert indices that are older than 14 days to prevent the `project-x-sec-box` VM's disk from filling up as AWS logs accumulate. Without this, a busy lab environment will eventually run out of storage.

This guide covers two things in one: creating the Wazuh IAM service account (which feeds into the CloudTrail and VPC Flow Logs integrations coming next), and creating the ISM policy that keeps index storage under control.

---

## Part 1 — Install and Configure AWS CLI on project-x-sec-box

Wazuh's S3 integration uses the AWS CLI credentials stored on `project-x-sec-box` to authenticate against the S3 bucket. I needed to install the CLI on the security server and configure it with the `projectx-wazuh-s3-user` access keys.

### Step 1 — Connect to project-x-sec-box

SSH into `project-x-sec-box` from your local machine (or via the jumpbox if it's on a private subnet):

```bash
ssh ubuntu@<sec-box-ip>
```

---

### Step 2 — Install the AWS CLI

Update the package list and install the AWS CLI:

```bash
sudo apt update
sudo apt install awscli -y
```

I verified the installation:

```bash
aws --version
```

I received output like `aws-cli/2.x.x Python/3.x.x Linux/...`.

![Terminal on `project-x-sec-box` showing `aws --version` returning the installed CLI version — confirming the installation succeeded.](screenshot1.png)

---

### Step 3 — Configure AWS Credentials as Root

Wazuh's `<wodle>` S3 integration runs as the `root` user internally, so credentials must be configured under root. Switch to root first:

```bash
sudo su
```

I ran the configure command:

```bash
aws configure
```

I entered the following when prompted:

```
AWS Access Key ID [None]: <access-key-id-for-projectx-wazuh-s3-user>
AWS Secret Access Key [None]: <secret-access-key-for-projectx-wazuh-s3-user>
Default region name [None]: ap-southeast-1
Default output format [None]: json
```

I used the same region where your S3 datalake bucket is located.

![Terminal showing the `aws configure` prompts completed as root — Access Key ID entered, region set to `ap-southeast-1`, and output format set to `json`.](screenshot2.png)

---

### Step 4 — I verified the Credential Files

I confirmed the credentials were saved correctly:

```bash
cat ~/.aws/credentials
```

Expected output:

```
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

I checked the config file:

```bash
cat ~/.aws/config
```

Expected output:

```
[default]
region = ap-southeast-1
output = json
```

![Terminal showing `cat ~/.aws/credentials` and `cat ~/.aws/config` output — both files present under root's home directory with the correct access key and region configured.](screenshot3.png)

> The credentials are stored at `~/.aws/credentials` for whichever user runs `aws configure`. Because Wazuh's wodle integration runs as root, configuring as root (via `sudo su`) ensures Wazuh can read them without permission issues.

---

## Part 2 — I created the ISM Policy in Wazuh

With the service account and CLI configured, we now set up the ISM policy in the Wazuh dashboard to automatically manage index retention.

### Step 1 — Log Into the Wazuh Dashboard

Open a browser and navigate to your Wazuh dashboard URL (typically `https://<sec-box-ip>`).

Log in with your Wazuh admin credentials.

> If you've forgotten your Wazuh credentials, retrieve them from the security server:
> ```bash
> sudo cat /etc/wazuh-indexer/wazuh-passwords.txt
> ```

---

### Step 2 — Navigate to Index Management

Click the **hamburger menu (☰)** in the top-left corner of the Wazuh dashboard.

I navigated to **Indexer Management → Index Management**.

I selected **State management policies** from the left sidebar, then click **Create policy**.

![Wazuh Dashboard showing the Indexer Management → Index Management navigation path — the State management policies section open and the Create policy button visible.](screenshot4.png)

---

### Step 3 — Configure Policy Details

Fill in the basic information:

- **Policy ID:** `14day-policy`
- **Description:** `Automatically delete log indices after 14 days.`

> 📝 Policy IDs cannot contain spaces or special characters.

I selected **Create**.

![Wazuh ISM policy creation page showing `14day-policy` entered as the Policy ID and the description filled in.](screenshot5.png)

---

### Step 4 — Add the ISM Template

Under **ISM Templates**, select **Add Template**.

Set the **Index pattern** to:

```
wazuh-alerts-*
```

This tells ISM to automatically apply this policy to all newly created indices whose names match `wazuh-alerts-*` — which is the default index pattern for all Wazuh alert data, including the AWS logs we'll be ingesting from CloudTrail and VPC Flow Logs.

![Wazuh ISM template configuration showing `wazuh-alerts-*` entered as the index pattern — confirming all Wazuh alert indices will be managed by this policy.](screenshot6.png)

---

### Step 5 — I created the default State

In the **States** section, select **Add state**.

I configured:

- **State name:** `default`
- **Actions:** Leave empty — this state does nothing, it just waits
- **Transitions:** I added a transition with condition **Minimum index age is `14d`**

This is the starting state for every new index. The index sits here doing nothing until it reaches 14 days old, at which point ISM triggers the transition to the next state.

I selected **Save**.

![Wazuh ISM state editor showing the `default` state with no actions and a transition condition set to `Minimum index age is 14d`.](screenshot7.png)

---

### Step 6 — I created the delete State

I selected **Add state** again.

I configured:

- **State name:** `delete`
- **Order:** I added after `default`
- **Actions:** I selected **Delete**
- **Transitions:** Leave empty — once in the delete state, there's nowhere else to go

I selected **Save**.

![Wazuh ISM state editor showing the `delete` state with the Delete action configured and no transitions — this is the terminal state.](screenshot8.png)

---

### Step 7 — Link the Transition

Navigate back to the `default` state and edit its **Transition** to point to the `delete` state.

You should now have two states connected: `default` → (after 14 days) → `delete`.

![Wazuh ISM policy view showing both states — `default` and `delete` — with the transition arrow connecting them and the 14-day age condition visible.](screenshot9.png)

I selected **Create** to save the ISM policy.

---

### Step 8 — I verified the Policy

Navigate back to **State management policies**. The `14day-policy` should appear in the list, showing the `wazuh-alerts-*` index pattern.

![Wazuh State management policies page showing `14day-policy` listed with the `wazuh-alerts-*` index pattern and the policy status active — confirming it was created successfully.](screenshot10.png)

---

### Reference: Full ISM Policy JSON

If you'd prefer to create the policy via the **JSON editor** (or want to verify your configuration matches), here is the complete policy JSON:

```json
{
    "policy": {
        "policy_id": "14day-policy",
        "description": "Automatically delete log indices after 14 days.",
        "default_state": "default",
        "states": [
            {
                "name": "default",
                "actions": [],
                "transitions": [
                    {
                        "state_name": "delete",
                        "conditions": {
                            "min_index_age": "14d"
                        }
                    }
                ]
            },
            {
                "name": "delete",
                "actions": [
                    {
                        "retry": {
                            "count": 3,
                            "backoff": "exponential",
                            "delay": "1m"
                        },
                        "delete": {}
                    }
                ],
                "transitions": []
            }
        ],
        "ism_template": [
            {
                "index_patterns": [
                    "wazuh-alerts-*"
                ],
                "priority": 0
            }
        ]
    }
}
```

Notable detail: the `delete` action includes a built-in retry policy — if the deletion fails, ISM will retry up to 3 times with exponential backoff starting at 1 minute. This makes the policy resilient to transient errors.

---

## Summary

Two things are now in place that support the full AWS log ingestion pipeline:

| Component | Details |
|---|---|
| AWS CLI on `project-x-sec-box` | Configured as root with `projectx-wazuh-s3-user` credentials, region `ap-southeast-1` |
| `14day-policy` ISM | Automatically deletes `wazuh-alerts-*` indices older than 14 days to control disk usage |

With the service account configured and index lifecycle managed, Wazuh is ready to start ingesting AWS logs from the S3 datalake. The next steps — CloudTrail and VPC Flow Logs integration — will complete the pipeline.

---

*Next up — Part 8: AWS CloudTrail & Wazuh Integration.*
