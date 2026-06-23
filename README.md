# Linux Firewall and NFTables Troubleshooter

A Linux support toolkit for collecting firewall evidence and applying selected guarded firewalld or UFW repairs.

## Diagnostic script

```bash
chmod +x src/firewall_troubleshooter.sh
sudo ./src/firewall_troubleshooter.sh --target 192.0.2.10 --port 443
```

## Repair script

```bash
chmod +x src/firewall_repair.sh
sudo ./src/firewall_repair.sh --allow-port 443/tcp --dry-run
```

Examples:

```bash
sudo ./src/firewall_repair.sh --enable
sudo ./src/firewall_repair.sh --reload
sudo ./src/firewall_repair.sh --allow-port 443/tcp
sudo ./src/firewall_repair.sh --remove-port 443/tcp
sudo ./src/firewall_repair.sh --allow-service https --zone public
```

## What the repair does

- Detects firewalld or UFW.
- Enables and starts the detected firewall manager.
- Adds or removes one explicitly selected TCP or UDP port rule.
- Adds one selected firewalld service rule.
- Reloads the firewall manager after persistent rule changes.
- Captures rules and zone state before and after repair.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

Firewall changes can interrupt remote access and production traffic. Confirm an emergency console or alternate access path before changing rules. The tool does not flush the entire ruleset or change default policies automatically.

## Maintainer

IAmLegionVaal
