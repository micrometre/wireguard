.PHONY: help provision update-inventory configure destroy copy-ssh-keys wireguard wg-status

help:
	@echo "FastAPI ANPR - Ansible Infrastructure Management"
	@echo ""
	@echo "Available targets:"
	@echo "  install          - Install Ansible and Python dependencies"
	@echo "  provision        - Provision Multipass VM"
	@echo "  copy-ssh-keys    - Copy SSH keys to VM"
	@echo "  update-inventory - Update inventory with VM IP from Azure"
	@echo "  configure        - Configure VM (install base packages, setup)"
	@echo "  wireguard        - Install and configure WireGuard VPN"
	@echo "  wg-status        - Show live WireGuard status on all nodes"
	@echo "  destroy          - Destroy all Azure resources"
	@echo "  status           - Check status/list VMs"
	@echo "  clean            - Clean temporary files"

VM_NAME=server-node
VM2_NAME=client-node


vm-status:
	@echo "Display Multipass vms Status:"
	multipass list

provision:
	@echo "Provisioning Multipass VM..."
	multipass launch noble --name $(VM_NAME) --cpus 4 --memory 8G --disk 20G
	multipass launch noble --name $(VM2_NAME) --cpus 4 --memory 8G --disk 20G
	@echo "Updating inventory with VM IP..."
	@scripts/update-inventory.sh
	@echo ""
	@echo "✅ VM provisioned and inventory updated!"

update-inventory:
	@echo "Updating inventory with VM IP from Azure..."
	@scripts/update-inventory.sh

copy-ssh-keys:
	@echo "Copying SSH keys to VM..."
	cat ~/.ssh/*.pub | multipass exec $(VM_NAME) -- tee -a .ssh/authorized_keys
	cat ~/.ssh/*.pub | multipass exec $(VM2_NAME) -- tee -a .ssh/authorized_keys


configure:
	@echo "Configuring VM..."
	ansible-playbook playbooks/configure.yml
	@echo ""
	@echo "✅ Configured!"

wireguard:
	@echo "Installing and configuring WireGuard..."
	ansible-playbook playbooks/wireguard.yml
	@echo ""
	@echo "✅ WireGuard configured!"

wg-status:
	@echo "WireGuard status across all nodes:"
	ansible multipass_vms -m shell \
	  -a 'echo "=== $$(hostname) ==="; systemctl is-active wg-quick@wg0 && wg show || echo "[wg0 not running]"' \
	  --become




destroy:
	@echo "Cleaning temporary files..."
	rm -f *.retry vm_ip.txt
	rm -rf /tmp/ansible_facts
	@echo "Cleaning up virtual machine..."
	multipass delete $(VM_NAME) || true
	multipass delete $(VM2_NAME) || true
	multipass purge || true	
	@echo "✅ Clean complete!"
