# WireGuard and Ansible Setup Example

## Overview

This project demonstrates a complete WireGuard VPN setup using Ansible for
automated deployment on Multipass virtual machines. It includes a server-client
architecture with automated configuration management.

A standalone learning script (`basic_example.sh`) is also included so you can
understand exactly how WireGuard works on a **single machine** — no VMs required.

## Features

- Secure WireGuard VPN connections with server-client architecture
- Automated deployment with Ansible playbooks and roles
- Multipass-based virtual machine provisioning (Ubuntu)
- Easy SSH key management and inventory automation
- Configurable VM setup using Ansible roles (common, users, wireguard)
- Host-specific WireGuard configurations (server vs client)
- Standalone learning script to understand WireGuard locally — no VMs needed

## Prerequisites

- Multipass installed on your system
- Ansible 2.9+ installed
- Python 3 and pip installed
- Git installed

---

## Quick Start (Ansible / Multipass)

### 1. Provision Virtual Machines

```bash
make provision
```

Creates two Multipass VMs:
- `server-node` — WireGuard server (4 CPUs, 8 GB RAM, 20 GB disk)
- `client-node` — WireGuard client (4 CPUs, 8 GB RAM, 20 GB disk)

### 2. Copy SSH Keys

```bash
make copy-ssh-keys
```

Copies your local SSH public keys to both VMs for passwordless authentication.

### 3. Configure Base System

```bash
make configure
```

Applies base configuration including system updates, package installation, and
user setup.

### 4. Install WireGuard

```bash
make wireguard
```

Installs WireGuard on both nodes and generates cryptographic keys. The playbook
will display the public keys for each node.

### 5. Configure WireGuard Peers

After running the WireGuard playbook, copy the displayed public keys and update
the inventory file:

```bash
# Edit inventory/hosts.yml to add peer public keys and endpoints
```

Example configuration in `inventory/hosts.yml`:

```yaml
server-node:
  ansible_host: 10.134.198.86
  wg_role: server
  wg_address: 10.0.0.1/24
  # Add peer configuration in roles/wireguard/vars/main.yml

client-node:
  ansible_host: 10.134.198.246
  wg_role: client
  wg_address: 10.0.0.2/32
```

### 6. Re-run WireGuard Playbook

```bash
make wireguard
```

Applies the peer configurations and establishes the VPN connection.

## Available Make Targets

| Target | Description |
|--------|-------------|
| `make help` | Display available targets |
| `make provision` | Provision Multipass VMs |
| `make copy-ssh-keys` | Copy SSH keys to VMs |
| `make update-inventory` | Update inventory with VM IPs |
| `make configure` | Configure base system (users) |
| `make wireguard` | Install and configure WireGuard VPN |
| `make destroy` | Destroy all VMs and clean up |
| `make status` | Check VM status |

## Project Structure

```
.
├── inventory/
│   └── hosts.yml            # Ansible inventory with host variables
├── playbooks/
│   ├── configure.yml        # Base system configuration
│   └── wireguard.yml        # WireGuard installation and config
├── roles/
│   ├── users/               # User management
│   └── wireguard/           # WireGuard VPN role
│       ├── tasks/           # Installation and configuration tasks
│       ├── templates/       # WireGuard config templates
│       ├── vars/            # Default variables
│       └── handlers/        # Service handlers
├── scripts/
│   └── update-inventory.sh  # Script to update inventory with VM IPs
├── basic_example.sh         # Standalone learning script (no VMs needed)
└── Makefile                 # Automation targets
```

---

## Local Learning Example (`basic_example.sh`)

> **Reference:** https://www.wireguard.com/quickstart/

Before provisioning real VMs, use `basic_example.sh` to understand how WireGuard
works entirely on a **single machine**. It uses Linux network namespaces to
simulate two separate hosts (`ns-server` and `ns-client`) connected through a
real, encrypted WireGuard tunnel.

### What it demonstrates

