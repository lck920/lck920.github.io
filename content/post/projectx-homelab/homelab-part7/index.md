---
title: "Part 6 - Attack 3: IP Spoofing"
date: 2026-05-21
description: "Using NetImpostor to spoof a victim's IP address by flooding the network gateway's ARP table, then confirming the spoofed traffic through Wireshark."

tags:
  - cybersecurity
  - homelab
  - na101

categories:
  - homelab writeup
  - networks and attacks 101
---

# Attack 3 — IP Spoofing

## Prerequisites

Before starting, I made sure the following were in place:

1. VirtualBox or VMware Workstation Pro installed
2. `project-x-linux-client` is turned on and logged in
3. `project-x-attacker` is turned on

## Scenario
 
In this scenario, I acted as the attacker (`project-x-attacker`), already positioned on the same `10.0.0.0/24` subnet as my victim. Rather than targeting my victim's machine directly, I targeted the **network gateway** (`10.0.0.1`) — the single point all devices on the subnet use to communicate outward. By flooding the gateway's ARP table with a fake MAC-to-IP mapping, I convinced the gateway that my machine was Jane Doe's workstation (`project-x-linux-client`, `10.0.0.101`). Any traffic routed through the gateway would then treat me as if I was Jane.

## Likeliness Meter

![Likeliness Meter](attack3.png)

**Rating: Moderate**

Classic IP spoofing breaks TCP handshakes — because I receive no reply traffic (responses go back to the real IP owner), completing a proper three-way handshake is not possible. Modern services also tend to rely on cryptographic authentication well beyond just trusting a source IP. That said, it still rates **Moderate** because connectionless, one-way scenarios — like UDP-based DDoS amplification attacks — don't need a handshake at all. For those use cases, IP spoofing remains a practically relevant and widely abused technique. The other hard constraint: I had to be on the same local network as the device I'm impersonating.

## Background: IP Spoofing

Before jumping into the attack, I wanted to understand what IP spoofing actually is and why it works.

**IP spoofing** is the act of falsifying the source IP address in a packet header to make traffic appear as though it is originating from a trusted or different source. Every IP packet contains a header with fields for the source and destination IP address — and unlike higher-level protocols like TLS, the IP layer itself has no mechanism to verify whether the source address is legitimate. It simply trusts what it's told.

Tools and custom code can be used to inject a fake IP address into the IP header, making traffic look like it came from anywhere the attacker chooses. IP spoofing can be deployed to simulate, mask, or hide an attacker's real network traffic through a legitimate device — with the key limitation that the attacker must already be part of the same local network as the device they're intending to impersonate.

## How IP Spoofing Works

The foundation of IP spoofing is at the packet level. IP packets contain headers with information about the packet — including the source and destination IP address. When I craft a packet with a forged source IP, any device or service that receives it and trusts based on IP alone will believe the traffic came from my spoofed address.

In a local network context, IP spoofing is typically layered on top of ARP manipulation. I flooded the **network gateway's** ARP table with fake MAC-to-IP mappings — associating my own MAC address with the victim's IP. Once the gateway accepted my spoofed entry, it routed traffic accordingly, and my machine effectively presented itself as the victim to the rest of the network.

### NetImpostor

