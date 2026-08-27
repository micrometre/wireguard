#!/bin/bash
# Update Ansible inventory with Multipass VM IP

set -e

# Change this to match the name you used in the 'multipass launch' command
VM_NAME=server-node
VM2_NAME=client-node
INVENTORY_FILE="inventory/hosts.yml"

echo "Fetching IPs for Multipass instances..."

# Get VM IP addresses
# This uses grep and awk to extract the IPv4 address specifically
VM_IP=$(multipass info "$VM_NAME" | grep IPv4 | awk '{print $2}')
VM2_IP=$(multipass info "$VM2_NAME" | grep IPv4 | awk '{print $2}')

if [ -z "$VM_IP" ]; then
  echo "❌ Error: Could not retrieve IP for '$VM_NAME'"
  echo "Make sure the VM is running (check with 'multipass list')"
  exit 1
fi

if [ -z "$VM2_IP" ]; then
  echo "❌ Error: Could not retrieve IP for '$VM2_NAME'"
  echo "Make sure the VM is running (check with 'multipass list')"
  exit 1
fi

echo "✅ $VM_NAME IP: $VM_IP"
echo "✅ $VM2_NAME IP: $VM2_IP"

# Ensure the inventory directory exists
mkdir -p $(dirname "$INVENTORY_FILE")

# Update inventory file
cat > "$INVENTORY_FILE" <<EOL
all:
  children:
    multipass_vms:
      hosts:
        $VM_NAME:
          ansible_host: $VM_IP
          ansible_user: ubuntu
          # Multipass uses your default SSH key if you injected it, 
          # otherwise, it uses its own internal key.
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_python_interpreter: /usr/bin/python3
        $VM2_NAME:
          ansible_host: $VM2_IP
          ansible_user: ubuntu
          # Multipass uses your default SSH key if you injected it, 
          # otherwise, it uses its own internal key.
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_python_interpreter: /usr/bin/python3
EOL

echo "✅ Inventory updated: $INVENTORY_FILE"
echo ""
echo "You can now run:"
echo "  ansible all -m ping -i $INVENTORY_FILE"