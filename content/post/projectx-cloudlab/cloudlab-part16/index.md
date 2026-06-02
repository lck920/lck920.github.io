---
title: "Part 16: Tear Down and Cleanup"
date: 2026-06-02
description: "Walking through the final steps of tearing down the entire Cloudlab environment to ensure no lingering AWS charges."

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

# Conclusion — Tearing Down the Cloudlab

## Overview

After building and attacking the entire `projectx` cloud infrastructure, it was crucial to properly tear everything down. Leaving resources running in AWS—especially EC2 instances, NAT Gateways, and RDS databases—will quickly incur significant billing charges. 

In this final section, I walked through the systematic teardown of the entire Cloudlab environment.

---

## Step 1 — Terminate EC2 Instances

I navigated to the **EC2 Dashboard**, selected **Instances**, and terminated both instances:
- `projectx-prod-jumpbox`
- `projectx-prod-websvr`

> **Note:** Terminating the instances automatically deleted their attached default EBS volumes, but I also navigated to **Elastic Block Store → Volumes** to ensure no orphaned volumes were left behind.

---

## Step 2 — Delete the RDS Database

I went to the **RDS Dashboard**, selected **Databases**, and deleted the `projectx-prod-rds` database instance.
I unchecked the option to create a final snapshot and acknowledged the deletion.

---

## Step 3 — Remove the NAT Gateway and Elastic IPs

NAT Gateways incur a continuous hourly charge as long as they exist.

1. I navigated to **VPC → NAT Gateways**, selected `projectx-prod-nat-gw`, and deleted it. I waited a few minutes for the state to change to **Deleted**.
2. I went to **VPC → Elastic IPs**, selected the allocated IP address, and released it. 

---

## Step 4 — Delete the VPC

With the instances and NAT Gateway removed, I could delete the VPC itself, which automatically cleans up the subnets, route tables, and internet gateway.

I navigated to **VPC → Your VPCs**, selected `projectx-prod-vpc`, and clicked **Delete VPC**. 

---

## Step 5 — Empty and Delete S3 Buckets

S3 buckets must be empty before they can be deleted.

1. I navigated to **S3**, selected the logging datalake bucket (`projectx-prod-datalake-dllm` or similar).
2. I clicked **Empty** and typed the confirmation to delete all log objects.
3. Once empty, I selected the bucket and clicked **Delete**.

---

## Step 6 — Delete CloudTrail and CloudWatch Logs

To stop further logging charges:
1. I navigated to **CloudTrail**, selected the `projectx-prod-management-trail`, and deleted it.
2. I navigated to **CloudWatch → Log groups** and deleted the log group created for VPC flow logs.

---

## Step 7 — Clean Up IAM

Finally, I cleaned up the IAM resources to return the account to a clean slate:
1. **IAM Users:** I deleted `projectx-prod-admin` and `projectx-prod-janed`.
2. **IAM Groups:** I deleted the `Administrators`, `projectx-employees-group`, and `projectx-jumpbox-group` groups.
3. **IAM Policies:** I deleted the custom `projectx-ec2-read-only` policy.

---

## Summary

The entire ProjectX environment was successfully dismantled, and all billing metrics dropped back to zero.

This wraps up the **Cloud & Attacks 101** series! Thank you for following along through the process of building, securing, and exploiting a realistic AWS cloud environment.
