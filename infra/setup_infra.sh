#!/bin/bash

# Exit on error
set -e

# Variables
REPO_URL="https://your-git-repo-url.git"  # Replace with your actual Git repo URL
PROJECT_NAME="infra"
INSTALL_DIR="/opt/$PROJECT_NAME"
SUBNET="192.168.1.0/24"  # Adjust to your network
GATEWAY="192.168.1.1"    # Adjust to your gateway
BASE_IP="192.168.1.101"

# Function to increment IP address
increment_ip() {
    ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    echo "$i1.$i2.$i3.$((i4 + 1))"
}

# Function to check if Docker network exists
network_exists() {
    docker network inspect "$1" &> /dev/null
}

echo "[INFO] Checking and creating Docker MACVLAN network..."
# Create the Docker MACVLAN network only if it doesn't exist
if network_exists lan_bridge; then
    echo "[INFO] Docker network 'lan_bridge' already exists. Skipping creation."
else
    docker network create \
      --driver=macvlan \
      --subnet=$SUBNET \
      --gateway=$GATEWAY \
      --opt parent=eth0 \
      lan_bridge
    echo "[INFO] Docker MACVLAN network 'lan_bridge' created."
fi

echo "[INFO] Configuring static IPs for Docker Compose files..."
CURRENT_IP=$BASE_IP
for dir in $(find $INSTALL_DIR -maxdepth 1 -type d \( ! -name "." ! -name ".git" \)); do
  cd $dir
  if [ -f docker-compose.yml ]; then
    echo "[INFO] Updating Docker Compose file in $dir..."
    # Check if the file already includes 'lan_bridge'
    if ! grep -q "lan_bridge" docker-compose.yml; then
      sed -i "/services:/a \  networks:\n    lan_bridge:\n      external: true" docker-compose.yml
      sed -i "/networks:/a \  lan_bridge:\n    ipv4_address: $CURRENT_IP" docker-compose.yml
      CURRENT_IP=$(increment_ip $CURRENT_IP)  # Increment the IP for the next service
    else
      echo "[INFO] Static IP configuration already exists in $dir/docker-compose.yml. Skipping."
    fi
  fi
  cd $INSTALL_DIR
done
