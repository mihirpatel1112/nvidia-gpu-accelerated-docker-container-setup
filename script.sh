#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "=== Step 1: Install Docker Engine ==="
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Ensuring Docker service is running..."
if ! systemctl is-active --quiet docker; then
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "Docker started."
else
    echo "Docker already active."
fi

echo "=== Step 2: Install NVIDIA GPU Driver ==="
sudo apt-get update -y
sudo apt-get install -y nvidia-driver-535 nvidia-utils-535

echo "Attempting to load NVIDIA kernel modules..."
if sudo modprobe nvidia; then
    echo "NVIDIA module loaded successfully."
else
    echo "⚠️  Failed to load NVIDIA module. Reboot may be required."
fi


# Asking to reboot
echo "Driver installation complete. A reboot is required to activate the NVIDIA kernel modules."
while true; do
    read -p "Do you want to reboot now? [Y/n]: " resp
    case "$resp" in
        [Yy]* | "" )
            echo "Rebooting..."
            sudo reboot
            exit 0
            ;;
        [Nn]* )
            echo "Skipping reboot. You must reboot later for full activation."
            break
            ;;
        * )
            echo "Please answer Y or N."
            ;;
    esac
done

echo "Checking GPU status on host..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi || echo "⚠️  nvidia-smi failed. Driver may not be active yet."
else
    echo "❌ nvidia-smi not found — driver install may have failed."
    exit 1
fi

echo "=== Step 3: Install NVIDIA Container Toolkit ==="
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)

if [ ! -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
else
    echo "NVIDIA Container Toolkit repository already added. Skipping."
fi

sudo apt-get update -y
sudo apt-get install -y nvidia-container-toolkit

echo "Configuring Docker runtime for NVIDIA GPUs..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo "=== Step 4: Test GPU access inside Docker ==="
if sudo docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    echo "✅ GPU access inside Docker confirmed."
else
    echo "❌ GPU access inside Docker failed. Check driver and runtime setup."
    exit 1
fi

echo "All done. Setup is complete."
