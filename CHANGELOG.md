# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-11-13

Measured on a GitHub-hosted runner VM (systemd and Docker running, large `/opt` and `/usr/local`), where fast mode took 231 seconds.

### Fixed
- `25_kernel` took 155s in fast mode: `getcap -r` walked `/usr/lib`, `/opt`, `/home` and `/usr/local`, and the BPF fd scan started one `readlink` per open file descriptor. Fast mode now checks binary directories and temp areas only (full mode still scans `/`), and fds are listed with a single `ls`. Measured after the change: 2s
- `70_filesystem` walked the same trees twice, once for SUID/SGID and once for world-writable files (about 150s on that host with a cold cache). Both lists now come from one traversal
- `50_persistence`: the `LD_PRELOAD` text search of `/etc` is limited to 60s; a cut-off is reported as a WARN

### Added
- CI runs the smoke test on the runner host as well as in containers, and prints per-module timings and the timestamped progress log

## [0.3.0] - 2026-11-12

### Changed
- **Collection order now follows the order of volatility.** Modules were renumbered; output directory names are unchanged
  - `50_execution` -> `15_execution`, `60_network` -> `20_network`, `30_auth` -> `40_auth`, `40_persistence` -> `50_persistence`, `20_logs` -> `60_logs`
- **Secret values in environment variables are masked by default** (`GH_TOKEN=<redacted:40 chars>`); names are kept. Applies to the collector's own environment, per-process `environ` (full mode), container PID 1 environment, and `docker inspect` output. Disable with `--no-redact` / `LDIR_REDACT_SECRETS=0`
- The collector's own environment is saved once (`system/environment_variables.txt`); the duplicate under `custom_environment/` was removed
- Repository layout flattened: the `ldir-toolkit-fresh/` level is gone
- docker-test build context fixed (it expected a copy of the toolkit inside `docker-test/`)

### Added
- `25_kernel` module: loaded modules with taint flags, cross-check of `/proc/modules` against `/sys/module`, out-of-tree module files, eBPF programs/maps/links, `/etc/ld.so.preload`, file capabilities, security-relevant sysctls, LSM / lockdown / Secure Boot state, dmesg
- `30_containers` module: Docker and Podman (containers, images, networks, inspect, diff, risk summary), CRI (`crictl`), Kubernetes node files (static pod manifests, kubelet config), runtime sockets and privileged groups
- `docs/SPECIFICATION.md` (仕様書) and `docs/PROCEDURE.md` (手順書)
- `make dist` builds `dist/ldir-toolkit-vX.Y.Z.tar.gz` with a `.sha256`
- `LDIR_CONTAINER_TIMEOUT`
- Release workflow: merging a new version to `main` publishes the archive, checksums and both documents as a GitHub release

### Removed
- Duplicated and outdated documents (`QUICKSTART.md`, `README_EXTENDED.txt`, `DISTRIBUTION_GUIDE.txt`, the Japanese README inside `ldir-toolkit/`), replaced by the two documents above

## [0.2.2] - 2026-11-11

### Fixed
- Manifest recorded the OS version as "Collector Version" (sourcing `/etc/os-release` overwrote `VERSION`)
- Collector aborted on distributions without `VERSION_ID` in os-release (Arch, Debian testing) due to `set -u`
- `sha256sum -c` always failed for `collection.log` (log was appended after hashing)
- Directory copies were nested one level too deep (`config/pam.d/pam.d`, `logs/apt/apt`, ...)
- The collection listed its own output in `tmp_files.txt` / `modified_last_7days.txt` when writing under `/tmp`
- `journal_full.txt` only held the last 1000 lines; renamed to `journal_tail.txt`, real full journal in full mode
- SSH host private keys were copied with `/etc/ssh/` despite the documented intent not to collect private keys
- Fast mode copied each user's whole `~/.config` (browser profiles included); now a listing in fast mode, full copy in full mode
- Cloud metadata probes could be answered by an HTTP proxy (`--noproxy` added)
- `/opt/*/conf` directories from different products overwrote each other
- On BusyBox (Alpine) every `find -ls` listing was silently empty; falls back to `ls -ld`
- `--help` exited with status 1; unknown options were treated as an output directory

### Changed
- "File not found" is no longer a WARN. Warn counts in the manifest now mean real problems (`LDIR_VERBOSE=1` shows the notices)
- `file_hashes.txt` uses relative, sorted paths, so it verifies after moving the collection
- Unpackaged-binary check builds the package file list once instead of one `dpkg -S`/`rpm -qf` per file (fast mode on Ubuntu 24.04: 52s -> 11s)
- Modules are discovered from `modules/NN_*.sh`; no hard-coded list
- Per-user crontabs are saved only for users that have one (`persistence/user_crontab_l/`)
- Exit status is 2 when a module fails (was always 0)
- Colour output only on a terminal; honours `NO_COLOR`
- Removed unused `lib/detect_distro.sh` (the fallback path never called it)

### Added
- Options: `--mode`, `--archive` (tar.gz + `.sha256`), `--list-modules`, `--version`
- Per-module duration and UTC timestamp in the manifest
- Unit tests, smoke test, `Makefile`, and CI (shellcheck + multi-distribution container matrix)

## [0.2.1] - 2026-03-17

### Fixed
- Fixed module output path handling by passing collection directory to modules
- Ensured module output directories are created reliably
- Fixed silent failures by adding per-module logs (WARN/ERROR counts in manifest)
- Fixed tilde expansion issue in persistence module and improved user systemd unit collection

### Added
- fast/full mode control via `LDIR_MODE` (fast by default)
- Feature flags: `LDIR_ENABLE_WEB`, `LDIR_ENABLE_CLOUD_METADATA`
- AWS IMDSv2 token support (best-effort) in cloud metadata module

## [0.2.0] - 2025-12-08

### Added
- Extended distribution support for 20+ Linux distributions
- Custom environment detection module (90_custom_environment.sh)
- Cloud metadata collection module (91_cloud_metadata.sh)
  - AWS EC2 IMDSv2 support
  - GCP Compute Engine metadata
  - Azure VM metadata
- Advanced distribution detection logic (detect_distro_advanced.sh)
- Support for systemd-less environments (OpenRC/runit/s6)
- Support for minimal configurations (busybox-based)
- SELinux/AppArmor status detection
- Package manager auto-detection (apt/yum/dnf/pacman/zypper/apk)

### Changed
- Updated main collection script to v2.0
- Improved error handling across all modules
- Enhanced documentation with comprehensive guides

### Fixed
- Path detection issues on non-standard configurations
- Permission handling for restricted files

## [0.1.0] - 2025-12-07

### Added
- Initial release
- 8 core collection modules
  - system_info
  - logs
  - auth
  - persistence
  - execution
  - network
  - filesystem
  - web
- Support for Ubuntu, Debian, Rocky Linux
- Docker test environment
- SHA256 hashing and manifest generation
- Execution logging
