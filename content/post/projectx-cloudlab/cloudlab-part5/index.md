---
title: "Part 5: Deploying and Configuring the Web Server"
date: 2026-05-27
description: "Deploying projectx-prod-websvr into the private subnet, connecting through the jumpbox, and configuring the server with Node.js, Astro, and Tailwind CSS."

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


# Compute — Deploying and Configuring the Web Server

## Prerequisites

Before starting, I made sure the following were in place:

1. `projectx-prod-vpc` has been created with all subnets configured
2. `projectx-prod-jumpbox` is running and accessible via SSH
3. `my-desktop-key-pair` key pair exists locally
4. AWS CLI is configured with appropriate credentials
5. The NAT Gateway (`projectx-prod-nat-gw`) is deployed and the private route table updated — the web server needs outbound internet access to install packages

---

## Overview

This guide deploys `projectx-prod-websvr` — the production web server EC2 instance that will eventually host the ProjectX threat intelligence application. The web server lives in the **private subnet**, which means it has no public IP and is unreachable directly from the internet. All access goes through the jumpbox.

After deploying the instance, we'll connect through the jumpbox and install the full development stack: Node.js, Astro (a modern static site framework), and Tailwind CSS. The actual application code will be added in a later section — this guide gets the environment ready.

---

## Step 1 — Launch the EC2 Instance

Ensure you're working in the correct AWS region (e.g. `ap-southeast-1` or whichever region your VPC is in).

I navigated to the **EC2** service and select **Launch instance**.

### Instance Details

Configure the following:

- **Name:** `projectx-prod-websvr`
- **AMI:** Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
- **Instance type:** `t3.small`
- **Key pair:** Select `my-desktop-key-pair`

> The web server uses `t3.small` rather than `t3.micro` — Astro's build process needs slightly more CPU and memory than the jumpbox.

![EC2 Launch Instance page showing `projectx-prod-websvr` as the name, Ubuntu Server 24.04 LTS selected, `t3.small` as the instance type, and `my-desktop-key-pair` selected in the key pair dropdown.](screenshot1.png)

---

### Network Settings

I selected **Edit** to configure network settings.

- **VPC:** Select `projectx-prod-vpc`
- **Subnet:** Select `projectx-prod-private-web-subnet`
- **Auto-assign Public IP:** **Disable** — this is a private subnet, no public IP needed

**Create a new security group:**

- **Security group name:** `projectx-prod-websvr-sg`
- **Description:** Security group for projectx-prod-websvr

**Inbound rule:**

- **Type:** SSH
- **Port:** 22
- **Source type:** Custom
- **Source:** Select the security group `projectx-prod-jumpbox-sg`

> 📝 By setting the SSH source to the jumpbox's security group rather than an IP range, we ensure the web server only accepts SSH connections that originate from the jumpbox — not from anywhere else on the internet.

![EC2 Network Settings panel showing `projectx-prod-vpc` selected, `projectx-prod-private-web-subnet` chosen, Auto-assign Public IP disabled, and the new `projectx-prod-websvr-sg` configured with SSH allowed only from `projectx-prod-jumpbox-sg`.](screenshot2.png)

---

### Storage

I left storage settings as default — 8 GiB gp3.

### Advanced Details

Leave all other settings as default. No user data script is needed for the web server.

---

## Step 2 — Launch and Confirm

I reviewed the configuration and select **Launch instance**.

| Setting | Value |
|---|---|
| Name | `projectx-prod-websvr` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | `t3.small` |
| Key pair | `my-desktop-key-pair` |
| VPC | `projectx-prod-vpc` |
| Subnet | `projectx-prod-private-web-subnet` |
| Public IP | Disabled |
| Security group | `projectx-prod-websvr-sg` |

I waited for the instance state to show **Running** and note the **Private IPv4 address** — this is what you'll use to SSH from the jumpbox.

![EC2 Instances list showing `projectx-prod-websvr` with state **Running**, no public IP assigned, and the `projectx-prod-private-web-subnet` subnet visible — confirming the instance is live in the private subnet.](screenshot3.png)

---

## Step 3 — Update the Web Server Security Group

Now that the NAT Gateway is in place (completed during the VPC networking step), update the web server's security group to also allow outbound HTTPS traffic — needed for package installations and Node.js downloads.

I navigated to **EC2 → Security Groups → `projectx-prod-websvr-sg`**.

I added an **inbound rule**:

- **Type:** HTTPS
- **Port:** 443
- **Source:** `0.0.0.0/0`

The full inbound rules for `projectx-prod-websvr-sg` should now be:

| Type | Port | Source |
|---|---|---|
| SSH | 22 | `projectx-prod-jumpbox-sg` |
| HTTPS | 443 | `0.0.0.0/0` |

![AWS Security Group page for `projectx-prod-websvr-sg` showing both inbound rules — SSH allowed from `projectx-prod-jumpbox-sg` and HTTPS allowed from `0.0.0.0/0`.](screenshot4.png)

---

## Step 4 — Connect via Jumpbox

Since `projectx-prod-websvr` has no public IP, access goes through the jumpbox.

### Connect to the Jumpbox with Agent Forwarding

From your local machine, enable the SSH agent and add your key (if not already done):

