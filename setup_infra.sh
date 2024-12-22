#!/bin/bash

# Exit on error
set -e

# Variables
REPO_URL="https://github.com/IosefBG/homelab.git"  # Replace with your actual Git repo URL
PROJECT_NAME="infra"
INSTALL_DIR="/opt/$PROJECT_NAME"
SUBNET="192.168.1.0/24"  # Adjust to your network
GATEWAY="192.168.1.1"    # Adjust to your gateway
BASE_IP="192.168.1.101"

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to increment IP address
increment_ip() {
    ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    echo "$i1.$i2.$i3.$((i4 + 1))"
}

# Function to check if a Docker network exists
network_exists() {
    docker network inspect "$1" &> /dev/null
}

echo "[INFO] Updating system and installing prerequisites..."
# Update system and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl unzip jq docker.io docker-compose bind9 bind9-utils dnsutils

echo "[INFO] Creating backup of project directory..."
# Backup the project directory
if [ -d "$INSTALL_DIR" ]; then
    sudo mv $INSTALL_DIR "$INSTALL_DIR.bak.$(date +%Y%m%d%H%M%S)"
fi

echo "[INFO] Checking and installing Terraform..."
# Install Terraform only if not already installed
if ! command_exists terraform; then
    TERRAFORM_VERSION="1.5.7"
    curl -o terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip terraform.zip
    sudo mv terraform /usr/local/bin/
    rm terraform.zip
else
    echo "[INFO] Terraform is already installed."
fi

echo "[INFO] Checking and setting up Docker..."
# Start and enable Docker if not already running
if ! command_exists docker; then
    echo "[INFO] Installing Docker..."
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "[INFO] Docker is already installed and running."
fi

# Check Docker version
docker --version

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

echo "[INFO] Cloning your Git repository..."
# Clone the Git repository only if not already cloned
if [ ! -d "$INSTALL_DIR" ]; then
    sudo mkdir -p $INSTALL_DIR
    sudo chown $USER:$USER $INSTALL_DIR
    git clone $REPO_URL $INSTALL_DIR
else
    echo "[INFO] Repository already cloned. Pulling latest changes..."
    cd $INSTALL_DIR
    git pull
fi

echo "[INFO] Navigating to the project directory..."
cd $INSTALL_DIR

echo "[INFO] Configuring static IPs for Docker Compose files..."
CURRENT_IP=$BASE_IP
for dir in $(find $INSTALL_DIR -maxdepth 1 -type d \( ! -name "." ! -name ".git" \)); do
  cd $dir
  if [ -f docker-compose.yml ]; then
    echo "[INFO] Updating Docker Compose file in $dir..."
    # Ensure lan_bridge is defined as external
    if ! grep -q "networks:" docker-compose.yml; then
      echo -e "\nnetworks:\n  lan_bridge:\n    external: true" >> docker-compose.yml
    fi

    # Add network configuration to the service section
    if ! grep -q "lan_bridge:" docker-compose.yml; then
      sed -i "/services:/a \  networks:\n    lan_bridge:\n      ipv4_address: $CURRENT_IP" docker-compose.yml
      CURRENT_IP=$(increment_ip $CURRENT_IP)
    else
      echo "[INFO] Static IP configuration already exists in $dir/docker-compose.yml. Skipping."
    fi
  fi
  cd $INSTALL_DIR
done


echo "[INFO] Starting Bind9 for local DNS..."
# Set up Bind9
if [ -d "$INSTALL_DIR/bind9" ]; then
  cd "$INSTALL_DIR/bind9"
  docker-compose up -d || echo "[WARN] Bind9 already running or error during startup."
  cd $INSTALL_DIR
else
  echo "[ERROR] Bind9 directory does not exist in the project. Skipping Bind9 setup."
fi

echo "[INFO] Running Terraform to deploy the stack..."
# Run Terraform only if the terraform directory exists
if [ -d "$INSTALL_DIR/terraform" ]; then
  cd "$INSTALL_DIR/terraform"
  terraform init
  terraform apply -auto-approve
  cd $INSTALL_DIR
else
  echo "[ERROR] Terraform directory does not exist in the project. Skipping Terraform deployment."
fi

echo "[INFO] Starting all Docker Compose services..."
# Start all Docker Compose services
for dir in $(find $INSTALL_DIR -maxdepth 1 -type d \( ! -name "." ! -name ".git" ! -name "terraform" ! -name "bind9" \)); do
  cd $dir
  if [ -f docker-compose.yml ]; then
    echo "[INFO] Starting Docker Compose service in $dir..."
    docker-compose up -d || echo "[WARN] Error starting service in $dir."
  fi
  cd $INSTALL_DIR
done

echo "[INFO] Setup completed successfully!"
