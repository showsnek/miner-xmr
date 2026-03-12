#!/usr/bin/env bash
set -euo pipefail

VERSION="3.0"
WALLET="${1:-YOUR_WALLET}"
EMAIL="${2:-}"
INSTALL_DIR="${HOME}/moneroocean"
SERVICE_NAME="moneroocean_miner"
XMRIG_REPO="https://github.com/xmrig/xmrig.git"

if [[ -z "${WALLET}" || "${WALLET}" == "YOUR_WALLET" ]]; then
  echo "Usage: bash setup_mo_xmrig.sh <wallet> [email]"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

if ! command -v nproc >/dev/null 2>&1; then
  echo "nproc is required"
  exit 1
fi

CPU_THREADS="$(nproc)"
HOST_TAG="$(hostname | cut -f1 -d'.' | sed -E 's/[^a-zA-Z0-9_-]+/_/g')"
[[ -z "${HOST_TAG}" ]] && HOST_TAG="node"
PASS="${HOST_TAG}"
[[ -n "${EMAIL}" ]] && PASS="${HOST_TAG}:${EMAIL}"

power2() {
  local n="$1"
  local p=1
  while [[ "$p" -lt "$n" ]]; do
    p=$((p * 2))
  done
  echo "$p"
}

compute_port() {
  local exp_hashrate
  local port
  exp_hashrate=$(( CPU_THREADS * 700 / 1000 ))
  [[ "$exp_hashrate" -lt 1 ]] && exp_hashrate=1
  port=$(( exp_hashrate * 30 ))
  port="$(power2 "$port")"
  port=$(( 10000 + port ))
  [[ "$port" -lt 10001 ]] && port=10001
  [[ "$port" -gt 18192 ]] && port=18192
  echo "$port"
}

POOL_PORT="$(compute_port)"

choose_threads_hint() {
  if [[ "$CPU_THREADS" -le 2 ]]; then
    echo "75"
  elif [[ "$CPU_THREADS" -le 4 ]]; then
    echo "85"
  else
    echo "95"
  fi
}

THREADS_HINT="$(choose_threads_hint)"

compute_hugepages() {
  if [[ "$CPU_THREADS" -le 4 ]]; then
    echo "512"
  elif [[ "$CPU_THREADS" -le 8 ]]; then
    echo "768"
  else
    echo "$((1168 + CPU_THREADS))"
  fi
}

HUGEPAGES="$(compute_hugepages)"

echo "== MoneroOcean/XMRig optimized setup v${VERSION} =="
echo "CPU threads: ${CPU_THREADS}"
echo "Pool port: ${POOL_PORT}"
echo "Threads hint: ${THREADS_HINT}"
echo "Hugepages: ${HUGEPAGES}"
echo

sudo apt update -y
sudo apt install -y \
  curl ca-certificates git build-essential cmake \
  libuv1-dev libssl-dev libhwloc-dev \
  msr-tools util-linux

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

download_official_binary() {
  local api_url latest_url asset_url
  api_url="https://api.github.com/repos/xmrig/xmrig/releases/latest"
  latest_url="$(curl -fsSL "${api_url}" | grep '"browser_download_url"' | grep 'linux-static-x64.tar.gz' | head -n1 | cut -d '"' -f4 || true)"

  if [[ -z "${latest_url}" ]]; then
    return 1
  fi

  rm -rf "${INSTALL_DIR:?}"/*
  curl -fL "${latest_url}" -o /tmp/xmrig.tar.gz
  tar -xzf /tmp/xmrig.tar.gz -C "${INSTALL_DIR}" --strip-components=1
  rm -f /tmp/xmrig.tar.gz

  [[ -x "${INSTALL_DIR}/xmrig" ]]
}

build_from_source() {
  rm -rf "${INSTALL_DIR:?}"/*
  git clone --depth 1 "${XMRIG_REPO}" "${INSTALL_DIR}/src"
  mkdir -p "${INSTALL_DIR}/src/build"
  cd "${INSTALL_DIR}/src/build"
  cmake ..
  make -j"$(nproc)"
  cp ./xmrig "${INSTALL_DIR}/xmrig"
  cd "${INSTALL_DIR}"
}

echo "== Fetching XMRig =="
if ! download_official_binary; then
  echo "Official binary failed, building from source..."
  build_from_source
fi

chmod +x "${INSTALL_DIR}/xmrig"

echo "== System tuning =="
sudo modprobe msr || true
echo "vm.nr_hugepages=${HUGEPAGES}" | sudo tee /etc/sysctl.d/99-xmrig.conf >/dev/null
sudo sysctl --system >/dev/null || true

if command -v cpupower >/dev/null 2>&1; then
  sudo cpupower frequency-set -g performance >/dev/null 2>&1 || true
fi

sudo setcap cap_ipc_lock=+ep "${INSTALL_DIR}/xmrig" || true

cat > "${INSTALL_DIR}/config.json" <<EOF
{
  "autosave": true,
  "background": false,
  "colors": true,
  "title": true,
  "randomx": {
    "mode": "auto",
    "1gb-pages": false,
    "rdmsr": true,
    "wrmsr": true,
    "cache_qos": false,
    "numa": true,
    "scratchpad_prefetch_mode": 1
  },
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "huge-pages-jit": true,
    "hw-aes": null,
    "priority": 2,
    "memory-pool": false,
    "yield": true,
    "max-threads-hint": ${THREADS_HINT}
  },
  "donate-level": 1,
  "pools": [
    {
      "algo": "rx/0",
      "coin": "monero",
      "url": "gulf.moneroocean.stream:${POOL_PORT}",
      "user": "${WALLET}",
      "pass": "${PASS}",
      "rig-id": "${HOST_TAG}",
      "keepalive": true,
      "tls": false
    }
  ],
  "log-file": "${INSTALL_DIR}/xmrig.log",
  "syslog": false
}
EOF

cat > "${INSTALL_DIR}/miner.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${INSTALL_DIR}"
exec "${INSTALL_DIR}/xmrig" --config="${INSTALL_DIR}/config.json"
EOF
chmod +x "${INSTALL_DIR}/miner.sh"

if command -v systemctl >/dev/null 2>&1; then
  echo "== Creating systemd service =="
  sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=MoneroOcean XMRig Miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/xmrig --config=${INSTALL_DIR}/config.json
Restart=always
RestartSec=10
Nice=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable "${SERVICE_NAME}.service" >/dev/null
  sudo systemctl restart "${SERVICE_NAME}.service"

  echo
  echo "Service started."
  echo "Check status: sudo systemctl status ${SERVICE_NAME}"
  echo "View logs:    sudo journalctl -u ${SERVICE_NAME} -f"
else
  echo "systemd not found, starting in foreground..."
  "${INSTALL_DIR}/xmrig" --config="${INSTALL_DIR}/config.json"
fi

echo
echo "Setup complete."
echo "Install dir: ${INSTALL_DIR}"
echo "Pool: gulf.moneroocean.stream:${POOL_PORT}"
echo "Threads hint: ${THREADS_HINT}"
