#!/usr/bin/env bash
# =============================================================================
# WireGuard Basic Example — Understanding How WireGuard Works
# Reference: https://www.wireguard.com/quickstart/
#
# This script creates a minimal two-peer WireGuard tunnel entirely on one
# machine, using Linux network namespaces so we don't need real separate hosts.
#
#   Topology:
#
#     [ns-server]                       [ns-client]
#     wg0 → 10.0.0.1/24    ←tunnel→    wg0 → 10.0.0.2/24
#     (listen on udp/51820)             (endpoint: 127.0.0.1:51820)
#
#   After setup you'll be able to:
#     • ping the server from the client namespace
#     • run `wg show` to inspect tunnel state
#     • see how keys, allowed-ips, and endpoints wire together
#
# Requirements:
#   sudo, ip, wg (wireguard-tools), ping
#
# Usage:
#   sudo bash basic_example.sh [up|down|clean|status]
#
# =============================================================================

set -euo pipefail

# ---------- tuneable config ---------------------------------------------------
WG_PORT=51820
SERVER_WG_IP="10.0.0.1/24"
CLIENT_WG_IP="10.0.0.2/24"
SERVER_NS="ns-server"
CLIENT_NS="ns-client"
VETH_SERVER="veth-srv"   # veth pair that gives the two namespaces L3 reachability
VETH_CLIENT="veth-cli"
VETH_SRV_IP="169.254.0.1/30"   # link-local underlay between the two namespaces
VETH_CLI_IP="169.254.0.2/30"
KEY_DIR="/tmp/wg-demo-keys"

# ---------- helpers -----------------------------------------------------------
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)."
}

check_deps() {
    local missing=()
    for cmd in ip wg ping; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing tools: ${missing[*]}. Install wireguard-tools and iproute2."
    fi
}

# =============================================================================
# STEP 1 — Key Generation
# =============================================================================
# WireGuard uses Curve25519 for key exchange.  Each peer has:
#   • a private key (keep secret!)
#   • a public key  (share with peers)
#
# wg genkey  → produces a random 32-byte private key, base64-encoded
# wg pubkey  → derives the corresponding public key
# =============================================================================
generate_keys() {
    log "Generating keypairs for server and client ..."
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    # Server
    wg genkey | tee "$KEY_DIR/server.key" | wg pubkey > "$KEY_DIR/server.pub"
    chmod 600 "$KEY_DIR/server.key"

    # Client
    wg genkey | tee "$KEY_DIR/client.key" | wg pubkey > "$KEY_DIR/client.pub"
    chmod 600 "$KEY_DIR/client.key"

    SERVER_PRIV=$(cat "$KEY_DIR/server.key")
    SERVER_PUB=$(cat "$KEY_DIR/server.pub")
    CLIENT_PRIV=$(cat "$KEY_DIR/client.key")
    CLIENT_PUB=$(cat "$KEY_DIR/client.pub")

    ok "Server private key : $SERVER_PRIV"
    ok "Server public  key : $SERVER_PUB"
    ok "Client private key : $CLIENT_PRIV"
    ok "Client public  key : $CLIENT_PUB"
}

# =============================================================================
# STEP 2 — Network Namespaces & Underlay
# =============================================================================
# We simulate two separate machines with Linux network namespaces.
# A veth (virtual ethernet) pair connects them at Layer 3 so the WireGuard
# UDP packets have a path to travel (this is the "internet" in our demo).
# =============================================================================
setup_namespaces() {
    log "Creating network namespaces: $SERVER_NS, $CLIENT_NS ..."
    ip netns add "$SERVER_NS"
    ip netns add "$CLIENT_NS"

    log "Creating veth pair for underlay connectivity ..."
    ip link add "$VETH_SERVER" type veth peer name "$VETH_CLIENT"
    ip link set "$VETH_SERVER" netns "$SERVER_NS"
    ip link set "$VETH_CLIENT" netns "$CLIENT_NS"

    ip netns exec "$SERVER_NS" ip addr add "$VETH_SRV_IP" dev "$VETH_SERVER"
    ip netns exec "$SERVER_NS" ip link set "$VETH_SERVER" up
    ip netns exec "$SERVER_NS" ip link set lo up

    ip netns exec "$CLIENT_NS" ip addr add "$VETH_CLI_IP" dev "$VETH_CLIENT"
    ip netns exec "$CLIENT_NS" ip link set "$VETH_CLIENT" up
    ip netns exec "$CLIENT_NS" ip link set lo up

    ok "Underlay ready — server underlay IP: ${VETH_SRV_IP%/*}, client: ${VETH_CLI_IP%/*}"
}

