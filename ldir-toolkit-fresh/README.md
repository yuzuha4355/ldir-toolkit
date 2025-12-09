# LDIR-Toolkit

Linux forensic data collection tool for incident response.

[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](https://github.com/yuzuha4355/ldir-toolkit/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)]()

---

## Overview

LDIR-Toolkit collects system artifacts from Linux hosts for forensic analysis. Supports 20+ distributions including Ubuntu, Debian, RHEL-based systems, Arch, Alpine, and embedded/cloud environments. Runs offline, requires root, takes 2-5 minutes, outputs ~10GB.

**Use case**: Incident response, security audits, compliance checks.

---

## Features

- Multi-distribution support (Ubuntu, Debian, Rocky, AlmaLinux, CentOS, Fedora, Amazon Linux, Arch, openSUSE, Gentoo, Alpine, Raspberry Pi OS, Oracle Linux)
- 10 collection modules: system info, logs, auth (sudoers/SSH/PAM), persistence (cron/systemd), execution history, network, filesystem, web artifacts, custom environment detection, cloud metadata (AWS/GCP/Azure IMDSv2)
- Auto-detection: package managers (apt/yum/dnf/pacman/zypper/apk), init systems (systemd/OpenRC/runit/s6), security frameworks (SELinux/AppArmor)
- Evidence integrity: SHA256 hashing, manifest generation, execution logging
- Offline-capable, no network required
- 26KB package size

---

## Quick Start

### Installation

```bash
wget https://github.com/yuzuha4355/ldir-toolkit/releases/download/v0.2.0/ldir-toolkit-extended-v0.2.0.tar.gz
tar -xzf ldir-toolkit-extended-v0.2.0.tar.gz
cd ldir-toolkit-v0.2.0
```

### Usage

```bash
# Collect data (requires root)
sudo ./ldir-collect.sh /tmp/ldir_output

# Archive results
tar -czf ldir_result_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz /tmp/ldir_output/
```

### Verification

```bash
sha256sum -c ldir-toolkit-extended-v0.2.0.tar.gz.sha256
```

---

## Supported Distributions

**Standard**: Ubuntu 20.04+, Debian 11+, Rocky Linux 8/9, AlmaLinux 8/9, CentOS 7/Stream 8/9, Fedora 38+, Amazon Linux 2/2023

**Special Purpose**: Arch Linux, openSUSE Leap/Tumbleweed, Gentoo, Alpine

**Embedded/IoT**: Raspberry Pi OS, Armbian

**Cloud**: Oracle Linux, Google Cloud Optimized OS, AWS EC2 Optimized

**Custom**: systemd-less (OpenRC/runit/s6), busybox-based, SELinux/AppArmor-hardened

---

## Collection Modules

| Module | Artifacts |
|--------|-----------|
| system_info | uname, hostname, users, groups |
| logs | syslog, auth.log, journal |
| auth | sudoers, SSH config, PAM |
| persistence | cron, systemd units, init scripts |
| execution | bash_history, process list |
| network | connections, routing, firewall |
| filesystem | mounts, recently modified files |
| web | browser history, cookies |
| custom_environment | init system, package manager detection |
| cloud_metadata | AWS/GCP/Azure metadata (IMDSv2) |

---

## Output Structure

```
/tmp/ldir_output/[hostname]_[timestamp]/
├── system_info/
├── logs/
├── auth/
├── persistence/
├── execution/
├── network/
├── filesystem/
├── web/
├── custom_environment/
├── cloud_metadata/
├── metadata/
│   ├── manifest.txt       # File list with timestamps
│   └── file_hashes.txt    # SHA256 hashes
└── execution.log          # Tool execution log
```

---

## What's New (v0.2.0)

- Extended distribution support (20+)
- Custom environment detection module
- Cloud metadata collection (AWS IMDSv2, GCP, Azure)
- Advanced distro detection logic (multi-method fallback)
- systemd-less environment support

---

## Requirements

- OS: Linux (see supported distributions)
- Permissions: root or sudo
- Storage: ~10GB free space
- Execution time: 2-5 minutes
- Network: not required

---

## Usage Scenarios

### Direct execution on target server
```bash
tar -xzf ldir-toolkit-extended-v0.2.0.tar.gz
cd ldir-toolkit-v0.2.0
sudo ./ldir-collect.sh /tmp/ldir_output
tar -czf ldir_result_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz /tmp/ldir_output/
```

### Transfer via WinSCP (Windows → Linux)
1. Download toolkit on Windows
2. Transfer to Linux server via WinSCP
3. SSH into server, execute collection
4. Download results via WinSCP

### Live USB
1. Boot target system with Live USB
2. Mount evidence drive
3. Execute: `sudo ./ldir-collect.sh /mnt/evidence/ldir_output`
4. Unmount, preserve chain of custody

---

## Evidence Integrity

Tool generates three integrity files:
- `manifest.txt`: file list with timestamps
- `file_hashes.txt`: SHA256 for all collected files
- `execution.log`: tool execution log

Verification:
```bash
cat /tmp/ldir_output/*/metadata/manifest.txt
sha256sum -c /tmp/ldir_output/*/metadata/file_hashes.txt
cat /tmp/ldir_output/*/execution.log
```

---

## Testing

Docker test environment available:

```bash
git clone https://github.com/yuzuha4355/ldir-toolkit.git
cd ldir-toolkit/docker-test

# Test single environment
./test-single.sh ubuntu

# Test all 11 environments
docker-compose -f docker-compose-extended.yml build
./test-all-extended.sh
./generate_report.sh
```

---

## Documentation

- [README_EXTENDED.txt](docs/README_EXTENDED.txt)
- [DISTRIBUTION_GUIDE.txt](docs/DISTRIBUTION_GUIDE.txt)
- [QUICKSTART.md](docs/QUICKSTART.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CHANGELOG.md](CHANGELOG.md)

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
git clone https://github.com/yuzuha4355/ldir-toolkit.git
cd ldir-toolkit
```

---

## Troubleshooting

**Permission denied**  
Run with sudo: `sudo ./ldir-collect.sh /output`

**Modules skipped**  
Normal behavior. Non-existent paths are skipped automatically.

**Execution takes >10 minutes**  
Expected on large systems.

**Command not found**  
Set execute permissions: `chmod +x ldir-collect.sh`

**Cloud metadata not collected**  
IMDSv2 token acquisition failed. Check network/firewall.

---

## Important

Use only on systems you have authorization to investigate. Collected data may contain sensitive information. Encrypt and secure result files.

---

## License

MIT License - see [LICENSE](LICENSE)

---

## Contact

- Issues: [GitHub Issues](https://github.com/yuzuha4355/ldir-toolkit/issues)
- Discussions: [GitHub Discussions](https://github.com/yuzuha4355/ldir-toolkit/discussions)

---

**Version**: 0.2.0  
**Maintainer**: [@yuzuha4355](https://github.com/yuzuha4355)
