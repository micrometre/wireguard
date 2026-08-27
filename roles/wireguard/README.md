# WireGuard Ansible Role

This Ansible role installs and configures WireGuard VPN on Ubuntu/Debian systems.

## Requirements

- Ansible 2.9+
- Ubuntu/Debian target system
- Root/sudo access on target hosts

## Role Variables

### Main Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `wg_interface` | `wg0` | WireGuard interface name |
| `wg_port` | `51820` | UDP port for WireGuard |
| `wg_address` | `10.0.0.1/24` | VPN IP address for this host |
| `wg_peers` | `[]` | List of peer configurations |

### Peer Configuration

Each peer in `wg_peers` supports:

| Variable | Description |
|----------|-------------|
| `name` | Peer identifier (for reference) |
| `public_key` | Peer's WireGuard public key |
| `allowed_ips` | IPs allowed from this peer (e.g., `10.0.0.2/32`) |
| `endpoint` | Peer's endpoint (optional, e.g., `203.0.113.5:51820`) |

### Example Configuration

```yaml
wg_interface: wg0
wg_port: 51820
wg_address: 10.0.0.1/24
wg_peers:
  - name: peer1
    public_key: "someBase64PublicKeyHere..."
    allowed_ips: 10.0.0.2/32
    endpoint: "203.0.113.5:51820"
  - name: peer2
    public_key: "anotherBase64PublicKeyHere..."
    allowed_ips: 10.0.0.3/32
```

## Dependencies

None

## Example Playbook

```yaml
---
- name: Install WireGuard
  hosts: vpn_servers
  become: true
  roles:
    - wireguard
```

## Tasks

This role performs the following:

1. Updates apt cache
2. Installs WireGuard packages (`wireguard`, `wireguard-tools`, `qrencode`)
3. Enables IP forwarding (`net.ipv4.ip_forward`)
4. Creates `/etc/wireguard` directory
5. Generates WireGuard private/public key pair
6. Saves keys to `/etc/wireguard/privatekey` and `/etc/wireguard/publickey`
7. Deploys WireGuard configuration from template
8. Starts and enables `wg-quick@wg0` service

## Key Management

The role automatically generates:
- **Private key**: `/etc/wireguard/privatekey` (mode 0600)
- **Public key**: `/etc/wireguard/publickey` (mode 0644)

To retrieve the public key for peer configuration:

```bash
ansible vpn_servers -m shell -a "cat /etc/wireguard/publickey"
```

## Usage

### Basic Installation

```bash
ansible-playbook playbooks/wireguard.yml
```

### With Custom Variables

```bash
ansible-playbook playbooks/wireguard.yml -e "wg_address=10.10.0.1/24"
```

### Check WireGuard Status

```bash
ansible vpn_servers -m shell -a "wg show"
```

### Restart WireGuard Service

```bash
ansible vpn_servers -m systemd -a "name=wg-quick@wg0 state=restarted" --become
```

## Firewall Configuration

Ensure UDP port 51820 is open on your firewall:

```bash
sudo ufw allow 51820/udp
```

Or with Ansible:

```yaml
- name: Allow WireGuard port
  ufw:
    rule: allow
    port: "{{ wg_port }}"
    proto: udp
```

## License

MIT

## Author

Created for WireGuard and Ansible setup example
