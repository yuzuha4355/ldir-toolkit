# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-13

Log collection with a chosen period and a size cap, a virtualization module, and fixes for artifacts that looked collected but were not.

### Changed — output paths and behaviour existing users will notice
- **`logs/journal_7days.txt` is renamed `logs/journal_period.txt`.** It now covers the log period (30 days by default, `--log-days`). In full mode without `--log-days` there is no period and the export is `logs/journal_full.txt` as before
- **`journal_ssh.txt`, `journal_sshd.txt`, `journal_cron.txt` and `journal_errors.txt` are limited to the log period.** Up to 0.3.2 they covered the whole journal. `journal_cron.txt` now also includes the RHEL unit `crond`
- **Rotated logs are collected.** `auth.log`, `secure`, `syslog`, `messages`, `kern.log`, `wtmp`, `btmp` and the package, web server, database, mail and firewall logs are taken with their rotations (`.1`, `.2.gz`, `-YYYYMMDD`) when modified within the period. Compressed files are copied as they are
- **Log files keep their original names.** On RHEL-family hosts `/var/log/secure` was copied twice, once as `logs/auth.log`; it is now only `logs/secure` (and its rotations). Debian's `logs/auth.log` is unchanged
- **Web server and database log directories are no longer copied whole.** `logs/nginx/`, `logs/apache2/`, `logs/httpd/`, `logs/mysql/`, `logs/postgresql/` keep their layout but only hold files from the period, up to the cap
- **Audit logs moved from `execution/` to `logs/`**: `execution/audit/` → `logs/audit/`, `execution/audit_execve.txt`, `audit_user_cmd.txt`, `audit_recent.txt` → `logs/`. They follow the period and the cap; `ausearch` gets `--start`. The move also keeps the volatile-first module from spending time on large copies
- `logs/apt/` holds `history.log*` and `term.log*` only (no `eipp.log.xz`)
- Package manager logs are no longer duplicated under `custom_environment/packages/` (they are in `logs/`, period-limited)
- LXC moved from `containers/lxc/lxc-ls.txt` to `virtualization/host/lxc/`. `containers/privileged_groups.txt` lists `docker` and `podman` only; `lxd` and `incus` are in `virtualization/privileged_groups.txt`. `containers/no_container_runtime.txt` now points to `virtualization/`
- **Per-user artifacts follow the user database**, not `/root` and `/home/*` only: command history, SSH, user systemd units, autostart, shell init files, browser data and `~/.config`. Directories are named after the user name. A home under `/root` or `/home` with no passwd entry is labelled `orphan-home_<name>`
- `persistence/shell_init/<user>/` is created only for users that have such files (it used to be created, empty, for every home)
- History files are copied with their modification time (`cp -a`); 0.3.2 used plain `cp`
- Single files that are symbolic links (`/etc/resolv.conf`, `/etc/os-release`, `/etc/rc.local` on RHEL, ...) are copied as the content of their target, and the link is recorded in `_symlinks.txt` next to the copy. Up to 0.3.2 the collection held a dangling relative link, which was not hashed either
- Fast-mode SUID/SGID and world-writable search also covers `/usr/bin`, `/usr/sbin`, `/bin` and `/sbin` (when not links into `/usr`) and `/usr/libexec`, before `/usr/local` and `/opt`
- Commands whose failure was silently ignored now report it: `iptables*`, `ip6tables`, `nft`, `ufw`, `bpftool`, `dmesg` (WARN on a host, DEBUG inside a container), `lscpu`, `lsblk`, `lsmod`, `ip route show table all`, `atq`, `docker/podman --version`, `kubelet` journal. `lsof`, `sysctl -a`, `mokutil` and `firewall-cmd` exit codes are interpreted (no WARN for "nothing found" or "firewalld not running")
- `--no-redact` also turns off the new masking of VM definitions and hypervisor configuration

### Added
- `--log-days 30|60|90` / `LDIR_LOG_DAYS` (default 30; any other value exits with status 1) and `--log-max-mb N` / `LDIR_LOG_MAX_MB` (default 100 MB per log group, 0 = no cap). Full mode has no period and no cap unless these are given. Both are recorded in the manifest (`Log Days`, `Log Since`, `Log Size Cap`)
- `logs/log_summary.txt` (per log group: `collected`, `capped`, `none_in_period`, `not_present`, `symlink_only`, `copy_failed`) and `logs/log_inventory.tsv` (every file and its decision, including the files not collected because of the cap)
- Binary journal files (`logs/journal/`, `logs/run_log/journal/`), `logs/journal_auth.txt` (auth/authpriv facility: on hosts without rsyslog this is the only authentication record), `/var/log/cron*` (RHEL), `maillog*`, `boot.log*`, `mariadb/`, `mongodb/`, `redis/`, `lighttpd/`, RHEL PostgreSQL logs under `/var/lib/pgsql`, and `logs/var_log_listing.txt`
- `35_virtualization` module (`virtualization/`): whether this host is a VM and why (also in the manifest as `Virtualization`), guest and cloud agents that can run commands in the guest, and on hypervisor hosts libvirt (VMs, networks, pools, snapshots, definitions, logs), Proxmox VE (`/etc/pve`, task logs, API access log), LXC, LXD / Incus (read from the API socket), VirtualBox, Xen dom0, running hypervisor processes. A WARN flags QEMU running outside libvirt and Proxmox. Disk images and memory state are listed, never copied. `LDIR_VIRT_TIMEOUT`, `LDIR_VIRT_BUDGET`
- Masking for configuration files (`redact_config`): VNC/SPICE passwords, cloud-init user-data, LXD `environment.*`, Proxmox `cipassword`, QEMU secret objects, URL credentials
- `config/user_homes.tsv`, `config/getent_passwd.txt`, `config/getent_group.txt`, `config/sshd_effective_config.txt` (`sshd -T`), `authorized_keys2`, `~/.ssh/rc`, `~/.ssh/environment`, `ssh_dir_listing.txt`, and key files named by `AuthorizedKeysFile`
- History: ash, sh, ksh, fish, `.python_history`, `.mysql_history`, `.psql_history`, `.sqlite_history`, `.rediscli_history`, `.node_repl_history`, `.irb_history`, `.dbshell`, `.lesshst`, `.viminfo`, `.wget-hsts` (`execution/user_history/<user>/`)
- Persistence: `/usr/local/lib/systemd/system`, transient units (`/run/systemd/transient`), `/run/systemd/system`, `/etc/systemd/user`, systemd generators, `/etc/anacrontab`, `cron.allow` / `cron.deny`, RHEL `/etc/bashrc`, zsh and csh system files, `/etc/environment`, more per-user shell init files
- `hosts.allow` / `hosts.deny`, `sudo.conf`, `doas.conf`

