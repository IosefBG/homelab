#!/bin/bash

# Exit on error
set -e

# Variables
REPO_URL="https://github.com/IosefBG/homelab.git"
PROJECT_NAME="infra"
INSTALL_DIR="/opt/$PROJECT_NAME"
SUBNET="192.168.1.0/24"
GATEWAY="192.168.1.1"
BASE_IP="192.168.1.101"
ZONE_FILE="$INSTALL_DIR/bind9/config/zones/db.home.devnexuslab.me"

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Function to increment IP address
increment_ip() {
    ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<<"$ip"
    echo "$i1.$i2.$i3.$((i4 + 1))"
}

# Function to check if a Docker network exists
network_exists() {
    docker network inspect "$1" &>/dev/null
}

# Function to add network config to docker-compose
add_network_config() {
    local file=$1
    local service_name=$2
    local ip_address=$3

    # Create a temporary file
    tmp_file=$(mktemp)

    # If networks section exists, remove old lan_bridge config
    if grep -q "^networks:" "$file"; then
        sed '/lan_bridge:/,/external: true/d' "$file" >"$tmp_file"
    else
        # Copy original content and add networks section
        cp "$file" "$tmp_file"
        echo -e "\nnetworks:\n  lan_bridge:\n    external: true" >>"$tmp_file"
    fi

    # Find the main service name if not provided
    if [ -z "$service_name" ]; then
        service_name=$(grep -A 1 "services:" "$file" | tail -n 1 | sed 's/[[:space:]]*//g' | sed 's/://')
    fi

    # Add network configuration to the service
    sed -i "/^  $service_name:/a\    networks:\n      lan_bridge:\n        ipv4_address: $ip_address" "$tmp_file"

    # Replace original file
    mv "$tmp_file" "$file"
}

# Function to update DNS zone file
update_zone_file() {
    local service_name=$1
    local ip_address=$2

    if grep -q "^${service_name}\s\+IN\s\+A" "$ZONE_FILE"; then
        sed -i "/^${service_name}\s\+IN\s\+A/c\\${service_name}\tIN\tA\t${ip_address}" "$ZONE_FILE"
    else
        echo -e "${service_name}\tIN\tA\t${ip_address}" >>"$ZONE_FILE"
    fi
}

# Function to update zone file serial
update_zone_serial() {
    local new_serial=$(date +%Y%m%d)01
    sed -i "s/[0-9]\{10\}\s*;\s*Serial/${new_serial} ; Serial/" "$ZONE_FILE"
}

echo "[INFO] Cleaning up existing Docker containers..."
# Stop all containers
docker stop $(docker ps -aq) 2>/dev/null || true
# Remove all containers
docker rm $(docker ps -aq) 2>/dev/null || true

echo "[INFO] Updating system and installing prerequisites..."
# Update system and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl unzip jq docker.io docker-compose bind9 bind9-utils dnsutils

echo "[INFO] Creating backup of project directory..."
if [ -d "$INSTALL_DIR" ]; then
    sudo mv $INSTALL_DIR "$INSTALL_DIR.bak.$(date +%Y%m%d%H%M%S)"
fi

echo "[INFO] Checking and installing Terraform..."
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
if ! command_exists docker; then
    echo "[INFO] Installing Docker..."
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "[INFO] Docker is already installed and running."
fi

docker --version

echo "[INFO] Checking and creating Docker MACVLAN network..."
if network_exists lan_bridge; then
    echo "[INFO] Removing existing 'lan_bridge' network..."
    docker network rm lan_bridge || true
fi

docker network create \
    --driver=macvlan \
    --subnet=$SUBNET \
    --gateway=$GATEWAY \
    --opt parent=eth0 \
    lan_bridge
echo "[INFO] Docker MACVLAN network 'lan_bridge' created."

echo "[INFO] Cloning your Git repository..."
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

echo "[INFO] Disabling the existing DNS Service..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved


echo "[INFO] Configuring static IPs for Docker Compose files and updating DNS records..."
CURRENT_IP=$BASE_IP
declare -A service_ips

# Create a file to store service IPs
if [ -f $INSTALL_DIR/service_ips.txt ]; then
    rm $INSTALL_DIR/service_ips.txt
    touch $INSTALL_DIR/service_ips.txt
fi
echo "[INFO] Service IP Assignments:"

for dir in $(find $INSTALL_DIR -maxdepth 1 -type d \( ! -name "." ! -name ".git" \)); do
    cd $dir
    if [ -f docker-compose.yml ]; then
        service_name=$(basename "$dir")
        echo "[INFO] Processing service: $service_name"

        # Add network configuration
        add_network_config "docker-compose.yml" "$service_name" "$CURRENT_IP"

        # Store service name and IP for DNS update
        service_ips[$service_name]=$CURRENT_IP

        # Record the IP assignment
        echo "$service_name: $CURRENT_IP" >>$INSTALL_DIR/service_ips.txt

        # If this is the postgres service, store its IP for vault configuration
        if [ "$service_name" = "postgres" ]; then
            POSTGRES_IP=$CURRENT_IP
        fi

        CURRENT_IP=$(increment_ip $CURRENT_IP)
    fi
    cd $INSTALL_DIR