| Step | WireGuard concept |
|------|-------------------|
| `wg genkey` → private key, `wg pubkey` → public key | Curve25519 asymmetric keypairs |
| `ip link add dev wg0 type wireguard` | Creating kernel WireGuard interfaces |
| `wg setconf` with `[Interface]` + `[Peer]` blocks | Config file format |
| `AllowedIPs`, `Endpoint`, `PersistentKeepalive` | Peer firewall & routing rules |
| Live `wg show` output + cross-namespace ping | Verifying the encrypted handshake |

### Topology

```
[ns-server]                              [ns-client]
wg0 → 10.0.0.1/24   ←── tunnel ──→    wg0 → 10.0.0.2/24
(listen udp/51820)                       (endpoint 169.254.0.1:51820)
        │                                        │
    veth-srv ←──── underlay link ────→ veth-cli
               (169.254.0.1 ↔ 169.254.0.2)
```

### Requirements

```bash
sudo apt install wireguard-tools iproute2   # Debian / Ubuntu
```

### Usage

```bash
# Bring the tunnel up — generates keys, creates namespaces, runs a ping test
sudo bash basic_example.sh

# Inspect live tunnel state while it's running
sudo ip netns exec ns-server wg show          # server peer info
sudo ip netns exec ns-client  wg show          # client peer info
sudo ip netns exec ns-client  ping 10.0.0.1   # ping through the tunnel

# Show wg status without re-running setup
sudo bash basic_example.sh status

# Tear everything down and print a cleanup summary
sudo bash basic_example.sh clean   # or: down
```

### How cleanup works

The script is designed to be safe and self-cleaning:

| Mechanism | Behaviour |
|-----------|-----------|
| **Idempotent `up`** | Always runs `cleanup_previous` first — re-running never fails due to leftover namespaces or key files |
| **`trap ERR`** | If any setup step fails mid-way, teardown fires automatically before exit — no orphaned namespaces or key material left behind |
| **`clean` / `down`** | Explicit teardown prints a bulleted summary of every resource removed (namespaces, key files) and warns gracefully if the environment was already empty |

---

## WireGuard Configuration (Ansible Role)

### Server Configuration

The server node:
- Listens on UDP port 51820
- Has VPN IP: 10.0.0.1/24
- Enables IP forwarding for routing
- Accepts connections from configured clients

### Client Configuration

The client node:
- Connects to server endpoint
- Has VPN IP: 10.0.0.2/32
- Routes traffic through the VPN tunnel

### Variables

Key WireGuard variables (in `roles/wireguard/vars/main.yml`):

| Variable | Description |
|----------|-------------|
| `wg_interface` | WireGuard interface name (default: `wg0`) |
| `wg_port` | UDP port for WireGuard (default: `51820`) |
| `wg_address` | VPN IP address for the host |
| `wg_role` | Either `server` or `client` |
| `wg_peers` | List of peer configurations (server only) |
| `wg_server_peer` | Server peer configuration (client only) |

## Verification

Check WireGuard status on the VMs:

```bash
# On server-node
multipass exec server-node -- sudo wg show

# On client-node
multipass exec client-node -- sudo wg show
```

Test connectivity:

```bash
# From client-node, ping server through VPN
multipass exec client-node -- ping 10.0.0.1
```

## Troubleshooting

### VM Connection Issues

```bash
# Check VM status
make status

# Update inventory if IPs changed
make update-inventory

# Re-copy SSH keys
make copy-ssh-keys
```

### WireGuard Issues

```bash
# Check WireGuard service status
multipass exec server-node -- sudo systemctl status wg-quick@wg0

# View WireGuard logs
multipass exec server-node -- sudo journalctl -u wg-quick@wg0 -f

# Check firewall
multipass exec server-node -- sudo ufw status
```

### Kernel Debug Output

Enable WireGuard dynamic debug (Linux kernel module only):

```bash
sudo modprobe wireguard && echo module wireguard +p > /sys/kernel/debug/dynamic_debug/control
```

## Cleanup

To destroy all Multipass VMs:

```bash
make destroy
```

To remove only the local learning tunnel:

```bash
sudo bash basic_example.sh clean
```

## License

MIT
