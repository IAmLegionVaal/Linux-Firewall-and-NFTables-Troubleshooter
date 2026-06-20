# Linux Firewall and NFTables Troubleshooter

A read-only Bash toolkit for collecting nftables, iptables, firewalld, UFW, listening-port, routing, and packet-filter evidence.

## Usage

```bash
chmod +x src/firewall_troubleshooter.sh
sudo ./src/firewall_troubleshooter.sh --target 192.0.2.10 --port 443
```

## Checks performed

- nftables and iptables rules and policies
- firewalld zones and UFW status
- Listening sockets and service ownership
- Routes, interfaces, and forwarding state
- Optional target ping and TCP reachability tests
- Recent firewall-drop and reject events
- Text, CSV, and JSON reports

## Safety

The script never adds, deletes, flushes, reloads, or changes firewall rules and services.

## Author

Dewald Pretorius — L2 IT Support Engineer
