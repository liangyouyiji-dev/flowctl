# flowctl

> **Releases paused — 2026-10-28.** Published releases, binary assets and version tags have been withdrawn while the official domain is being prepared. This repository and its distribution documentation are retained. Installation and upgrade commands below are reference instructions for future releases; downloads are currently unavailable. Application source code remains private.

Official binary distribution of flowctl by 亮有一计.

Website: https://liangyouyiji.com · Support: support@liangyouyiji.com

This repository contains installation tooling and binary releases. Application source code is maintained privately. GitHub's automatically generated “Source code” archives contain only this distribution repository; download the platform archive to install flowctl.

## Install

Install [Cosign](https://docs.sigstore.dev/cosign/system_config/installation/) first (the release verification flow uses Cosign 2.6.0). Then download and inspect the installer:

```sh
curl -fsSLO https://raw.githubusercontent.com/liangyouyiji-dev/flowctl/main/scripts/install.sh
bash install.sh
```

Default installation path: `~/.local/bin/flowctl`. Add `~/.local/bin` to your PATH if needed. Use `--install-dir PATH` or `--no-skill` to customize installation. Windows users can download the matching ZIP from Releases and verify it before extracting `flowctl.exe`.

## Releases and verification

Releases include macOS (amd64/arm64), Linux (amd64/arm64/386/riscv64), and Windows (amd64/arm64) archives, a dependency SBOM, SHA-256 checksums, and Cosign signature/certificate files. Distribution checksums are signed by this repository's `.github/workflows/release.yml` workflow at the release tag, using GitHub Actions OIDC. This authenticates the distribution; it is not a claim that private application source was built on GitHub.

Prereleases are staging candidates. Use a stable release with its complete signature files. The installer verifies publisher identity, checksum, version and command contracts before installation. macOS executables are not Apple-notarized; follow your organization's software approval process if Gatekeeper intervenes.

## Version and upgrade

```sh
flowctl version
flowctl upgrade --check
flowctl upgrade
```

Upgrade checks the latest stable GitHub release and only upgrades when it is newer. `flowctl upgrade --force` explicitly reinstalls the latest release (including a downgrade). `flowctl upgrade --no-skill` updates only the executable. Cosign must be available on PATH. The previous executable is retained as `flowctl.bak`. Configure and log into your own endpoint with an explicit `--profile local|test|prod`; installation does not configure production access.

Starting with 2.1.35, version checks and upgrades are independent of backend profiles and login credentials. They work even when a production endpoint is not configured. Set their output preferences with command-line flags or `FLOWCTL_FORMAT` / `FLOWCTL_LANG`.

For bugs or installation questions, open an issue without credentials, tokens or personal data.
