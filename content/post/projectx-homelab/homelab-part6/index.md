---
title: "Part 5 - Attack 2: MiTM: DNS Zone Poisoning"
date: 2026-05-20
description: "Exploiting a misconfigured internal BIND9 DNS server to redirect victims to a fake web portal and capture credentials."
 
tags:
  - cybersecurity
  - homelab
  - na101

categories:
  - homelab writeup
  - networks and attacks 101
---

## Prerequisites

Before starting, I made sure the following were in place:

1. VirtualBox or VMware Workstation Pro installed
2. My `project-x-corp-svr` is configured with Docker
3. My DNS container (`corp-server-dns-server`) is set up and running
4. My Web container (`corp-server-web-server`) is set up and running
5. My `project-x-attacker` is turned on


## Scenario
 
In this scenario, I acted as the attacker (`project-x-attacker`), having identified an exposed SSH port on the corporate server (`10.0.0.8`). I used it as an entry point into the DNS container running on that host. Once inside the container, I modified the internal BIND9 zone file to redirect `www.projectxcorp.com` to a fake web server I controlled — causing any victim on my network (`project-x-win-client`) who navigates to that domain to land on my cloned login page without any visible warning.

## Likeliness Meter

![Likeliness Meter](attack2.png)

**Rating: Moderate**

DNS zone poisoning on its own would be rated **Unlikely** — it requires the attacker to have already gained access to the DNS server, which is a significant prerequisite. However, DNS as a whole is rated **Moderate** as an attack surface because there is so much that can go wrong: misconfigured zones, open recursion, unvalidated cache entries, weak access controls on zone files. A compromise at any point in the DNS chain leads to severe downstream consequences — traffic redirection, credential theft, and complete loss of network trust.

The key nuance: **public-facing** DNS is typically hardened by large infrastructure providers and difficult to poison. **Internal** DNS servers running in a business LAN — like the one I set up in this lab — are far more likely to have misconfigurations that an attacker can exploit once they're on the network.

## Background: Man-in-the-Middle (MiTM) and DNS

### What is a MiTM Attack?

A **Man-in-the-Middle (MiTM)** attack occurs when a threat actor secretly intercepts, relays, or alters communication between two parties without either party knowing. Both sides believe they're communicating directly with each other — but everything is passing through the attacker.

DNS is one of the most valuable targets for MiTM attacks because it sits at the very foundation of how networks communicate. Every time a user types a domain name into a browser, a DNS query goes out to resolve it to an IP address. If I can control that resolution, I control where the user ends up — regardless of what domain name the user typed.

### What is DNS Zone Poisoning?

DNS Zone Poisoning is a specific variant of DNS-based MiTM. Rather than intercepting DNS queries in transit (DNS cache poisoning), zone poisoning involves **directly modifying the zone file on a DNS server** — the source-of-truth file that defines which IP addresses domain names resolve to.

If I gain write access to a zone file, I can change an `A` record to point any domain to an IP address I control. Every client using that DNS server will then be silently redirected to my attacker machine.

## Impact

A successful DNS zone poisoning attack can lead to:

- **Credential theft** — Users land on a cloned login page and unknowingly hand over their username and password
- **Data interception** — Sensitive information submitted through forms is captured by the attacker
- **Network traffic redirection** — Any service resolved by the poisoned DNS server can be hijacked
- **Loss of integrity** — Users lose the ability to trust that they're talking to the real service

## Running the Attack

### The Objective

My goal was to redirect `www.projectxcorp.com` to a web server I controlled. I copied the real internal portal, made it look identical, and captured credentials when an employee — Jane or John — logged in thinking they were on the legitimate site.

### Step 1 — Reconnaissance from the Attacker Machine

On `project-x-attacker`, I started with an Nmap scan to identify what was running on the corporate server:

```bash
nmap -p1-5000 -Pn -sV 10.0.0.8
```

The scan results showed a few ports of interest — notably **port 22** and **port 2222**. Port 22 is the host SSH service on `project-x-corp-svr` itself. Port 2222 is the SSH service I configured inside the DNS container.

![My Nmap scan against `10.0.0.8` highlighting port 2222, my pathway into the DNS container.](screenshot1.png)

### Step 2 — Brute-Force SSH into the DNS Container

With port 2222 open, I attempted to brute-force the SSH credentials using Hydra:

```bash
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://10.0.0.8 -s 2222
```

The password came back as `admin` — exactly the weak root password I set during the DNS container setup.

![Hydra easily cracking the weak root password.](screenshot2.png)

I logged into the DNS container:

```bash
ssh root@10.0.0.8 -p 2222
# password: november
```

![Successfully SSH-ing into the DNS container on port 2222.](screenshot3.png)

### Step 3 — Post-Compromise Recon Inside the Container

Now that I was inside, I started looking around to understand what this server did.

**Check active network services:**

```bash
netstat -tuln
```

Port 53 was listening — this is a DNS server. Combined with my earlier Nmap finding, this confirmed the container was the internal DNS service for `10.0.0.8`.

![Confirming the presence of DNS services (port 53) via netstat.](screenshot4.png)

**Check recently installed software:**

```bash
grep " install " /var/log/dpkg.log
```

![A quick grep through `dpkg.log` revealed BIND9 was installed.](screenshot5.png)