**macOS / Linux:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/my-desktop-key-pair.pem
ssh -A -i ~/.ssh/my-desktop-key-pair.pem ubuntu@<jumpbox-public-ip>
```

**Windows PowerShell:**
```powershell
Start-Service ssh-agent
ssh-add C:\Users\<username>\.ssh\my-desktop-key-pair.pem
ssh -A -i $env:USERPROFILE\.ssh\my-desktop-key-pair.pem ubuntu@<jumpbox-public-ip>
```

![Terminal showing the SSH connection to the jumpbox with `-A` flag for agent forwarding — landing on the `ubuntu@projectx-prod-jumpbox` shell prompt.](screenshot5.png)

### SSH from Jumpbox to Web Server

From inside the jumpbox, SSH into the web server using its private IP:

```bash
ssh ubuntu@<websvr-private-ip>
```

The first connection will prompt you to accept the host fingerprint — type `yes` and press Enter.

![Terminal showing `ssh ubuntu@<private-ip>` from inside the jumpbox, with the fingerprint acceptance prompt and the `ubuntu@projectx-prod-websvr` shell prompt confirming a successful two-hop connection.](screenshot6.png)

### Optional: SSH Config File

For convenience, you can add a config entry on the jumpbox so `ssh websvr` is all you need:

```bash
sudo mkdir -p ~/.ssh
nano ~/.ssh/config
```

```
Host websvr
    HostName <private-ip-websvr>
    User ubuntu
    IdentityFile ~/.ssh/my-desktop-key-pair.pem
```

Then simply run `ssh websvr` from the jumpbox.

---

## Step 5 — Change the Hostname

On the web server, set the hostname to match the instance name:

```bash
sudo hostnamectl set-hostname projectx-prod-websvr
sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost projectx-prod-websvr/' /etc/hosts
hostnamectl
```

![Terminal showing `hostnamectl` output on the web server with `Static hostname: projectx-prod-websvr` — confirming the hostname was set correctly.](screenshot7.png)

---

## Step 6 — Install Development Tools

All commands from here are run on `projectx-prod-websvr` (connected via the jumpbox).

### Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

![Terminal showing `sudo apt update && sudo apt upgrade -y` completing — package lists fetched and upgrades applied, confirming the NAT Gateway is routing outbound traffic correctly from the private subnet.](screenshot8.png)

### Install Node.js 20.x

Astro requires Node.js. Install the LTS version (20.x) using the NodeSource repository:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

I verified the installation:

```bash
node --version
npm --version
```

I received Node.js `22.x` and npm `10.x` or higher.

![Terminal showing `node --version` returning `v20.x.x` and `npm --version` returning `10.x.x` — confirming Node.js was installed successfully.](screenshot9.png)

### Install Additional Tools

```bash
sudo apt install -y git curl build-essential
```

---

## Step 7 — Install Astro

**Astro** is the web framework we're using to build the ProjectX threat intelligence application. It's designed for content-heavy, fast-loading sites and compiles down to minimal JavaScript.

### I created the Project Directory

```bash
mkdir -p ~/threat-intel-app
cd ~/threat-intel-app
```

### Initialise the Astro Project

```bash
npm create astro@latest .
```

When prompted, choose:

- **Template:** `Empty` (for a clean custom setup)
- **Install dependencies:** Yes
- **TypeScript:** Yes
- **Git repository:** Yes

![Terminal showing the Astro interactive setup prompts — `Empty` template selected, dependencies installing, confirming the project scaffold was created in `~/threat-intel-app`.](screenshot10.png)

### Verify Astro

```bash
npm list astro
```

Astro should appear in the dependency list.

---

## Step 8 — Install Tailwind CSS

**Tailwind CSS** is a utility-first CSS framework we'll use to style the application.

### Install Tailwind and Dependencies

From inside `~/threat-intel-app`:

```bash
npm install -D tailwindcss@3 postcss autoprefixer
```

> 📝 We're using Tailwind v3 specifically — v4 had compatibility issues with the `npx tailwindcss init` command at the time of writing.

### Initialise Tailwind Configuration

```bash
npx tailwindcss init -p
```

This generates two config files:
- `tailwind.config.mjs` — Tailwind configuration
- `postcss.config.mjs` — PostCSS configuration

### Configure Tailwind Content Paths

Edit `tailwind.config.mjs` to tell Tailwind which files to scan for class names:

```bash
nano tailwind.config.mjs
```

Update the `content` array:

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

Save and exit (`Ctrl+X`, then `Y`, then `Enter`).

### Add Tailwind Directives

I created the global CSS file:

```bash
mkdir -p src/styles
nano src/styles/global.css
```

Add the three Tailwind directives:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

Save and exit.

### Import CSS in the Layout

Edit `src/layouts/Layout.astro` (or `src/pages/index.astro` if no layout exists):

```bash
nano src/pages/index.astro
```

Add the import at the top of the frontmatter block:

```astro
---
import '../styles/global.css';
---
```

---

## Step 9 — I verified the Full Installation

Check all tools are installed:

```bash
node --version
npm --version
npx astro --version
npx tailwindcss --version
```

Test the Astro development server:

```bash
cd ~/threat-intel-app
npm run dev
```

The server should start and display a local URL (typically `http://localhost:4321`). Since the web server is in a private subnet, you won't be able to access this URL directly from your browser yet — port forwarding or a reverse proxy would be needed for that. For now, the important thing is that the server starts without errors.

Stop the server with `Ctrl+C`.

![Terminal showing `npm run dev` starting the Astro development server — the `Local: http://localhost:4321` URL printed and no errors in the output, confirming the full stack is working.](screenshot11.png)

---

## Summary

The ProjectX production compute layer is now fully deployed:

| Resource | Location | Access |
|---|---|---|
| `projectx-prod-jumpbox` | Public subnet | SSH from internet via public IP |
| `projectx-prod-websvr` | Private subnet | SSH via jumpbox only |

The web server is configured with Node.js 22.x, Astro, and Tailwind CSS — ready for the application layer. All connections to private resources flow through the jumpbox.

---

*Next up — Part 6: S3 Security Datalake.*