### Fixed
- **On BusyBox (Alpine) a scan cut off by the fast-mode time budget was not marked partial.** BusyBox `timeout` exits with 143, not 124; `run_limited` now reports 124 for both, so `scan_incomplete.txt` and the `# PARTIAL RESULT` note appear as intended
- **`docker inspect` failures left an empty `<ID>.json`** that read as "collected". A failure now leaves `<ID>.inspect_failed.txt` and a WARN; `diff` and `logs` failures are counted per kind
- The unit test that rejects unchecked `cmd > file 2>&1` missed lines ending in `|| true`; it now catches them (deliberate exceptions carry `# ldir:allow`)
- README: the module table was truncated

### Security
- **Private keys are detected by content and never written to the output.** Up to 0.3.2, `/etc/ssh` was copied and `ssh_host_*_key` deleted afterwards, which left the deleted keys recoverable on the output medium, and host keys with other names (`HostKey` in `sshd_config`) were collected. `/etc/containers/auth.json` had the same copy-then-delete pattern. Excluded paths are listed in `excluded_files.txt`
- Key stores are not collected: `/etc/libvirt/secrets`, `/etc/pve/priv`, `*.key`, `*.keyring`, `*.pw` and similar under the copied configuration trees

## [0.3.2] - 2026-11-13

Fixes from an independent review of v0.3.1.

### Security
- **Secret masking missed plural names.** Variables such as `GITHUB_TOKENS` or `API_TOKENS` were written in clear text: the name rule required that `TOKEN` not be followed by `S` (added in 0.3.0 to spare `MAX_TOKENS`). The rule is now a plain `TOKEN`, as the specification already stated. Collections made with 0.3.0 or 0.3.1 may contain such values in `system/environment_variables.txt`, in `execution/proc_details/*/environ.txt` (full mode) and in `containers/*/inspect/*.json`

### Fixed
- **Failed collection commands did not reach the manifest.** Commands written as `cmd > file 2>&1` left only an error message in the output file while the module reported `warn=0`. They now go through `capture`, which counts a non-zero exit as a WARN and records a missing command in the output file. A unit test rejects new unchecked redirects
- **BusyBox `ps` degraded silently**: BSD-style options were ignored and `-o ...,lstart` failed, yet the module reported success. The module now detects a non-procps `ps`, requests the columns it supports, raises a WARN and writes `execution/ps_limited.txt`
- **A timed-out fast scan left empty SUID/SGID and world-writable lists** that read like "none found". The lists now start with a `# PARTIAL RESULT` note
- `systemctl` runtime queries are skipped when systemd is not PID 1 (they always failed in containers); `persistence/systemd_not_running.txt` records this
- A failing `find`/`du` while computing statistics could abort the run before hashes were written
- A WARN is raised when `timeout` is missing, since the fast-mode budget cannot then interrupt a scan
- README: wrong module count, a broken leftover table, and links to documents removed in 0.3.0

### Changed
- `fstab` is copied as a file (`filesystem/fstab.txt`) instead of via `cat`
- Documentation states that the test suite, `Makefile` and CI are in the repository, not in the release archive, and lists the new known constraints (BusyBox `ps`, non-standard `HostKey` names, missing `timeout`)

## [0.3.1] - 2026-11-13

Measured on a GitHub-hosted runner VM (systemd and Docker running, large `/opt` and `/usr/local`), where fast mode took 231 seconds.

### Fixed
- `25_kernel` took 155s in fast mode: `getcap -r` walked `/usr/lib`, `/opt`, `/home` and `/usr/local`, and the BPF fd scan started one `readlink` per open file descriptor. Fast mode now checks binary directories and temp areas only (full mode still scans `/`), and fds are listed with a single `ls`. Measured after the change: 2s
- `70_filesystem` spent about 150s on the SUID/SGID and world-writable search. The time is proportional to the number of files under `/opt` and `/usr/local`. Two changes:
  - both lists now come from one traversal (measured: 152s -> 131s; the second walk had been hitting a warm cache, so this alone helped little)
  - in fast mode the search has a time budget (`LDIR_FAST_SCAN_BUDGET`, default 60s). Small, abuse-prone locations are scanned first. When the budget runs out the lists are marked partial with a WARN and `filesystem/scan_incomplete.txt`. Full mode is not limited
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