done

echo "[INFO] Updating DNS zone file..."
if [ -f "$ZONE_FILE" ]; then
    # Create backup of zone file
    cp "$ZONE_FILE" "${ZONE_FILE}.bak.$(date +%Y%m%d%H%M%S)"

    # Update each service in zone file
    for service in "${!service_ips[@]}"; do
        echo "[INFO] Adding/Updating DNS record for $service: ${service_ips[$service]}"
        update_zone_file "$service" "${service_ips[$service]}"
    done

    # Update serial number
    update_zone_serial

    echo "[INFO] Zone file updated successfully"
else
    echo "[ERROR] Zone file not found at $ZONE_FILE"
fi

# echo "[INFO] Starting Bind9 for local DNS..."
# if [ -d "$INSTALL_DIR/bind9" ]; then
#     cd "$INSTALL_DIR/bind9"
#     docker-compose up -d || echo "[WARN] Bind9 already running or error during startup."
#     chmod -R 770 config
#     chmod -R 770 cache
#     sudo chown -R 100:101 ./config
#     sudo chown -R 100:101 ./cache
#     cd $INSTALL_DIR
# else
#     echo "[ERROR] Bind9 directory does not exist in the project. Skipping Bind9 setup."
# fi

# Update vault.hcl if it exists
if [ -f "$INSTALL_DIR/vault/vault.hcl" ]; then
    echo "[INFO] Updating Vault configuration with PostgreSQL IP..."
    if [ ! -z "$POSTGRES_IP" ]; then
        # Create a backup of the original vault.hcl
        cp "$INSTALL_DIR/vault/vault.hcl" "$INSTALL_DIR/vault/vault.hcl.bak"

        # Update the connection URL in vault.hcl
        sed -i "s|connection_url = \"postgresql://.*\"|connection_url = \"postgresql://vault:vault@$POSTGRES_IP:5432/vault?sslmode=disable\"|g" "$INSTALL_DIR/vault/vault.hcl"
        echo "[INFO] Updated PostgreSQL connection in vault.hcl to use IP: $POSTGRES_IP"
        chmod 644 $INSTALL_DIR/vault/vault.hcl
    else
        echo "[WARN] PostgreSQL IP not found. Make sure the postgres service directory is named 'postgres'"
    fi
fi

echo "[INFO] Running Terraform to deploy the stack..."
if [ -d "$INSTALL_DIR/terraform" ]; then
    cd "$INSTALL_DIR/terraform"
    terraform init
    terraform apply -auto-approve
    cd $INSTALL_DIR
else
    echo "[ERROR] Terraform directory does not exist in the project. Skipping Terraform deployment."
fi

echo "[INFO] Starting all Docker Compose services..."
for dir in $(find $INSTALL_DIR -maxdepth 1 -type d \( ! -name "." ! -name ".git" ! -name "terraform" ! -name "bind9" \)); do
    cd $dir
    if [ -f docker-compose.yml ]; then
        echo "[INFO] Starting Docker Compose service in $dir..."
        docker-compose up -d || echo "[WARN] Error starting service in $dir."
    fi
    cd $INSTALL_DIR
done

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker exec postgres pg_isready -U postgres > /dev/null 2>&1; do
    sleep 2
done

echo "PostgreSQL is ready."

# Create the vault user and database
echo "Setting up Vault database and user..."
docker exec -i postgres psql -U postgres <<EOF
CREATE USER vault WITH PASSWORD 'vault';
CREATE DATABASE vault OWNER vault;
EOF

docker exec -i postgres psql -U vault -d vault <<EOF
CREATE TABLE vault_kv_store (
  parent_path TEXT COLLATE "C" NOT NULL,
  path        TEXT COLLATE "C",
  key         TEXT COLLATE "C",
  value       BYTEA,
  CONSTRAINT pkey PRIMARY KEY (path, key)
);

CREATE INDEX parent_path_idx ON vault_kv_store (parent_path);
GRANT ALL PRIVILEGES ON DATABASE vault TO vault;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vault;
EOF

echo "[INFO] Displaying all service IPs:"
cat $INSTALL_DIR/service_ips.txt
echo "[INFO] Setup completed successfully!"

echo "[FINISH] The system is rebooting..."

echo "[INFO] After everything works fine you can create teleport user with:"
# echo "docker exec -it teleport tctl users add -g admin -p password teleport"
echo "docker exec teleport tctl users add admin --roles=editor,access --logins=root,ubuntu"

echo "You can generate TSIG from bind for dns with:"
echo "docker exec bind9 tsig-keygen -a hmac-sha256"