# =============================================================================
# STEP 3 — Create WireGuard Interfaces
# =============================================================================
# `ip link add dev wg0 type wireguard` creates a new WireGuard network
# interface inside the specified namespace.
# =============================================================================
create_interfaces() {
    log "Creating WireGuard interface wg0 in each namespace ..."
    ip netns exec "$SERVER_NS" ip link add dev wg0 type wireguard
    ip netns exec "$CLIENT_NS"  ip link add dev wg0 type wireguard
    ok "WireGuard interfaces created."
}

# =============================================================================
# STEP 4 — Write wg-quick style config files (used with `wg setconf`)
# =============================================================================
# The [Interface] section describes this peer itself.
# The [Peer] section describes the remote peer:
#   • PublicKey    — the remote peer's public key
#   • AllowedIPs   — which source IPs are accepted from (and routed to) this peer
#   • Endpoint     — where to send outgoing packets (IP:port of remote host)
# =============================================================================
write_configs() {
    log "Writing WireGuard config files ..."

    # Server config — listens on UDP/51820, no Endpoint needed (clients connect to us)
    cat > "$KEY_DIR/server.conf" <<EOF
[Interface]
PrivateKey = $SERVER_PRIV
ListenPort = $WG_PORT

[Peer]
PublicKey = $CLIENT_PUB
# AllowedIPs is the WireGuard firewall: only packets whose source IP matches
# this list are accepted from this peer, and packets to these IPs are sent to
# this peer.  10.0.0.2/32 means only the client's tunnel IP.
AllowedIPs = 10.0.0.2/32
EOF

    # Client config — connects out to the server's underlay IP
    cat > "$KEY_DIR/client.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV

[Peer]
PublicKey = $SERVER_PUB
# Endpoint tells WireGuard where to send encrypted UDP packets.
# We use the server's veth underlay address since both namespaces live on the
# same host.  In a real setup this would be the server's public IP.
Endpoint = ${VETH_SRV_IP%/*}:$WG_PORT
AllowedIPs = 10.0.0.1/32

# PersistentKeepalive — send a keepalive every 25 s so NAT/firewall state
# stays open.  Useful for clients behind NAT; 0 = disabled (default).
PersistentKeepalive = 25
EOF

    ok "Config files written to $KEY_DIR/"
}

# =============================================================================
# STEP 5 — Apply Configuration & Assign Tunnel IPs
# =============================================================================
apply_config() {
    log "Applying WireGuard configuration ..."

    # Load config (sets private key, listen port, and peers)
    ip netns exec "$SERVER_NS" wg setconf wg0 "$KEY_DIR/server.conf"
    ip netns exec "$CLIENT_NS"  wg setconf wg0 "$KEY_DIR/client.conf"

    # Assign tunnel (overlay) IP addresses to the wg0 interfaces
    ip netns exec "$SERVER_NS" ip address add dev wg0 "$SERVER_WG_IP"
    ip netns exec "$CLIENT_NS"  ip address add dev wg0 "$CLIENT_WG_IP"

    # Bring the interfaces up
    ip netns exec "$SERVER_NS" ip link set up dev wg0
    ip netns exec "$CLIENT_NS"  ip link set up dev wg0

    ok "Tunnel is up."
}

# =============================================================================
# STEP 6 — Verify & Demo
# =============================================================================
show_status() {
    echo ""
    echo "======================================================================"
    echo "  WireGuard Interface Status"
    echo "======================================================================"
    echo ""
    echo "--- SERVER (ns-server) -----------------------------------------------"
    ip netns exec "$SERVER_NS" wg show
    echo ""
    echo "--- CLIENT (ns-client) -----------------------------------------------"
    ip netns exec "$CLIENT_NS" wg show
    echo ""
}

run_ping_test() {
    log "Pinging server tunnel IP (10.0.0.1) from client namespace ..."
    if ip netns exec "$CLIENT_NS" ping -c 3 -W 2 10.0.0.1; then
        ok "Ping succeeded!  The WireGuard tunnel is working."
    else
        warn "Ping failed.  Check 'wg show' output above for handshake status."
    fi
}

# =============================================================================
# cleanup_previous — silently remove any leftovers from a prior run
# =============================================================================
# Called automatically at the start of 'up' so the script is idempotent:
# running it twice in a row always succeeds cleanly.
# =============================================================================
cleanup_previous() {
    local found=0
    if ip netns list 2>/dev/null | grep -q "^$SERVER_NS"; then
        ip netns del "$SERVER_NS" 2>/dev/null && found=1 || true
    fi
    if ip netns list 2>/dev/null | grep -q "^$CLIENT_NS"; then
        ip netns del "$CLIENT_NS" 2>/dev/null && found=1 || true
    fi
    if [[ -d "$KEY_DIR" ]]; then
        rm -rf "$KEY_DIR" && found=1
    fi
    [[ $found -eq 1 ]] && warn "Removed stale state from a previous run."
    return 0
}

# =============================================================================
# teardown — remove everything we created and print a summary
# =============================================================================
teardown() {
    log "Tearing down WireGuard demo ..."
    local removed=()

    # Delete namespaces (this also destroys the wg0 interfaces and the veth
    # pair inside them — Linux cleans up interfaces when their namespace is gone)
    if ip netns list 2>/dev/null | grep -q "^$SERVER_NS"; then
        ip netns del "$SERVER_NS" 2>/dev/null && removed+=("namespace:$SERVER_NS") || true
    else
        warn "Namespace $SERVER_NS was not present (already clean)."
    fi
    if ip netns list 2>/dev/null | grep -q "^$CLIENT_NS"; then
        ip netns del "$CLIENT_NS"  2>/dev/null && removed+=("namespace:$CLIENT_NS")  || true
    else
        warn "Namespace $CLIENT_NS was not present (already clean)."
    fi

    # Remove key material
    if [[ -d "$KEY_DIR" ]]; then
        local key_count
        key_count=$(find "$KEY_DIR" -type f | wc -l)
        rm -rf "$KEY_DIR"
        removed+=("$key_count key file(s) in $KEY_DIR")
    else
        warn "Key directory $KEY_DIR was not present (already clean)."
    fi

    # Summary
    if [[ ${#removed[@]} -eq 0 ]]; then
        warn "Nothing to clean — environment was already empty."
    else
        ok "Removed:"
        for item in "${removed[@]}"; do
            echo "        • $item"
        done
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    local action="${1:-up}"

    require_root
    check_deps

    case "$action" in
        up)
            log "=== WireGuard Basic Example — Bringing tunnel UP ==="

            # Always start from a clean slate so the script is idempotent.
            cleanup_previous

            # Register an automatic cleanup handler: if any command in the
            # pipeline fails (set -e), ERR fires and teardown runs before exit,
            # ensuring we never leave orphaned namespaces or key material behind.
            trap 'echo ""; warn "Setup failed — running automatic cleanup ..."; teardown' ERR

            generate_keys
            setup_namespaces
            create_interfaces
            write_configs
            apply_config
            show_status
            run_ping_test

            # Setup succeeded — disarm the error trap
            trap - ERR

            echo ""
            echo "Tunnel is running.  Useful commands while it's up:"
            echo "  sudo ip netns exec $SERVER_NS wg show          # inspect server peer"
            echo "  sudo ip netns exec $CLIENT_NS  wg show          # inspect client peer"
            echo "  sudo ip netns exec $CLIENT_NS  ping 10.0.0.1   # tunnel ping"
            echo "  sudo bash $0 status    ← show live wg state"
            echo "  sudo bash $0 clean     ← remove everything"
            ;;
        down|clean)
            teardown
            ;;
        status)
            show_status
            ;;
        *)
            die "Unknown action '$action'.  Usage: sudo bash $0 [up|down|clean|status]"
            ;;
    esac
}

main "$@"
