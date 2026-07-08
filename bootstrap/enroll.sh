#!/usr/bin/env bash
# Enrolls THIS machine into the lab: installs git+ansible if missing,
# clones this repo, and installs a systemd timer that repeats
# `git pull` + a local ansible-pull run forever, unattended.
#
# Run this once per machine (as root, or with sudo). It is idempotent —
# re-running it just re-installs the same timer/service, safe on a
# machine that's already enrolled.
#
# What a machine becomes is decided by infra/ansible/inventory/hosts.yml
# in this repo, not by anything passed to this script — see
# ARCHITECTURE.md. A machine not yet listed there gets the minimal
# `ungrouped` baseline until someone adds it to a real group.

set -euo pipefail

REPO_URL="${HOMELAB_REPO_URL:-https://github.com/SigSegGit/ITSaHomeLab_Banking_Ops.git}"
INSTALL_DIR="/opt/itsahomelab-banking-ops"
PULL_INTERVAL="${HOMELAB_PULL_INTERVAL:-5min}"

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root (sudo $0)" >&2
    exit 1
fi

echo "==> installing git, ansible"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq git ansible
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git ansible
else
    echo "unsupported distro: install git + ansible manually, then re-run" >&2
    exit 1
fi

echo "==> cloning ${REPO_URL} to ${INSTALL_DIR}"
if [ -d "${INSTALL_DIR}/.git" ]; then
    git -C "${INSTALL_DIR}" pull --ff-only
else
    git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
fi

echo "==> installing required ansible collections"
ansible-galaxy collection install -r "${INSTALL_DIR}/infra/ansible/requirements.yml"

echo "==> installing the reconcile service + timer"
cat >/etc/systemd/system/homelab-reconcile.service <<EOF
[Unit]
Description=Homelab Banking OPS: pull latest config and reconcile this host
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${INSTALL_DIR}
ExecStartPre=/usr/bin/git pull --ff-only
ExecStartPre=/usr/bin/ansible-galaxy collection install -r ${INSTALL_DIR}/infra/ansible/requirements.yml
ExecStart=/usr/bin/ansible-playbook -i localhost, --connection=local \\
    ${INSTALL_DIR}/infra/ansible/site.yml --limit "\$(hostname)"
EOF

cat >/etc/systemd/system/homelab-reconcile.timer <<EOF
[Unit]
Description=Run homelab-reconcile.service on a fixed interval

[Timer]
OnBootSec=1min
OnUnitActiveSec=${PULL_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now homelab-reconcile.timer

echo "==> enrolled. First reconcile run:"
systemctl start --no-block homelab-reconcile.service
echo "    follow it with: journalctl -u homelab-reconcile.service -f"

# Secrets never come from `git pull` (see ARCHITECTURE.md) — if this
# host needs to decrypt SOPS-encrypted values, drop the lab's age key
# at /etc/itsahomelab-banking-ops/age.key by hand (out of band) before the
# first reconcile run touches anything that needs it.
