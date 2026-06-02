---
title: "Part 2: IAM Admin User, AWS CLI & SSH Key Pair Setup"
date: 2026-05-27
description: "Setting up the foundational access layer for CA101 — creating a dedicated IAM admin user, configuring the AWS CLI with access keys, and generating an SSH key pair for EC2 access on Windows."

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


# Part 2 — IAM Admin User, AWS CLI & SSH Key Pair Setup

With the AWS account created, the next step was setting up the access layer — a dedicated IAM admin user, CLI credentials, and an SSH key pair. These three things underpin every other step in this series, so it's worth getting them right before touching any infrastructure.

---

## Section 1 — Create the IAM Admin User

### Why Not Use the Root Account?

The AWS root account has unrestricted access to everything in your account — billing, IAM, every service. It should be used only for initial setup and then locked away. For day-to-day operations, even in a homelab, I work through a dedicated IAM admin user instead. If those credentials are ever compromised, the blast radius is scoped and the root account remains untouched.

### Step 1 — Create an Account Alias

Before creating the user, I set a human-readable alias for my account's sign-in URL.

I navigated to **IAM → Dashboard → Customize** and set an alias (e.g. `dllm-cloudlab`).

My sign-in URL became:

```
https://dllm-cloudlab.signin.aws.amazon.com/console
```

This is easier to bookmark and share than the default numeric account ID URL.

![IAM Dashboard showing the custom alias applied — the sign-in URL with the alias name visible in the Account Alias section.](screenshot1.png)

---

### Step 2 — Create the Administrators Group

Groups make permission management scalable — assign a policy to the group, and every user in it inherits those permissions. I created a dedicated admin group first, then dropped the admin user into it.

I navigated to **IAM → User groups → Create group**.

I configured:

- **Group name:** `Administrators`
- **Attach policy:** Search for and select `AdministratorAccess`

I selected **Create group**.

![IAM User Groups page showing the `Administrators` group created with `AdministratorAccess` listed as the attached policy.](screenshot2.png)

---

### Step 3 — Create the Admin User

I navigated to **IAM → Users → Create user**.

I configured:

- **Username:** `projectx-prod-admin`
- **Console access:** Enable — set a custom password (tick "require password reset" if others will use this account, uncheck for personal homelab use)

I selected **Next → Add user to group → select `Administrators` → Next → Create user**.

![IAM Users list showing `projectx-prod-admin` created and appearing in the user table — confirming the account exists.](screenshot3.png)

---

### Step 4 — Enforce MFA on the Admin User

MFA is not optional for an admin account. Even in a homelab, it's good practice — and some AWS services will eventually require it.

I navigated to **IAM → Users → `projectx-prod-admin` → Security credentials → Assign MFA device**.

I chose **Virtual MFA device** and scanned the QR code with an authenticator app (Google Authenticator, Authy, or a passkey). I entered two consecutive codes to confirm and clicked **Assign MFA**.

![IAM Security Credentials tab for `projectx-prod-admin` showing an MFA device listed as assigned — with the device ARN visible confirming MFA is active on the account.](screenshot4.png)

---

### Step 5 — Create Access Keys for CLI Use

Access keys are what allow the AWS CLI to authenticate as `projectx-prod-admin` programmatically.

I navigated to **IAM → Users → `projectx-prod-admin` → Security credentials → Create access key**.

Select **Command Line Interface (CLI)** as the use case → tick the confirmation checkbox → **Next → Create access key**.

AWS displayed the keys **once** — I copied them immediately. These are the credentials I used throughout this series:

| | Value |
|---|---|
| **Access Key ID** | `AKIAIOSFODNN7EXAMPLE` |
| **Secret Access Key** | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

> **Treat access keys like passwords.** Never commit them to a Git repository, paste them into a public document, or share them. If they're ever exposed, delete them immediately in IAM and generate new ones.

![AWS IAM Access Key creation success screen showing the Access Key ID visible and the Secret Access Key revealed](screenshot5.png)

---

## Section 2 — Install and Configure the AWS CLI

### What is the AWS CLI?

The **AWS Command Line Interface (CLI)** lets you manage AWS services from a terminal window. Rather than clicking through the console for every action, you can query resources, trigger deployments, and automate tasks with simple commands. Throughout CA101, the CLI is used alongside the console — especially useful for scripting and for verifying what the console has created.

### Step 1 — Install the AWS CLI on Windows

I downloaded the MSI installer from:

