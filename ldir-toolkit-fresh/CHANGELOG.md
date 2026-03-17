# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
