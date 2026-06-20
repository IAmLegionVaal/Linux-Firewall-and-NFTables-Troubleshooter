#!/usr/bin/env bash
set -u
TARGET=""
PORT=443
HOURS=24
OUTPUT_DIR=""
usage(){ echo "Usage: firewall_troubleshooter.sh [--target HOST] [--port N] [--hours N] [--output DIR]"; }
while [[ $# -gt 0 ]]; do case "$1" in --target) TARGET="${2:-}"; shift 2;; --port) PORT="${2:-443}"; shift 2;; --hours) HOURS="${2:-24}"; shift 2;; --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
[[ "$PORT" =~ ^[0-9]+$ && "$HOURS" =~ ^[0-9]+$ ]] || { echo "Port and hours must be numeric" >&2; exit 2; }
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./firewall-troubleshooting-$STAMP}"; mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/firewall-report.txt"; CSV="$OUTPUT_DIR/listeners.csv"; JSON="$OUTPUT_DIR/summary.json"; ERRORS="$OUTPUT_DIR/command-errors.log"; :>"$REPORT"; :>"$ERRORS"
echo 'protocol,local_address,process' > "$CSV"
section(){ t="$1"; shift; { printf '\n===== %s =====\n' "$t"; "$@"; } >>"$REPORT" 2>>"$ERRORS" || true; }
section "Metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; id'
section "Interfaces" ip -brief address
section "Routes" ip route show table all
section "Listening sockets" ss -lntup
section "Forwarding" bash -c 'sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null || true'
command -v nft >/dev/null 2>&1 && section "nftables ruleset" nft list ruleset
command -v iptables-save >/dev/null 2>&1 && section "iptables rules" iptables-save
command -v ip6tables-save >/dev/null 2>&1 && section "ip6tables rules" ip6tables-save
command -v firewall-cmd >/dev/null 2>&1 && section "firewalld" bash -c 'firewall-cmd --state; firewall-cmd --get-active-zones; firewall-cmd --list-all-zones'
command -v ufw >/dev/null 2>&1 && section "UFW" ufw status verbose
section "Recent firewall events" bash -c "journalctl --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'DROP|REJECT|DENIED|BLOCK|nft|iptables|firewalld|ufw' | tail -n 3000 || true"
ss -H -lntup 2>>"$ERRORS" | while read -r proto _ _ local _ process; do printf '"%s","%s","%s"\n' "$proto" "$local" "${process//"/""}" >> "$CSV"; done
TARGET_PING=false; TARGET_TCP=false
if [[ -n "$TARGET" ]]; then section "Target ping" ping -c 4 "$TARGET"; ping -c 1 -W 3 "$TARGET" >/dev/null 2>&1 && TARGET_PING=true; if command -v nc >/dev/null 2>&1; then section "Target TCP" nc -vz -w 5 "$TARGET" "$PORT"; nc -z -w 5 "$TARGET" "$PORT" >/dev/null 2>&1 && TARGET_TCP=true; fi; fi
LISTENERS=$(awk 'END{print NR-1}' "$CSV"); NFT=false; command -v nft >/dev/null 2>&1 && NFT=true; IPT=false; command -v iptables >/dev/null 2>&1 && IPT=true
cat > "$JSON" <<EOF
{"collected_at":"$(date -Is)","hostname":"$(hostname -f 2>/dev/null || hostname)","listeners":$LISTENERS,"nftables_available":$NFT,"iptables_available":$IPT,"target":"$TARGET","port":$PORT,"target_ping":$TARGET_PING,"target_tcp":$TARGET_TCP}
EOF
printf '\nFirewall diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
