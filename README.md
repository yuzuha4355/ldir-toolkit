# LDIR-Toolkit

Linux forensic data collection tool for incident response.

[![Version](https://img.shields.io/badge/version-0.3.2-blue.svg)](https://github.com/yuzuha4355/ldir-toolkit/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)]()

---

## Documentation

| Document | Contents |
|---|---|
| [docs/PROCEDURE.md](docs/PROCEDURE.md) | 収集手順書: 準備から収集、検証、持ち出し、後始末まで（作業記録の様式付き） |
| [docs/SPECIFICATION.md](docs/SPECIFICATION.md) | 仕様書: オプション、収集順、出力ファイル、秘匿情報の扱い、モジュール規約 |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Overview

LDIR-Toolkit collects system artifacts from Linux hosts for forensic analysis. Supports 20+ distributions including Ubuntu, Debian, RHEL-based systems, Arch, Alpine, and embedded/cloud environments. Runs offline, requires root, typically completes in minutes (depends on system size and LDIR_MODE), outputs can be large.

**Use case**: Incident response, security audits, compliance checks.

---

## Features

- Multi-distribution support (Ubuntu, Debian, Rocky, AlmaLinux, CentOS, Fedora, Amazon Linux, Arch, openSUSE, Gentoo, Alpine, Raspberry Pi OS, Oracle Linux)
- 12 collection modules, run in order of volatility: system info, processes, network, kernel (modules/eBPF/capabilities), containers, auth (sudoers/SSH/PAM), persistence (cron/systemd), logs, filesystem, web artifacts, custom environment detection, cloud metadata
- Auto-detection: package managers (apt/yum/dnf/pacman/zypper/apk), init systems (systemd/OpenRC/runit/s6), security frameworks (SELinux/AppArmor)
- Evidence integrity: SHA256 hashing, manifest with per-module warnings, execution logging
- Secret-looking environment variable values are masked by default
- Offline-capable, no network required

---

## Quick Start

### Modes

- **fast (default)**: first-response friendly (smaller, safer defaults; web/cloud modules disabled)
- **full**: exhaustive collection (may be slow & large)

```bash
# fast (default)
sudo ./ldir-collect.sh /tmp/ldir_output

# full
sudo ./ldir-collect.sh --mode full /tmp/ldir_output

# Also pack the result into a tar.gz with a checksum
sudo ./ldir-collect.sh --archive /mnt/usb/evidence
```

### Download

Latest release: <https://github.com/yuzuha4355/ldir-toolkit/releases/latest>

```bash
wget https://github.com/yuzuha4355/ldir-toolkit/releases/latest/download/ldir-toolkit-latest.tar.gz
wget https://github.com/yuzuha4355/ldir-toolkit/releases/latest/download/ldir-toolkit-latest.tar.gz.sha256
sha256sum -c ldir-toolkit-latest.tar.gz.sha256
tar -xzf ldir-toolkit-latest.tar.gz
cd ldir-toolkit-v*/
```

Each release also carries the versioned archive (`ldir-toolkit-vX.Y.Z.tar.gz`) and the two documents:
[PROCEDURE.md](https://github.com/yuzuha4355/ldir-toolkit/releases/latest/download/PROCEDURE.md) (手順書),
[SPECIFICATION.md](https://github.com/yuzuha4355/ldir-toolkit/releases/latest/download/SPECIFICATION.md) (仕様書).

### Usage

```bash
# Collect data (requires root); --archive also writes a tar.gz and its checksum
sudo ./ldir-collect.sh --archive /mnt/usb/evidence
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

Modules run in order of volatility: what disappears first is collected first.

| # | Module | Output | Artifacts |
|---|--------|---

## Output Structure

```
/tmp/ldir_output/[hostname]_[timestamp]/
├── system/                # 10_system_info
├── execution/             # 15_execution
├── network/               # 20_network
├── kernel/                # 25_kernel
├── containers/            # 30_containers
├── config/                # 40_auth (passwd, sudoers, PAM, SSH)
├── persistence/           # 50_persistence
├── logs/                  # 60_logs
├── filesystem/            # 70_filesystem
├── web/                   # 80_web (disabled in fast mode)
├── custom_environment/    # 90_custom_environment
├── cloud_metadata/        # 91_cloud_metadata (disabled in fast mode)
└── metadata/
    ├── manifest.txt       # Environment summary and per-module result
    ├── collection.log     # Tool execution log
    ├── modules/*.log      # One log per module
    └── file_hashes.txt    # SHA256 of every collected file (relative paths)
```

With `--archive`, `[hostname]_[timestamp].tar.gz` and a `.sha256` file are written next to the directory.

---

## What's New (v0.3.0)

- Collection order follows the order of volatility (processes and network before logs and filesystem)
- New `kernel` module: kernel modules and taint, hidden-module cross-check, eBPF, `ld.so.preload`, file capabilities
- New `containers` module: Docker / Podman / CRI / Kubernetes node artifacts
- Secret values in collected environment variables are masked by default
- Procedure and specification documents; `make dist` builds the release archive

See [CHANGELOG.md](CHANGELOG.md) for details.

---

## Requirements

- OS: Linux (see supported distributions)
- Permissions: root or sudo
- Storage: a few hundred MB (fast); several GB possible (full)
- Execution time: about a minute (fast); longer in full mode
- Network: not required

---

## Usage Scenarios

### Direct execution on target server
```bash
tar -xzf ldir-toolkit-latest.tar.gz
cd ldir-toolkit-v*/
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

Files under `metadata/`:
- `manifest.txt`: environment summary, per-module result (warn/error counts, duration)
- `file_hashes.txt`: SHA256 for all collected files, recorded with relative paths
- `collection.log`: tool execution log

Verification (works on the analysis machine too, since paths are relative):
```bash
cd /tmp/ldir_output/<hostname>_<timestamp>
cat metadata/manifest.txt
sha256sum -c metadata/file_hashes.txt | grep -v ': OK$'   # prints only mismatches
```

The collector prints the SHA256 of `file_hashes.txt` itself at the end of the run.
Record that value in your chain-of-custody notes.

Exit status: `0` all modules completed, `1` setup error, `2` at least one module failed.

---

## Testing

The release archive contains the collector and the documents only.
The test suite, `Makefile`, CI workflows and `docker-test/` live in the repository:

```bash
git clone https://github.com/yuzuha4355/ldir-toolkit.git
cd ldir-toolkit
make lint          # shellcheck
make test          # unit tests, no root needed
sudo make smoke    # real collection + integrity checks; use a container or test VM
```

CI runs these on every push: unit tests and a real collection in containers for
10 distributions, plus a real collection on the runner host (systemd and Docker running).

---

## Contributing

Contributions welcome. Open an issue or a pull request; `make check` must pass.

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

## Development

These commands need a clone of the repository (they are not in the release archive).

```bash
make lint     # shellcheck
make dist     # release archive + .sha256 in dist/
make test     # unit tests, no root needed
sudo make smoke   # real collection + integrity checks; run in a container or test VM
```

- Modules are discovered automatically: drop `NN_name.sh` into `ldir-toolkit/modules/` and it runs in numeric order. The number encodes volatility order, and every module must be listed in `docs/SPECIFICATION.md` (a unit test checks this). Each module receives the collection directory as `$1`.
- Use `capture`, `safe_copy`, `log_*` from `lib/common.sh`. Do not write `cmd > file 2>&1` directly: a failure would not reach the manifest (a unit test rejects it). A missing source file is expected and logged as DEBUG; `log_warn` is for things that should have worked.
- Releasing: bump `LDIR_VERSION` in `ldir-collect.sh`, add the CHANGELOG entry, merge to `main`. `.github/workflows/release.yml` then builds and publishes the release if that version has none yet.
- CI (`.github/workflows/ci.yml`) runs lint, unit tests, and the smoke test inside containers for several distributions and on the runner host.

---

## Contact

- Issues: [GitHub Issues](https://github.com/yuzuha4355/ldir-toolkit/issues)
- Discussions: [GitHub Discussions](https://github.com/yuzuha4355/ldir-toolkit/discussions)

---

**Version**: 0.3.2  
**Maintainer**: [@yuzuha4355](https://github.com/yuzuha4355)
