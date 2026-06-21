#!/usr/bin/env bash
set -u

ENABLE=false
RELOAD=false
ALLOW_PORT=""
ALLOW_SERVICE=""
ZONE=""
REMOVE_PORT=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage(){ cat <<'EOF'
Usage: firewall_repair.sh [options]

  --enable                 Enable the detected UFW or firewalld service.
  --reload                 Reload the detected firewall manager.
  --allow-port PORT/PROTO  Add one permanent TCP or UDP port rule.
  --remove-port PORT/PROTO Remove one managed port rule.
  --allow-service NAME     Add one firewalld service rule.
  --zone ZONE              Select a firewalld zone for rule changes.
  --dry-run                Show commands without changing firewall state.
  --yes                    Skip confirmation prompts.
  --output DIR             Save logs, backups and verification output in DIR.
EOF
}
while [ "$#" -gt 0 ]; do case "$1" in
  --enable) ENABLE=true; shift;; --reload) RELOAD=true; shift;;
  --allow-port) ALLOW_PORT="${2:-}"; shift 2;; --remove-port) REMOVE_PORT="${2:-}"; shift 2;;
  --allow-service) ALLOW_SERVICE="${2:-}"; shift 2;; --zone) ZONE="${2:-}"; shift 2;;
  --dry-run) DRY_RUN=true; shift;; --yes) ASSUME_YES=true; shift;;
  --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;; esac; done
if ! $ENABLE && ! $RELOAD && [ -z "$ALLOW_PORT" ] && [ -z "$REMOVE_PORT" ] && [ -z "$ALLOW_SERVICE" ]; then echo "Choose at least one repair action." >&2; exit 2; fi
validate_port(){ case "$1" in *'/tcp'|*'/udp') p=${1%/*}; case "$p" in ''|*[!0-9]*) return 1;; esac; [ "$p" -ge 1 ] && [ "$p" -le 65535 ];; *) return 1;; esac; }
[ -z "$ALLOW_PORT" ] || validate_port "$ALLOW_PORT" || { echo "Invalid port specification." >&2; exit 2; }
[ -z "$REMOVE_PORT" ] || validate_port "$REMOVE_PORT" || { echo "Invalid port specification." >&2; exit 2; }
MANAGER=none; command -v firewall-cmd >/dev/null 2>&1 && MANAGER=firewalld; [ "$MANAGER" != none ] || { command -v ufw >/dev/null 2>&1 && MANAGER=ufw; }; [ "$MANAGER" != none ] || { echo "Supported firewall manager not found." >&2; exit 3; }
if [ "$MANAGER" = ufw ] && { [ -n "$ALLOW_SERVICE" ] || [ -n "$ZONE" ]; }; then echo "Service and zone options require firewalld." >&2; exit 2; fi
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./firewall-repair-$STAMP}"; BACKUP_DIR="$OUTPUT_DIR/backup"; mkdir -p "$BACKUP_DIR"; LOG="$OUTPUT_DIR/repair.log"; BEFORE="$OUTPUT_DIR/before.txt"; AFTER="$OUTPUT_DIR/after.txt"; : >"$LOG"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
confirm(){ $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
run(){ local d="$1"; shift; ACTIONS=$((ACTIONS+1)); log "$d"; if $DRY_RUN; then printf 'DRY-RUN:' >>"$LOG"; printf ' %q' "$@" >>"$LOG"; printf '\n' >>"$LOG"; return 0; fi; if "$@" >>"$LOG" 2>&1; then log "SUCCESS: $d"; else FAILURES=$((FAILURES+1)); log "WARNING: $d failed"; return 1; fi; }
root(){ local d="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run "$d" "$@"; else run "$d" sudo "$@"; fi; }
collect(){ local f="$1"; { echo "Collected: $(date -Is)"; echo "Manager: $MANAGER"; if [ "$MANAGER" = firewalld ]; then firewall-cmd --state 2>&1 || true; firewall-cmd --get-active-zones 2>&1 || true; firewall-cmd --list-all --zone="${ZONE:-$(firewall-cmd --get-default-zone 2>/dev/null)}" 2>&1 || true; else ufw status verbose 2>&1 || true; fi; echo; nft list ruleset 2>&1 || true; } >"$f"; }
collect "$BEFORE"; if [ "$MANAGER" = firewalld ]; then firewall-cmd --runtime-to-permanent >/dev/null 2>&1 || true; firewall-cmd --list-all-zones >"$BACKUP_DIR/firewalld-zones.txt" 2>&1 || true; else ufw status numbered >"$BACKUP_DIR/ufw-rules.txt" 2>&1 || true; fi
confirm "Apply the selected firewall changes? Confirm remote access paths first." || { log "Repair cancelled."; exit 10; }
if [ "$MANAGER" = firewalld ]; then
  ZONE="${ZONE:-$(firewall-cmd --get-default-zone 2>/dev/null)}"
  $ENABLE && root "Enabling firewalld" systemctl enable --now firewalld || true
  [ -z "$ALLOW_PORT" ] || root "Allowing $ALLOW_PORT in zone $ZONE" firewall-cmd --permanent --zone="$ZONE" --add-port="$ALLOW_PORT" || true
  [ -z "$REMOVE_PORT" ] || root "Removing $REMOVE_PORT from zone $ZONE" firewall-cmd --permanent --zone="$ZONE" --remove-port="$REMOVE_PORT" || true
  [ -z "$ALLOW_SERVICE" ] || root "Allowing service $ALLOW_SERVICE in zone $ZONE" firewall-cmd --permanent --zone="$ZONE" --add-service="$ALLOW_SERVICE" || true
  if $RELOAD || [ -n "$ALLOW_PORT" ] || [ -n "$REMOVE_PORT" ] || [ -n "$ALLOW_SERVICE" ]; then root "Reloading firewalld" firewall-cmd --reload || true; fi
else
  $ENABLE && root "Enabling UFW" ufw --force enable || true
  [ -z "$ALLOW_PORT" ] || root "Allowing $ALLOW_PORT through UFW" ufw allow "$ALLOW_PORT" || true
  [ -z "$REMOVE_PORT" ] || root "Removing UFW allow rule for $REMOVE_PORT" ufw --force delete allow "$REMOVE_PORT" || true
  $RELOAD && root "Reloading UFW" ufw reload || true
fi
$DRY_RUN || sleep 2; collect "$AFTER"; [ "$FAILURES" -eq 0 ] || exit 20; log "Firewall repair completed successfully. Actions performed: $ACTIONS"
