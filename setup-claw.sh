#!/bin/bash

echo "===== UPDATE SYSTEM ====="
sudo apt update -y

echo "===== INSTALL DEPENDENCIES ====="
sudo apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev cpufrequtils

echo "===== SET CPU PERFORMANCE MODE ====="
sudo cpupower frequency-set -g performance 2>/dev/null

echo "===== ENABLE HUGE PAGES ====="
sudo sysctl -w vm.nr_hugepages=128

echo "===== CLONE XMRIG ====="
cd ~
rm -rf xmrig
git clone https://github.com/xmrig/xmrig.git

echo "===== BUILD XMRIG ====="
cd xmrig
mkdir build
cd build
cmake ..
make -j$(nproc)

echo "===== ALLOW MEMORY LOCK ====="
sudo setcap cap_ipc_lock=+ep ./xmrig

echo "===== CREATE CONFIG ====="

cat <<EOF > config.json
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-threads-hint": 95
  },
  "randomx": {
    "mode": "auto"
  },
  "pools": [
    {
      "algo": "rx/0",
      "coin": "monero",
      "url": "gulf.moneroocean.stream:10128",
      "user": "WALLET_ADDRESS",
      "pass": "server1",
      "rig-id": "node-$(hostname)",
      "keepalive": true,
      "tls": false
    }
  ]
}
EOF

echo "===== CPU INFO ====="
lscpu

echo "===== START MINER ====="

taskset -c 0-$(($(nproc)-1)) ./xmrig