Searching around confirmed **BIND9** was the DNS software in use. A quick search told me the default BIND9 configuration directory is `/etc/bind`.

### Step 4 — Find and Inspect the Zone File

I navigated to the BIND9 config directory:

```bash
ls /etc/bind
cat /etc/bind/named.conf
```

The `named.conf` file revealed a zone declaration for `projectxcorp.com`, pointing to a zone file at `/etc/bind/zones/db.projectxcorp.com`. I looked at it:

```bash
cat /etc/bind/zones/db.projectxcorp.com
```

The zone file showed the `A` record for `www.projectxcorp.com` currently pointing to `10.0.0.8` — the web container I set up in Part 2. This is the internal corporate portal.

![Inspecting the zone file. The `www` A record was my target for modification.](screenshot6.png)

This was my target. I could edit this file to redirect `www.projectxcorp.com` to any IP I controlled.

### Step 5 — Poison the Zone File

I edited the zone file and changed the `www` A record from `10.0.0.8` to `10.0.0.50` — my attacker machine's IP:

```bash
nano /etc/bind/zones/db.projectxcorp.com
```

I changed:
```
www     IN      A       10.0.0.8
```

To:
```
www     IN      A       10.0.0.50
```

I also incremented the **Serial** number in the SOA record by 1 — this tells BIND9 that the zone has been updated:

```
2         ; Serial  →  change to  3
```

I saved and exited.

![Modifying the zone file in nano to point to my attacker IP and bumping the serial number.](screenshot7.png)

I flushed the DNS cache and restarted BIND9 to apply the change:

```bash
rndc flush
service named restart
```

![Restarting the BIND9 service to load my newly poisoned zone file.](screenshot8.png)

### Step 6 — Stand Up the Fake Web Server on the Attacker Machine

I opened a **new terminal** on `project-x-attacker` (keeping the SSH session to the DNS container open).

I navigated to the Apache web root and set up my fake portal:

```bash
cd /var/www/html
```

I cloned the exercise web files (or copied the `index.html` from the real web container — the one I built in Part 2 — and modified it slightly to capture credentials):

```bash
# Option: copy the real portal's index.html and modify it
# The cloned page should look identical to the real projectxcorp.com portal
# but route form submissions to a local credential capture script
service apache2 start
```

>  My fake page looks identical to `www.projectxcorp.com`. The only difference — any credentials submitted go straight to me.

![My fake web server running on Kali, perfectly mimicking the internal portal.](screenshot9.png)

### Step 7 — Verify the Victim's DNS is Pointing to Our Server

On `project-x-win-client`, I confirmed the machine was using `10.0.0.8` as its DNS resolver. I opened **Control Panel → Network and Internet → Network Connections**, checked the adapter's DNS settings and made sure it was set to `10.0.0.8`.

![Confirming the victim Windows machine is using the DNS server I just poisoned.](screenshot10.png)

From the Windows client, I did a quick DNS lookup to confirm the poison had taken effect:

```cmd
nslookup www.projectxcorp.com
```

The result now returned `10.0.0.50` instead of `10.0.0.8` — my attacker machine.

### Step 8 — The Victim Lands on the Fake Page

Still on `project-x-win-client`, I opened a browser and navigated to:

```
http://www.projectxcorp.com
```

The browser resolved the domain, got back `10.0.0.50`, and loaded my fake portal — which looked exactly like the real `www.projectxcorp.com` internal login page.

![The victim accesses `www.projectxcorp.com` and is seamlessly served my fake portal.](screenshot11.png)

John (logged in as `johnd`) entered his credentials and submitted the form.

![The victim entering their credentials into my trap.](screenshot12.png)

### Step 9 — Capture the Credentials

Back on my attacker machine, I checked the credential capture log:

```bash
cat /var/www/html/creds.log
```

![Checking `creds.log` and retrieving the stolen credentials.](screenshot13.png)

Credentials captured. The victim had no idea they weren't on the real site.

## Conclusion

DNS zone poisoning is a surgical attack. Unlike ARP cache poisoning — which is loud, broadcasts to the whole network, and resets when devices refresh their ARP tables — DNS zone poisoning is persistent. Once I modified the zone file and reloaded BIND9, **every single client** using that DNS server was affected, and the redirect stays in place until someone notices the zone file has changed and reverts it.

The attack chain here is worth reflecting on:

1. An open SSH port on the DNS container with a weak root password gave me initial access
2. Once inside, finding the BIND9 zone file was trivial — it's a well-known default path
3. A two-line edit to the zone file was enough to redirect an entire internal domain
4. The victim had zero indication anything was wrong — the URL in the browser looked correct

This is exactly why DNS security matters:

- **Restrict SSH access** to DNS servers — ideally key-based only, never password auth
- **Lock down zone file permissions** — only the BIND9 process should be able to write to zone files
- **Monitor zone file changes** with file integrity monitoring
- **Use DNSSEC** to cryptographically sign zone records so clients can verify authenticity
- **Audit DNS server access logs** regularly for unexpected logins

The likeliness rating of **Moderate** reflects that while zone poisoning itself requires existing server access, DNS as an attack surface is genuinely relevant — particularly for internal networks where DNS servers are often less hardened than their public-facing counterparts.

---

*Next up — IP Spoofing, where I manipulate packet headers to impersonate trusted sources on the network.*
