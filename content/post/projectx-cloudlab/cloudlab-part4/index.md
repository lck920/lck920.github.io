---
title: "Part 4: Deploying the Jumpbox"
date: 2026-05-27
description: "Deploying the projectx-prod-jumpbox bastion host EC2 instance into the public subnet, hardening it with fail2ban, and setting up SSH agent forwarding to reach private resources."

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


# Compute — Deploying the Jumpbox

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with all three subnets configured
2. `projectx-prod-public-subnet` (`10.0.0.0/24`) is available
3. SSH key pair `my-desktop-key-pair` has been created and stored locally
4. AWS CLI is configured with appropriate credentials

---

## Overview

### What is a Bastion Host / Jumpbox?

A **bastion host** (also called a jumpbox) is a special-purpose server that acts as a secure gateway to access resources in private subnets. It's the only server directly accessible from the internet and serves as the single controlled entry point into my private infrastructure.

Rather than exposing every EC2 instance to the internet, I exposed just one hardened machine — the jumpbox. Anyone who needs to reach a private resource (the web server, the database) must SSH into the jumpbox first, then hop from there. This approach:

- **Reduces the attack surface** — only one instance faces the public internet instead of every resource
- **Centralises access logging** — all authentication attempts go through a single point, making auditing and anomaly detection easier
- **Simplifies security configuration** — security group rules for private resources only need to trust the jumpbox, not the entire internet

> **Best practice:** Restrict jumpbox SSH access to your own IP address where possible. If you're working from multiple locations, at minimum use key-based authentication rather than passwords — never allow password-based SSH on a public-facing server.

---

## Step 1 — Launch the EC2 Instance

I navigated to the **EC2** service in the AWS Console and selected **Launch instance**.

### Instance Details

I configured the following:

- **Name:** `projectx-prod-jumpbox`
- **AMI:** Ubuntu Server 24.04 LTS
- **Instance type:** `t3.micro`
- **Key pair:** Select `my-desktop-key-pair`

![EC2 Launch Instance page showing `projectx-prod-jumpbox` as the name, Ubuntu Server 24.04 LTS selected as the AMI, `t3.micro` as the instance type, and `my-desktop-key-pair` selected in the key pair dropdown.](screenshot1.png)

---

### Network Settings

I selected **Edit** to configure network settings.

- **VPC:** Select `projectx-prod-vpc`
- **Subnet:** Select `projectx-prod-public-subnet`
- **Auto-assign Public IP:** Enable

**Create a new security group:**

- **Security group name:** `projectx-prod-jumpbox-sg`
- **Description:** Security group for ProjectX production jumpbox

**Inbound rule:**

- **Type:** SSH
- **Port:** 22
- **Source:** `0.0.0.0/0` (or restrict to your IP for better security)
- **Description:** SSH access for jumpbox

![EC2 Network Settings panel showing `projectx-prod-vpc` selected, `projectx-prod-public-subnet` chosen, Auto-assign Public IP enabled, and the new `projectx-prod-jumpbox-sg` security group configured with an SSH inbound rule.](screenshot2.png)

---

### Storage

I left storage settings as default — 8 GiB gp3 was sufficient for the jumpbox.

---

### Advanced Details — User Data (fail2ban)

I expanded **Advanced details** and pasted the following script into the **User data** field. This installed and configured **fail2ban** automatically on first boot — a daemon that monitors SSH login attempts and bans IPs that exceed the retry threshold.