I used **[NetImpostor](https://github.com/tastypepperoni/NetImpostor)** to carry out the attack — a brand new open-source IP spoofing tool I discovered while building this exercise. All credit to its developer, tastypepperoni.

NetImpostor works by flooding fake IP-to-MAC mappings to the ARP table of the victim network's gateway. Once the spoofed entry is in place, it uses a **SOCKS5 proxy** to route traffic through the spoofed IP address — since I will have both my real IP and the spoofed IP active simultaneously, proxychains facilitates communication specifically for the spoofed identity.

>  For a deeper technical breakdown of how NetImpostor achieves stateful connections with a spoofed source IP, read the developer's own writeup: [Stateful connection with spoofed source IP — NetImpostor](https://tastypepperoni.medium.com/stateful-connection-with-spoofed-source-ip-netimpostor-ece8b950a981)

## Security Implications

Why does IP spoofing matter?

The primary use cases are **impersonation, traffic misdirection, and attack obfuscation**. An attacker who can present a trusted source IP can exploit environments that rely on IP-based access controls to:

- **Bypass IP allowlists** — Firewall rules, internal APIs, or legacy systems that trust based on IP alone can be fooled
- **Amplify DDoS attacks** — Spoofed source IPs are the backbone of reflection and amplification attacks, where requests are sent to public servers (DNS resolvers, NTP servers) with the victim's IP as the return address — causing those servers to flood the victim with responses
- **Obscure attack origin** — Traffic logs point to the spoofed IP rather than the attacker's real address, complicating forensic investigation and incident response

**The detection opportunity** is the same as with ARP cache poisoning — my NetImpostor's ARP flooding leaves visible signals in packet captures. A single MAC address associating itself with multiple IPs, or an unexpected MAC-to-IP mapping at the gateway, are the giveaways. Wireshark catches this clearly, as I'll demonstrate.

## Running the Attack

### Step 1 — Set Up NetImpostor on the Attacker Machine

I navigated to `project-x-attacker` (Kali Linux).

I went to my attacker's home directory and cloned the NetImpostor repository:

```bash
cd ~
git clone https://github.com/tastypepperoni/NetImpostor.git
cd NetImpostor
```

![Cloning the NetImpostor repository down to my Kali machine.](screenshot1.png)

NetImpostor is written in Go, so I installed the Go compiler and built the binary:

```bash
sudo apt-get update
sudo apt install golang-go -y
go build -o NetImpostor
```

I saw Go pulling in dependencies during the build. Once complete, I ran `ls` to confirm the `NetImpostor` executable had been created.

![Successfully building the NetImpostor Go binary.](screenshot2.png)

### Step 2 — Configure Proxychains

NetImpostor routes spoofed traffic through a SOCKS5 proxy on port `1080`. The default proxychains config uses a different port, so I needed to update it:

```bash
sudo nano /etc/proxychains4.conf
```

I scrolled to the very bottom of the file and changed the last line to:

```
socks5 127.0.0.1 1080
```

I saved and exited.

![Configuring proxychains to use port 1080 for my SOCKS5 proxy.](screenshot3.png)

### Step 3 — Start a Wireshark Capture

Before running NetImpostor, I opened **Wireshark** on my Kali machine via the search bar and started a capture on `eth0`. I wanted to capture the spoofed traffic in real time as the attack ran — this would be my confirmation that the spoofing worked.

### Step 4 — Run NetImpostor

I opened a terminal on `project-x-attacker` and ran NetImpostor, targeting the network gateway and specifying Jane's workstation as the IP to impersonate:

```bash
sudo ./NetImpostor -i eth0 --impersonate 10.0.0.101 --targets 10.0.0.1
```

- `-i eth0` — the network interface to use
- `--impersonate 10.0.0.101` — Jane's workstation IP, the address I'm spoofing
- `--targets 10.0.0.1` — the network gateway whose ARP table I'm flooding

![Running NetImpostor to flood the gateway's ARP table.](screenshot4.png)

### Step 5 — Send Traffic Through the Spoofed IP

I opened a **new terminal tab** and routed a `curl` request through proxychains — this forced the request to travel through the SOCKS5 proxy using `10.0.0.101` as the source IP instead of my attacker's real address:

```bash
proxychains curl https://google.com/
```

>  I got a `socket error or timeout` on the first attempt — this is normal. NetImpostor needs a moment to propagate the spoofed ARP entry to the gateway. I tried the command a few more times.

![Sending my curl request through proxychains using the spoofed IP.](screenshot5.png)

### Step 6 — Confirm the Spoofing in NetImpostor Output

I switched back to the first terminal tab where NetImpostor was running.

I saw output confirming the spoofing was active — NetImpostor logged that it had successfully associated `10.0.0.101` with my attacker MAC address at the gateway.

![NetImpostor logs proving the gateway had been successfully poisoned.](screenshot6.png)

### Step 7 — Confirm the Spoofed Traffic in Wireshark

I switched back to Wireshark and stopped the capture.

I scrolled through the captured packets looking for ARP entries. I was looking for two key signals:

1. An ARP reply showing `10.0.0.101` mapped to **my attacker MAC address** — this is the spoofed entry NetImpostor injected into the gateway's ARP table
2. An outbound packet to Google's public IP showing **`10.0.0.101` as the source** — confirming traffic actually left my attacker machine presenting Jane's IP

![Wireshark showing both the malicious ARP reply and the outbound request carrying the spoofed IP address.](screenshot7.png)

I successfully IP spoofed Jane's workstation (`10.0.0.101`). From the network's perspective, the traffic came from Jane — even though Jane's machine never sent a single packet.

## Conclusion

IP spoofing is one of those techniques that sounds more powerful than it often is in practice. Modern cryptographic authentication — TLS, signed tokens, certificates — means that simply presenting a trusted source IP rarely grants meaningful access to a well-secured service. And because classic IP spoofing breaks TCP handshakes, my two-way communication with the spoofed identity was limited.

That said, it remains a relevant and actively used technique in the right contexts:
- **DDoS amplification** — where connectionless UDP traffic is all that's needed
- **Internal network impersonation** — where legacy systems or internal APIs still make access decisions based on IP alone
- **Attack obfuscation** — making forensic attribution harder during an incident

What this exercise also demonstrated to me is the layered nature of these attacks. NetImpostor doesn't just manipulate IP headers — it relies on ARP table manipulation at the gateway as its foundation. The signals it leaves behind are the same ones I saw in Attack 1: unexpected MAC-to-IP mappings, a single MAC address associated with multiple IPs, spoofed ARP replies visible in Wireshark.

The key takeaway from the blue team side: **IP-based trust is not enough**. Pair IP-based controls with cryptographic authentication, monitor gateway ARP tables for anomalous MAC-to-IP mappings, and keep packet capture tooling in place — because Wireshark doesn't lie.

---

*Next up — DoS Attack, where I shift from impersonation into availability disruption.*
