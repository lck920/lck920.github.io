#!/bin/bash
# Setup script for ProjectX Vulnerable Application
# This script sets up the vulnerable Flask app with hardcoded secrets
# Run this manually after SSH'ing into the EC2 instance: sudo bash /opt/projectx-app/setup-vulnerable-app.sh

set -euo pipefail

echo "[+] Setup script start"

# Ensure dirs exist
mkdir -p /opt/projectx-app /opt/projectx-app/config

# Install packages if not already installed
echo "[+] Installing packages..."
dnf -y install python3-pip aws-cli 


# Install Flask (always check and install to ensure it's available)
echo "[+] Checking/Installing Flask..."
if ! python3 -c "import flask" 2>/dev/null; then
    echo "[+] Flask not found, installing..."
    pip3 install --no-cache-dir flask
else
    echo "[+] Flask is already installed"
fi

# Verify Flask installation
if python3 -c "import flask" 2>/dev/null; then
    FLASK_VER=$(python3 -c 'import flask; print(flask.__version__)' 2>/dev/null || echo "unknown")
    echo "[+] Flask verified: $FLASK_VER"
else
    echo "[!] ERROR: Flask installation failed!"
    exit 1
fi

# Wait for IAM role if needed
echo "[+] Checking IAM role..."
if ! aws sts get-caller-identity &>/dev/null 2>&1; then
    echo "[+] Waiting for IAM role to be ready..."
    for i in {1..30}; do
        if aws sts get-caller-identity &>/dev/null 2>&1; then
            echo "[+] IAM role is ready"
            break
        fi
        sleep 2
    done
else
    echo "[+] IAM role is ready"
fi

# Get S3 bucket name from environment or find it
echo "[+] Looking for S3 bucket..."
BUCKET_NAME="${S3_BUCKET_NAME:-}"
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME=$(aws s3 ls 2>/dev/null | grep -i secrets | awk '{print $3}' | head -1 || true)
    if [ -n "$BUCKET_NAME" ]; then
        echo "[+] Found S3 bucket: $BUCKET_NAME"
    else
        echo "[!] Could not find S3 bucket automatically"
    fi
else
    echo "[+] Using S3 bucket from environment: $BUCKET_NAME"
fi

# VULNERABLE: hardcoded secrets in .env file
echo "[+] Creating .env file with hardcoded secrets..."
cat >/opt/projectx-app/.env <<ENVEOF
DB_HOST=prod-database.internal
DB_PORT=5432
DB_USER=admin
DB_PASSWORD=HardcodedEnvPassword789!
DB_NAME=customer_data
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
API_KEY=sk_live_userdata_example_key
S3_BUCKET_NAME=${BUCKET_NAME}
ENVEOF

cp /opt/projectx-app/.env /opt/projectx-app/config/.env
chmod 644 /opt/projectx-app/.env /opt/projectx-app/config/.env

# Download secrets/config file from S3 if bucket is available
if [ -n "$BUCKET_NAME" ]; then
    echo "[+] Downloading config file from S3 bucket: $BUCKET_NAME"
    aws s3 cp s3://$BUCKET_NAME/config/app-config.json /tmp/app-secrets.json || {
        echo "[!] Warning: Could not download config file from S3. Continuing..."
    }
else
    echo "[!] Warning: S3 bucket name not found. Config file will not be downloaded."
fi

# Create Flask app (intentionally exposes .env)
echo "[+] Creating Flask application..."
cat >/opt/projectx-app/app.py <<'PYEOF'
from flask import Flask, jsonify, send_file
import json, os

app = Flask(__name__)

S3_SECRETS = "/tmp/app-secrets.json"
ENV_ROOT = "/opt/projectx-app/.env"
ENV_CFG  = "/opt/projectx-app/config/.env"

def load_s3():
    """Load config file from S3 (simple key=value format)"""
    config = {}
    try:
        with open(S3_SECRETS, "r") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    config[key.strip()] = value.strip()
    except Exception:
        pass
    return config

@app.route("/")
def index():
    bucket_name = os.environ.get("S3_BUCKET_NAME", "unknown")
    return f"<h1>ProjectX Application</h1><p>Welcome to ProjectX</p><p>Status: Running</p><p>Config Source: s3://{bucket_name}</p>"

@app.route("/health")
def health():
    return jsonify({"status": "ok", "note": "Deliberately vulnerable lab"})

@app.route("/config")
def config():
    s3 = load_s3()
    bucket_name = os.environ.get("S3_BUCKET_NAME", "unknown")
    return jsonify({
        "s3_bucket": bucket_name,
        "s3_bucket_url": f"s3://{bucket_name}/config/app-config.json",
        "db_host": s3.get("DB_HOST", "unknown"),
        "hint": "Look for accidentally exposed configuration files"
    })

# VULNERABLE: direct exposure of secrets file
@app.route("/env")
def env_root():
    return send_file(ENV_ROOT, mimetype="text/plain")

@app.route("/config/env")
def env_cfg():
    # also vulnerable
    return send_file(ENV_CFG, mimetype="text/plain")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

# Create systemd service to make it survive reboots
echo "[+] Creating systemd service..."
cat >/etc/systemd/system/projectx.service <<UNITEOF
[Unit]
Description=ProjectX Vulnerable Flask App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/projectx-app
Environment="S3_BUCKET_NAME=${BUCKET_NAME}"
ExecStart=/usr/bin/python3 /opt/projectx-app/app.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF

# Reload systemd and enable/start service
echo "[+] Setting up systemd service..."
systemctl daemon-reload
systemctl enable projectx.service
systemctl start projectx.service

# Wait a moment for service to start
sleep 5

# Check service status
echo "[+] Checking service status..."
systemctl status projectx.service --no-pager -l || true

# Verify it's running
echo "[+] Testing Flask application..."
if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo "[+] SUCCESS: Flask application is running on port 8080"
    echo "[+] Check logs with: journalctl -u projectx.service -f"
else
    echo "[!] WARNING: Service may not be responding."
    echo "[!] Check service status: systemctl status projectx.service"
    echo "[!] Check service logs: journalctl -u projectx.service -n 50"
    echo "[!] Check if Flask app file exists: ls -la /opt/projectx-app/app.py"
    echo "[!] Try running manually: cd /opt/projectx-app && python3 app.py"
fi

echo "[+] Setup script complete"