```bash
#!/bin/bash
apt-get update
apt-get install -y fail2ban

# Configure fail2ban
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

# Start and enable fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

What this configured:
- Any IP that fails SSH login **3 times** within 10 minutes gets banned for **2 hours**
- The global default bans for 1 hour after 5 failures within 10 minutes
- fail2ban starts automatically on every reboot

---

## Step 2 — Launch and Confirm

I reviewed the configuration summary and selected **Launch instance**.

| Setting | Value |
|---|---|
| Name | `projectx-prod-jumpbox` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | `t3.micro` |
| Key pair | `my-desktop-key-pair` |
| VPC | `projectx-prod-vpc` |
| Subnet | `projectx-prod-public-subnet` |
| Public IP | Enabled |
| Security group | `projectx-prod-jumpbox-sg` |
| User data | fail2ban install script |

I waited for the instance state to show **Running** and noted the **public IPv4 address**.

![EC2 Instances list showing `projectx-prod-jumpbox` with state **Running**, a public IPv4 address assigned, and the `projectx-prod-public-subnet` subnet visible — confirming the instance is live in the public subnet.](screenshot3.png)

---

## Step 3 — Connect and Verify fail2ban

I SSH'd into the jumpbox using its public IP:

**macOS / Linux:**
```bash
ssh -i ~/.ssh/my-desktop-key-pair.pem ubuntu@<public-ip-address>
```

**Windows PowerShell:**
```powershell
ssh -i $env:USERPROFILE\.ssh\my-desktop-key-pair.pem ubuntu@<public-ip-address>
```

I replaced `<public-ip-address>` with my instance's actual public IP.

![Terminal showing the SSH command connecting to the jumpbox — the Ubuntu welcome banner and `ubuntu@projectx-prod-jumpbox` shell prompt confirming a successful login.](screenshot4.png)

Once connected, I verified fail2ban installed correctly and the SSH jail was active:

```bash
sudo systemctl status fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

![Terminal showing `sudo systemctl status fail2ban` returning **active (running)**, followed by `sudo fail2ban-client status sshd` showing the SSH jail as active with 0 currently banned IPs — confirming fail2ban is working.](screenshot5.png)

---

## Step 4 — Change the Hostname

I set the hostname to match the instance name so it was clearly identifiable in terminal sessions:

```bash
sudo hostnamectl set-hostname projectx-prod-jumpbox
sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost projectx-prod-jumpbox/' /etc/hosts
hostnamectl
```

I verified the hostname had been updated.

![Terminal showing `hostnamectl` output with `Static hostname: projectx-prod-jumpbox` — confirming the hostname change was applied successfully.](screenshot6.png)

---

## Step 5 — Set Up SSH Agent Forwarding

The web server I was deploying next lived in the **private subnet** — no public IP, no direct access. To reach it, I had to SSH into the jumpbox first, then hop from the jumpbox to the private instance. The cleanest way I found to do this without copying private keys onto the jumpbox was **SSH agent forwarding**.

SSH agent forwarding let me use my local private key to authenticate to a second hop (the web server) without ever storing the key file on the intermediate machine (the jumpbox).

### Enable the SSH Agent Locally

**macOS / Linux:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/my-desktop-key-pair.pem
```

**Windows PowerShell:**
```powershell
Start-Service ssh-agent
Get-Service ssh-agent   # confirm it's running
ssh-add C:\Users\<username>\.ssh\my-desktop-key-pair.pem
```

### Connect to the Jumpbox with Forwarding Enabled

```bash
ssh -A -i ~/.ssh/my-desktop-key-pair.pem ubuntu@<jumpbox-public-ip>
```

The `-A` flag enabled agent forwarding. From inside the jumpbox I could now SSH directly to any private instance without specifying a key:

```bash
ssh ubuntu@<private-instance-ip>
```

### Alternative: SCP Method

Alternatively, if I preferred not to use agent forwarding, I could copy the key to the jumpbox manually:

```bash
# From your local machine
scp -i my-desktop-key-pair.pem my-desktop-key-pair.pem ubuntu@<jumpbox-public-ip>:~/

# SSH into jumpbox
ssh -i my-desktop-key-pair.pem ubuntu@<jumpbox-public-ip>

# From jumpbox, SSH to private instance
ssh -i ~/my-desktop-key-pair.pem ubuntu@<private-instance-ip>
```

> Storing private keys on a remote server is less secure than agent forwarding. Use the SCP method only if agent forwarding isn't available in your environment.

---

## Summary

The jumpbox was now:

- Deployed in the **public subnet** with a public IP and SSH accessible from the internet
- Protected by **fail2ban** which bans IPs after 3 failed SSH attempts
- Configured as a **secure gateway** — all access to private resources in the VPC flows through here
- Set up for **SSH agent forwarding** so the private key never needs to leave your local machine

The jumpbox was the only public-facing EC2 instance in the entire ProjectX production environment. Everything else — the web server, the database — sat behind it in private subnets.

---

*Next up — Part 5: Deploying and Configuring the Web Server.*
