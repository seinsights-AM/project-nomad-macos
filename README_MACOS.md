<div align="center">
<img src="admin/public/project_nomad_logo.webp" width="200" height="200"/>

# Project N.O.M.A.D. for macOS
### Node for Offline Media, Archives, and Data

**Knowledge That Never Goes Offline — Now on Your Mac**

[![Upstream](https://img.shields.io/badge/Upstream-Crosstalk%20Solutions-blue)](https://github.com/Crosstalk-Solutions/project-nomad)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)
[![CI](https://github.com/seinsights-AM/project-nomad-macos/actions/workflows/test-macos-installer.yml/badge.svg)](https://github.com/seinsights-AM/project-nomad-macos/actions)

</div>

---

## What Is This?

Imagine having Wikipedia, AI chat, offline maps, educational courses, and a bunch of useful tools — all running on your Mac, **without needing the internet**. That's Project N.O.M.A.D.

You download it once while you have internet, and from then on, everything works offline. It's like carrying a library, a tutor, and a research assistant in your backpack.

**Some things you can do with it:**

- **Ask an AI questions** about anything — it runs entirely on your Mac, no cloud needed
- **Upload documents** (PDFs, notes, manuals) and ask the AI about them
- **Browse Wikipedia offline** — from a quick-reference version (313 MB) to the whole thing (118 GB)
- **View offline maps** of any region you've downloaded
- **Take Khan Academy courses** without internet
- **Encrypt, decode, and analyze data** with built-in tools
- **Take notes** with a built-in markdown editor

The original N.O.M.A.D. was built for Linux servers. **This fork makes it work on macOS** — specifically optimized for Apple Silicon Macs (M1/M2/M3/M4) so the AI runs fast using your Mac's GPU.

## Quick Install

One command. It handles everything — Homebrew, Docker, Ollama, the whole stack:

```bash
curl -fsSL https://raw.githubusercontent.com/seinsights-AM/project-nomad-macos/main/install/install_nomad_macos.sh \
  -o install_nomad_macos.sh && bash install_nomad_macos.sh
```

The installer walks you through everything interactively:

1. **Checks your system** — macOS version, architecture, disk space, internet
2. **Asks where to install** — your local drive or an external SSD (auto-detected)
3. **Installs dependencies** — Xcode tools, Homebrew, Docker Desktop, Ollama
4. **Recommends an AI model** — picks the best one for your Mac's memory
5. **Launches everything** — pulls containers, starts services, shows you the URL

When it's done, open **http://localhost:8080** in your browser.

### Want to test first without installing anything?

```bash
bash install_nomad_macos.sh --dry-run
```

This simulates the entire install, validating your system without downloading or changing anything.

## What Gets Installed

| Component | What It Is | How It's Installed |
|---|---|---|
| **Docker Desktop** | Runs the N.O.M.A.D. services in containers | `brew install --cask docker` |
| **Ollama** | Runs AI models locally using your Mac's GPU | `brew install ollama` |
| **N.O.M.A.D. Command Center** | The main web interface for managing everything | Docker container |
| **MySQL** | Database for settings, chat history, etc. | Docker container |
| **Redis** | Caching and background job queues | Docker container |
| **Dozzle** | Optional log viewer at port 9999 | Docker container |

**No `sudo` required.** The entire install runs as your normal user account.

## External Drive Support

You can install N.O.M.A.D. on an external USB-C SSD. The installer:

- Auto-detects connected drives and shows free space
- Checks the filesystem (rejects NTFS which is read-only on Mac)
- Tests write permissions (catches macOS privacy restrictions)
- Suppresses Spotlight indexing on data directories

This means you could set up N.O.M.A.D. on a portable SSD and bring your offline knowledge server anywhere.

## Smart AI Model Recommendation

The installer detects your Mac's unified memory and recommends the optimal AI model:

| Your Mac's RAM | Recommended Model | Why |
|---|---|---|
| 8 GB | `qwen3:4b` | Best sub-5B model, fits tight budgets |
| 16 GB | `qwen3:8b` | Fast and capable with headroom for Docker |
| 18 GB | `qwen3:14b` | Big quality jump — strong reasoning and RAG |
| 24 GB | `qwen3:30b-a3b` | MoE architecture: 30B brain at 3B speed |
| 32-36 GB | `qwen3.5:35b-a3b` | Best value — 35B knowledge, blazing fast |
| 48 GB | `deepseek-r1:32b` | RL-trained reasoning for complex documents |
| 64+ GB | `deepseek-r1:70b` | Powerhouse for serious research |
| 128 GB | `qwen3.5:122b-a10b` | 122B knowledge depth at 10B speed |

The installer offers to download your recommended model right there during setup. You can always change models later through the N.O.M.A.D. interface or with `ollama pull <model>`.

## What You Need

#### Minimum (just the platform, no AI)
- Any Mac running **macOS 12 (Monterey)** or later
- **5 GB** free disk space
- Internet connection for initial setup

#### Recommended (with AI)
- **Apple Silicon Mac** (M1/M2/M3/M4) — for Metal GPU acceleration
- **16+ GB** unified memory — more RAM = bigger/smarter AI models
- **20+ GB** free disk space (more if downloading Wikipedia, maps, etc.)

Intel Macs work too, but AI will run on CPU only (slower).

## Helper Scripts

After installation, two scripts are available in your install directory:

**Start everything** (Docker Desktop + Ollama + containers):
```bash
~/.project-nomad/start_nomad.sh
```

**Stop everything** (with option to keep Ollama running):
```bash
~/.project-nomad/stop_nomad.sh
```

N.O.M.A.D. auto-restarts when Docker Desktop launches, so you typically only need these for troubleshooting.

---

## Technical Details

### How This Fork Differs from Upstream

The [original Project N.O.M.A.D.](https://github.com/Crosstalk-Solutions/project-nomad) is built for Debian/Ubuntu Linux. This fork adapts it for macOS while keeping the core application unchanged. Here's exactly what's different:

#### Architecture Change: Native Ollama

**Linux (upstream):** Ollama runs inside a Docker container with NVIDIA GPU passthrough (`--gpus all`).

**macOS (this fork):** Ollama runs **natively** on macOS, outside of Docker. The N.O.M.A.D. admin container connects to it via `http://host.docker.internal:11434`.

Why: Docker Desktop for Mac runs containers inside a Linux VM. That VM has zero access to Apple's Metal GPU. Running Ollama in Docker on a Mac means CPU-only inference — roughly 10x slower than native Metal. By running Ollama natively, your AI models get full GPU acceleration.

#### Removed: Disk Collector Sidecar

**Linux (upstream):** A sidecar container mounts the host root filesystem (`/:/host:ro,rslave`) and uses `lsblk` + `/proc/1/mounts` to collect disk usage info.

**macOS (this fork):** Removed entirely. Every piece of this — `rslave` mount propagation, `/proc`, `lsblk` — is Linux-only. The admin UI handles missing disk data gracefully.

#### Removed: NVIDIA GPU Detection

**Linux (upstream):** Install script runs `lspci` and `nvidia-smi` to detect GPUs, installs the NVIDIA Container Toolkit, configures Docker's NVIDIA runtime.

**macOS (this fork):** All NVIDIA logic is replaced with Apple Silicon detection via `sysctl` and `uname -m`. GPU info comes from `system_profiler SPDisplaysDataType`.

#### Changed: Install Paths

**Linux (upstream):** `/opt/project-nomad/` (requires root, SIP-protected on macOS).

**macOS (this fork):** `~/.project-nomad` (user home, no root needed) or external drive path selected during install.

#### Changed: System Commands

| Function | Linux (upstream) | macOS (this fork) |
|---|---|---|
| Package manager | `apt-get` | `brew` |
| Service management | `systemctl` | `open -a Docker`, `brew services` |
| IP detection | `hostname -I` | `ipconfig getifaddr en0` |
| In-place sed | `sed -i` | `sed -i ''` (BSD) |
| GPU detection | `lspci`, `nvidia-smi` | `sysctl`, `system_profiler` |
| Docker install | `get.docker.com` script | `brew install --cask docker` |

#### Changed: Docker Compose

The macOS compose file (`management_compose_macos.yaml`) compared to the Linux version:

- Removes the `disk-collector` service entirely
- Removes `extra_hosts: host.docker.internal:host-gateway` (Docker Desktop for Mac resolves this natively)
- Removes `/:/host:ro,rslave` root filesystem mount
- Uses `NOMAD_DIR_PLACEHOLDER` for volume paths (replaced by installer with actual path)
- Removes the `NOMAD_DIR_PLACEHOLDER:NOMAD_DIR_PLACEHOLDER` updater mount uses actual install path

#### Added: macOS-Specific Features

- **Interactive installer** with external drive detection, filesystem validation, and TCC permission checks
- **Smart model recommendation** based on detected unified memory
- **Spotlight suppression** (`.metadata_never_index`) in data directories
- **Docker Desktop first-launch handling** — opens the app, pauses for license acceptance, polls until ready
- **Resume-on-interrupt** — saves progress to a state file, picks up where you left off
- **`--dry-run` mode** for testing the installer without installing anything

### Docker Compose Services (macOS)

| Service | Image | Port | Purpose |
|---|---|---|---|
| admin | `ghcr.io/crosstalk-solutions/project-nomad:latest` | 8080 | Command Center (main app) |
| mysql | `mysql:8.0` | 3306 | Persistent database |
| redis | `redis:7-alpine` | 6379 | Cache and job queues |
| dozzle | `amir20/dozzle:v10.0` | 9999 | Container log viewer |
| updater | `project-nomad-sidecar-updater:latest` | — | Self-update capability |

**Not included on macOS:** `disk-collector` (Linux-only)

**Runs natively (not in Docker):** Ollama (for Metal GPU access)

### CI/CD

Every push runs 6 automated tests on GitHub Actions macOS runners:

1. **ShellCheck** — lints all scripts for common bash pitfalls
2. **Bash Syntax** — validates scripts parse correctly
3. **Dry-Run** — runs the full installer in simulation mode on a real Mac
4. **Compose Validation** — parses the compose file, verifies services, checks for Linux-only mounts
5. **Preflight Unit Tests** — tests each function: OS detection, version parsing, disk space, IP, password gen, BSD sed
6. **Inline Compose Generator** — tests the fallback compose generation function

### Project Structure (macOS additions)

```
install/
  install_nomad_macos.sh          # Interactive one-command installer
  management_compose_macos.yaml   # macOS Docker Compose (no disk-collector, no NVIDIA)
  start_nomad_macos.sh            # Start: Docker Desktop + Ollama + containers
  stop_nomad_macos.sh             # Stop: containers + optional Ollama stop
.github/
  workflows/
    test-macos-installer.yml      # CI: shellcheck, syntax, dry-run, compose validation
```

All other files (admin app, collections, Dockerfile, etc.) are unchanged from upstream.

---

## Relationship to the Original Project

This is a **fork** of [Crosstalk Solutions' Project N.O.M.A.D.](https://github.com/Crosstalk-Solutions/project-nomad), adapted for macOS. The upstream project is the authoritative source for the core application — we only add macOS-specific installation and configuration.

- **Upstream:** `Crosstalk-Solutions/project-nomad` (Linux, Debian/Ubuntu)
- **This fork:** `seinsights-AM/project-nomad-macos` (macOS, Apple Silicon + Intel)

We track upstream releases and merge updates as they come. The core N.O.M.A.D. application (admin UI, API, database schema, all features) is identical — only the install process and runtime configuration differ.

## Contributing

Contributions welcome! If you find macOS-specific bugs or have improvements:

1. Fork this repo
2. Create a feature branch (`git checkout -b fix/my-fix`)
3. Make your changes
4. Test with `--dry-run` and verify CI passes
5. Open a pull request

For issues with the core N.O.M.A.D. application (not macOS-specific), please report them to the [upstream repo](https://github.com/Crosstalk-Solutions/project-nomad/issues).

## Community

- **Original N.O.M.A.D.:** [projectnomad.us](https://www.projectnomad.us)
- **Discord:** [Crosstalk Solutions Community](https://discord.com/invite/crosstalksolutions)
- **Benchmark Leaderboard:** [benchmark.projectnomad.us](https://benchmark.projectnomad.us)
- **FAQ:** [FAQ.md](FAQ.md)

## License

Project N.O.M.A.D. is licensed under the [Apache License 2.0](LICENSE). This fork maintains the same license.