**[https://awscli.amazonaws.com/AWSCLIV2.msi](https://awscli.amazonaws.com/AWSCLIV2.msi)**

I double-clicked the downloaded `.msi` file, followed the installation wizard, and accepted the default installation location.

I opened a new **PowerShell** window after installation and verified:

```powershell
aws --version
```

![PowerShell window showing `aws --version` returning the installed AWS CLI version (e.g. `aws-cli/2.x.x Python/3.x.x Windows/...`) — confirming the installation succeeded.](screenshot6.png)

---

### Step 2 — Configure the AWS CLI

I ran the configure command in PowerShell:

```powershell
aws configure
```

I entered the following when prompted:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: ap-southeast-1
Default output format [None]:
```

I left the output format blank — the CLI defaults to JSON which is fine for our purposes.

![PowerShell window showing the `aws configure` prompts being filled in — the Access Key ID visible and the region set to `ap-southeast-1`, with the Secret Access Key field filled .](screenshot7.png)

The credentials were stored locally at:

```
C:\Users\YourUsername\.aws\credentials
C:\Users\YourUsername\.aws\config
```

---

### Step 3 — Verify the Configuration

I confirmed the CLI was authenticated correctly by running:

```powershell
aws sts get-caller-identity
```

I received a JSON response with my account ID, user ID, and the ARN of `projectx-prod-admin`:

```json
{
    "UserId": "AIDAUM2TF5XX...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/projectx-prod-admin"
}
```

![PowerShell window showing the `aws sts get-caller-identity` response — the `Arn` field showing `projectx-prod-admin` confirming the CLI is authenticated as the correct user.](screenshot8.png)

I also did a quick sanity check to list any existing S3 buckets or EC2 instances:

```powershell
aws s3 ls
aws ec2 describe-instances --region ap-southeast-1
```

---

## Section 3 — Create the SSH Key Pair

### What is a Public/Private Key Pair?

SSH key pairs use asymmetric cryptography — two mathematically linked keys that work together:

- **Private key** — stays on your local machine, never shared. Used to prove your identity when connecting.
- **Public key** — stored on the EC2 instance (in `~/.ssh/authorized_keys`). Used to verify that you hold the matching private key.

When I connect via SSH, my client uses the private key to sign a challenge. The server verifies the signature using the public key — no password is ever transmitted. This is significantly more secure than password-based authentication, which is why AWS doesn't support passwords on EC2 instances by default.

By creating the key pair inside AWS EC2, the public key is automatically available to attach to any new instance during launch — no manual copying needed.

---

### Step 1 — Generate the Key Pair in EC2

Navigate to **EC2 → Network & Security → Key Pairs**.

Select **Create key pair**.

I configured:

- **Name:** `My-Desktop-Key-Pair`
- **Key pair type:** RSA
- **Private key file format:** `.pem`

I left everything else as default and selected **Create key pair**.

A `My-Desktop-Key-Pair.pem` file will automatically download to your browser's default download folder (`Downloads` by default).

![EC2 Key Pairs list showing `My-Desktop-Key-Pair` listed — confirming it was created and the `.pem` file was downloaded.](screenshot9.png)

---

### Step 2 — Store the Key in the .ssh Directory

Open **PowerShell** and create the `.ssh` directory if it doesn't already exist:

```powershell
mkdir $env:USERPROFILE\.ssh
```

Move the downloaded `.pem` file into the `.ssh` folder:

```powershell
mv $env:USERPROFILE\Downloads\My-Desktop-Key-Pair.pem $env:USERPROFILE\.ssh
```

![PowerShell window showing the `mv` command completing — and a follow-up `ls $env:USERPROFILE\.ssh` showing `My-Desktop-Key-Pair.pem` present in the `.ssh` directory.](screenshot10.png)

---

### Step 3 — Set Correct File Permissions

On Windows, SSH is strict about key file permissions — if the `.pem` file is accessible to other users on the system, SSH will refuse to use it and throw a `WARNING: UNPROTECTED PRIVATE KEY FILE!` error. We use `icacls` to restrict access to the current user only.

I ran these three commands in PowerShell:

```powershell
icacls "$env:USERPROFILE\.ssh\My-Desktop-Key-Pair.pem" /inheritance:r
icacls "$env:USERPROFILE\.ssh\My-Desktop-Key-Pair.pem" /grant:r "${env:USERNAME}:R"
icacls "$env:USERPROFILE\.ssh\My-Desktop-Key-Pair.pem"
```

What each command does:
- `/inheritance:r` — removes all inherited permissions from the file
- `/grant:r "${env:USERNAME}:R"` — grants the current Windows user read-only (`R`) access
- The third command (no flags) prints the current permissions so you can confirm the result

The output of the final `icacls` command should show **only your username** with `(R)` — no other users or groups listed.

![PowerShell window showing all three `icacls` commands run in sequence — the final output listing only `DESKTOP-XXXXX\YourUsername: (R)` with no other entries, confirming the permissions are correctly locked down.](screenshot11.png)

---

### Step 4 — Verify SSH Access

Once I had an EC2 instance running (covered in the next section), I could connect using:

```powershell
ssh -i "$env:USERPROFILE\.ssh\My-Desktop-Key-Pair.pem" ubuntu@<public-ip>
```

Replace `<public-ip>` with the public IPv4 address of your EC2 instance. The default username for Ubuntu AMIs is `ubuntu`.

---

## Summary

Three foundational pieces are now in place:

| Component | Details |
|---|---|
| IAM Admin User | `projectx-prod-admin` in the `Administrators` group with `AdministratorAccess`, MFA enabled |
| AWS CLI | Configured with `projectx-prod-admin` access keys, region `ap-southeast-1`, verified with `sts get-caller-identity` |
| SSH Key Pair | `My-Desktop-Key-Pair.pem` stored in `~\.ssh\`, permissions locked to current user via `icacls` |

With these in place, every subsequent step in the series — provisioning EC2 instances, managing S3 buckets, configuring IAM policies, and SSHing into private servers — is ready to go.

---

*Next up — Part 3: Setting Up the ProjectX Production VPC.*
