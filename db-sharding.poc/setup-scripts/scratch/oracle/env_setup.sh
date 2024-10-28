#!/bin/bash

# Variables
NETWORK_NAME="shard_pub1_nw"
NETWORK_SUBNET="10.0.20.0/24"
NETWORK_GATEWAY="10.0.20.1"
HOST_FILE="/opt/containers/shard_host_file"
SECRETS_DIR="/opt/.secrets"
PASSWORD_FILE="$SECRETS_DIR/pwdfile.txt"
ENC_PASSWORD_FILE="$SECRETS_DIR/pwdfile.enc"
KEY_FILE="$SECRETS_DIR/key.pem"
PUB_KEY_FILE="$SECRETS_DIR/key.pub"

# 1. Create Docker Network
# Created

# 2. Setup Hostfile
echo "Setting up hostfile for name resolution..."
mkdir -p /opt/containers
rm -f $HOST_FILE && touch $HOST_FILE
cat << EOF > $HOST_FILE
127.0.0.1       localhost.localdomain           localhost
10.0.20.100     oshard-gsm1.example.com         oshard-gsm1
10.0.20.101     oshard-gsm2.example.com         oshard-gsm2
10.0.20.102     oshard-catalog-0.example.com    oshard-catalog-0
10.0.20.103     oshard1-0.example.com           oshard1-0
10.0.20.104     oshard2-0.example.com           oshard2-0
10.0.20.105     oshard3-0.example.com           oshard3-0
10.0.20.106     oshard4-0.example.com           oshard4-0
EOF
echo "Hostfile setup completed at $HOST_FILE."

# 3. Generate Password Secrets
echo "Setting up encrypted secrets for password management..."
mkdir -p $SECRETS_DIR
chown 54321:54321 $SECRETS_DIR

# Generate RSA key pair
openssl genrsa -out $KEY_FILE
openssl rsa -in $KEY_FILE -out $PUB_KEY_FILE -pubout

# Create a password file (edit this manually later with a secure password)
# password: oracle
echo "Enter a secure password for database users and save to $PASSWORD_FILE ..."
touch $PASSWORD_FILE
vi $PASSWORD_FILE

# Encrypt the password
openssl pkeyutl -in $PASSWORD_FILE -out $ENC_PASSWORD_FILE -pubin -inkey $PUB_KEY_FILE -encrypt
if [ $? -ne 0 ]; then
  echo "Failed to encrypt password."
  exit 1
fi
echo "Password encrypted successfully."

# Cleanup plain password file
rm -f $PASSWORD_FILE

# Set permissions for the encrypted password and keys
chown 54321:54321 $ENC_PASSWORD_FILE $KEY_FILE $PUB_KEY_FILE
chmod 400 $ENC_PASSWORD_FILE $KEY_FILE $PUB_KEY_FILE

echo "Encrypted secrets setup completed."

# Summary of setup
echo "Setup completed successfully. Review the following details:"
echo "Docker Network: $NETWORK_NAME"
echo "Hostfile: $HOST_FILE"
echo "Secrets Directory: $SECRETS_DIR"
echo "Encrypted Password File: $ENC_PASSWORD_FILE"
