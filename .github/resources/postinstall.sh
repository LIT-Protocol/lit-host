#!/bin/bash

# Set Timezone (NOTE: Leaseweb API _should_ be setting this, but it doesn't)
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone

# Update and install dependencies
apt-get update && apt-get install -y curl

# Create a ci user (main SSH user)
adduser --disabled-password --gecos "" ci

# Copy authorized SSH key from root to ci
mkdir -p /home/ci/.ssh
cp /root/.ssh/authorized_keys /home/ci/.ssh/authorized_keys
chown -R ci:ci /home/ci/.ssh
chmod 700 /home/ci/.ssh
chmod 600 /home/ci/.ssh/authorized_keys
systemctl reload ssh
# Allow ci user to sudo without password
echo "ci ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/ci
chmod 0440 /etc/sudoers.d/ci
