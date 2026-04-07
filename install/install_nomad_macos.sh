#!/bin/bash

# Project N.O.M.A.D. — macOS Installation Script
#
# One-command installer for macOS (Apple Silicon & Intel)
# Handles all dependencies, external drive support, and interactive setup.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/seinsights-AM/project-nomad-macos/main/install/install_nomad_macos.sh -o install_nomad_macos.sh && bash install_nomad_macos.sh
#
# Options:
#   --dry-run, -n    Simulate the installation without downloading or installing anything
#
# Author: Ahmed Elgazar (seinsights-AM)
# Based on: Crosstalk Solutions, LLC — Project N.O.M.A.D.
# License: Apache License 2.0

###################################################################################################################################################################################################
#                                                                                       Color Codes                                                                                               #
###################################################################################################################################################################################################

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

###################################################################################################################################################################################################
#                                                                                  Constants & Variables                                                                                          #
###################################################################################################################################################################################################

NOMAD_VERSION="1.31.0"
DEFAULT_NOMAD_DIR="$HOME/.project-nomad"
NOMAD_DIR=""
INSTALL_STATE_FILE=""
ARCH="$(uname -m)"
MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="$(echo "$MACOS_VERSION" | cut -d. -f1)"

# URLs — point to our macOS fork
REPO_BASE="https://raw.githubusercontent.com/seinsights-AM/project-nomad-macos/main"
COMPOSE_FILE_URL="${REPO_BASE}/install/management_compose_macos.yaml"
START_SCRIPT_URL="${REPO_BASE}/install/start_nomad_macos.sh"
STOP_SCRIPT_URL="${REPO_BASE}/install/stop_nomad_macos.sh"

# Dry-run mode — simulates everything without installing or downloading
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]] || [[ "${1:-}" == "-n" ]]; then
  DRY_RUN=true
fi

# State tracking for resume-on-interrupt
STEPS_COMPLETED=()

###################################################################################################################################################################################################
#                                                                                      Helper Functions                                                                                           #
###################################################################################################################################################################################################

# Read user input — works both in interactive mode and curl|bash piped mode
prompt() {
  if $DRY_RUN; then
    # In dry-run, auto-answer with "y" — uses printf -v for safe variable assignment (no eval)
    printf -v "$1" '%s' 'y'
    return 0
  fi
  read -r "$@" </dev/tty
}

# Print styled messages
info()    { echo -e "${BLUE}▸${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $1"; }
fail()    { echo -e "${RED}✗${RESET} $1"; }
step()    { echo -e "\n${BOLD}${WHITE}$1${RESET}\n"; }
divider() { echo -e "${DIM}──────────────────────────────────────────────────${RESET}"; }
dry()     { $DRY_RUN && echo -e "  ${DIM}[dry-run] Would: $1${RESET}" && return 0; return 1; }

banner() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${BOLD}${WHITE}Project N.O.M.A.D. for macOS${RESET}                                ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${DIM}Node for Offline Media, Archives, and Data${RESET}                ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${DIM}v${NOMAD_VERSION}${RESET}                                                    ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
  if $DRY_RUN; then
    echo -e "  ${YELLOW}${BOLD}DRY-RUN MODE${RESET} — simulating installation, nothing will be installed"
  fi
  echo ""
}

# Generate a random alphanumeric password
generate_password() {
  local length="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# Get available disk space in bytes for a given path
get_free_space_bytes() {
  df -k "$1" 2>/dev/null | awk 'NR==2 {print $4 * 1024}'
}

# Format bytes to human-readable
format_bytes() {
  local bytes=$1
  if (( bytes >= 1073741824 )); then
    echo "$(( bytes / 1073741824 )) GB"
  elif (( bytes >= 1048576 )); then
    echo "$(( bytes / 1048576 )) MB"
  else
    echo "$(( bytes / 1024 )) KB"
  fi
}

# Get local IP address (macOS-compatible)
get_local_ip() {
  # Try Wi-Fi first, then any active interface
  local ip
  ip=$(ipconfig getifaddr en0 2>/dev/null)
  if [[ -z "$ip" ]]; then
    ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
  fi
  if [[ -z "$ip" ]]; then
    ip="localhost"
  fi
  echo "$ip"
}

# Save install state for resume capability
save_state() {
  STEPS_COMPLETED+=("$1")
  if ! $DRY_RUN && [[ -n "$INSTALL_STATE_FILE" ]] && [[ -d "$(dirname "$INSTALL_STATE_FILE")" ]]; then
    printf '%s\n' "${STEPS_COMPLETED[@]}" > "$INSTALL_STATE_FILE"
  fi
}

# Check if a step was already completed (for resume)
step_done() {
  for s in "${STEPS_COMPLETED[@]}"; do
    [[ "$s" == "$1" ]] && return 0
  done
  return 1
}

# Load previous install state if exists
load_state() {
  if [[ -f "$INSTALL_STATE_FILE" ]]; then
    while IFS= read -r line; do
      STEPS_COMPLETED+=("$line")
    done < "$INSTALL_STATE_FILE"
    return 0
  fi
  return 1
}

# Cleanup handler for interrupts
cleanup() {
  echo ""
  warn "Installation interrupted."
  if [[ ${#STEPS_COMPLETED[@]} -gt 0 ]]; then
    info "Progress saved. Re-run the installer to resume from where you left off."
  fi
  exit 1
}

trap cleanup INT TERM HUP

###################################################################################################################################################################################################
#                                                                                   Preflight Checks                                                                                              #
###################################################################################################################################################################################################

preflight_checks() {
  step "Step 1 — Preflight Checks"

  # Check we're on macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    fail "This installer is for macOS only."
    echo -e "  For Linux, use the original installer: ${CYAN}https://github.com/Crosstalk-Solutions/project-nomad${RESET}"
    exit 1
  fi
  success "macOS detected — ${MACOS_VERSION}"

  # Check macOS version (need 12+)
  if [[ "$MACOS_MAJOR" -lt 12 ]]; then
    fail "macOS 12 (Monterey) or later is required. You're running macOS ${MACOS_VERSION}."
    exit 1
  fi
  success "macOS version supported"

  # Detect architecture
  if [[ "$ARCH" == "arm64" ]]; then
    success "Apple Silicon detected (arm64) — Metal GPU acceleration available"
  else
    success "Intel Mac detected (x86_64)"
    warn "AI performance will be slower without Apple Silicon GPU acceleration"
  fi

  # Check available disk space on boot drive
  local boot_free
  boot_free=$(get_free_space_bytes "/")
  local boot_free_formatted
  boot_free_formatted=$(format_bytes "$boot_free")

  if (( boot_free < 5368709120 )); then  # 5 GB minimum
    fail "Only ${boot_free_formatted} free on your boot drive. At least 5 GB is required."
    exit 1
  fi
  success "Boot drive has ${boot_free_formatted} free"

  # Check for bash
  if [[ -z "$BASH_VERSION" ]]; then
    fail "This script requires bash. Run with: bash install_nomad_macos.sh"
    exit 1
  fi
  success "Running in bash ${BASH_VERSION%%(*}"

  # Check network connectivity
  if curl -fsSL --max-time 10 https://github.com >/dev/null 2>&1; then
    success "Internet connection available"
  else
    fail "Cannot reach github.com. An internet connection is required for installation."
    exit 1
  fi

  # Check for VPN (warning only)
  if scutil --nc list 2>/dev/null | grep -q "Connected"; then
    warn "VPN connection detected. This can sometimes interfere with Docker networking."
    warn "If you experience issues, try disconnecting your VPN and re-running the installer."
  fi

  echo ""
  success "All preflight checks passed!"
}

###################################################################################################################################################################################################
#                                                                                   License Agreement                                                                                             #
###################################################################################################################################################################################################

accept_license() {
  step "License Agreement"

  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0."
  echo "Full license: https://www.apache.org/licenses/LICENSE-2.0"
  echo ""
  echo -ne "Do you accept the License Agreement? ${DIM}(y/N)${RESET} "

  local choice
  prompt choice
  case "$choice" in
    y|Y) success "License accepted." ;;
    *)
      fail "License not accepted. Installation cancelled."
      exit 1
      ;;
  esac
}

###################################################################################################################################################################################################
#                                                                                 Install Location Selection                                                                                      #
###################################################################################################################################################################################################

select_install_location() {
  step "Step 2 — Choose Install Location"

  local boot_free
  boot_free=$(get_free_space_bytes "/")
  local boot_free_formatted
  boot_free_formatted=$(format_bytes "$boot_free")

  echo -e "  ${BOLD}[1]${RESET} Local storage ${DIM}(${DEFAULT_NOMAD_DIR})${RESET} — ${GREEN}${boot_free_formatted} free${RESET}"

  # Detect external volumes
  local -a ext_volumes=()
  local -a ext_paths=()
  local -a ext_fs_types=()
  local idx=2

  if [[ -d "/Volumes" ]]; then
    for vol in /Volumes/*/; do
      # Skip the boot volume symlink
      vol="${vol%/}"
      local vol_name
      vol_name="$(basename "$vol")"

      # Skip "Macintosh HD" and hidden volumes
      [[ "$vol_name" == "Macintosh HD" ]] && continue
      [[ "$vol_name" == "Macintosh HD - Data" ]] && continue
      [[ "$vol_name" =~ ^\.  ]] && continue

      # Get filesystem type
      local fs_type
      fs_type=$(diskutil info "$vol" 2>/dev/null | grep "File System Personality" | sed 's/.*: *//')
      [[ -z "$fs_type" ]] && fs_type="Unknown"

      # Get free space
      local vol_free
      vol_free=$(get_free_space_bytes "$vol")
      local vol_free_formatted
      vol_free_formatted=$(format_bytes "$vol_free")

      # Check if NTFS (read-only on macOS)
      local ntfs_warning=""
      if echo "$fs_type" | grep -qi "ntfs"; then
        ntfs_warning=" ${RED}(NTFS — read-only, cannot use)${RESET}"
      fi

      echo -e "  ${BOLD}[${idx}]${RESET} ${vol_name} ${DIM}(${vol})${RESET} — ${GREEN}${vol_free_formatted} free${RESET} — ${DIM}${fs_type}${RESET}${ntfs_warning}"
      ext_volumes+=("$vol_name")
      ext_paths+=("$vol")
      ext_fs_types+=("$fs_type")
      ((idx++))
    done
  fi

  echo ""

  local choice
  if $DRY_RUN; then
    choice="1"
    info "[dry-run] Auto-selecting local storage"
  else
    echo -ne "Select install location ${DIM}[1-$((idx-1))]${RESET}: "
    prompt choice
  fi

  if [[ "$choice" == "1" ]] || [[ -z "$choice" ]]; then
    NOMAD_DIR="$DEFAULT_NOMAD_DIR"
    success "Installing to: ${NOMAD_DIR}"
  elif [[ "$choice" -ge 2 ]] && [[ "$choice" -lt "$idx" ]]; then
    local vol_idx=$((choice - 2))
    local selected_path="${ext_paths[$vol_idx]}"
    local selected_fs="${ext_fs_types[$vol_idx]}"

    # Reject NTFS
    if echo "$selected_fs" | grep -qi "ntfs"; then
      fail "NTFS drives are read-only on macOS. Please reformat as exFAT or APFS, or choose a different drive."
      exit 1
    fi

    NOMAD_DIR="${selected_path}/project-nomad"

    # Test writability (catches TCC permission issues)
    local test_file="${selected_path}/.nomad_write_test"
    if ! touch "$test_file" 2>/dev/null; then
      fail "Cannot write to ${selected_path}."
      echo ""
      warn "This is likely a macOS permissions issue. To fix it:"
      echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
      echo "  2. Enable access for your terminal app (Terminal or iTerm2)"
      echo "  3. Re-run this installer"
      exit 1
    fi
    rm -f "$test_file" 2>/dev/null

    success "Installing to: ${NOMAD_DIR}"
  else
    fail "Invalid selection."
    exit 1
  fi

  INSTALL_STATE_FILE="${NOMAD_DIR}/.install_state"

  if $DRY_RUN; then return 0; fi

  # Check for previous partial install
  if [[ -d "$NOMAD_DIR" ]]; then
    if load_state; then
      info "Found a previous partial installation. Resuming..."
    else
      warn "Directory ${NOMAD_DIR} already exists."
      echo -ne "Overwrite existing installation? ${DIM}(y/N)${RESET} "
      local overwrite
      prompt overwrite
      if [[ "$overwrite" != "y" ]] && [[ "$overwrite" != "Y" ]]; then
        fail "Installation cancelled."
        exit 1
      fi
    fi
  fi
}

###################################################################################################################################################################################################
#                                                                                  Dependency Installation                                                                                        #
###################################################################################################################################################################################################

install_xcode_clt() {
  if step_done "xcode_clt"; then return 0; fi

  if xcode-select -p &>/dev/null; then
    success "Xcode Command Line Tools — already installed"
    save_state "xcode_clt"
    return 0
  fi

  if dry "Install Xcode Command Line Tools"; then save_state "xcode_clt"; return 0; fi

  info "Installing Xcode Command Line Tools..."
  warn "A dialog will appear. Please click 'Install' and wait for it to complete."
  xcode-select --install 2>/dev/null

  # Wait for installation to complete
  local elapsed=0
  local timeout=600  # 10 minutes
  while ! xcode-select -p &>/dev/null; do
    if (( elapsed >= timeout )); then
      fail "Xcode Command Line Tools installation timed out."
      fail "Please install manually: xcode-select --install"
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  success "Xcode Command Line Tools installed"
  save_state "xcode_clt"
}

install_homebrew() {
  if step_done "homebrew"; then return 0; fi

  if command -v brew &>/dev/null; then
    success "Homebrew — already installed"
    save_state "homebrew"
    return 0
  fi

  if dry "Install Homebrew"; then save_state "homebrew"; return 0; fi

  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty

  # Add brew to PATH for this session
  if [[ "$ARCH" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! command -v brew &>/dev/null; then
    fail "Homebrew installation failed."
    exit 1
  fi

  success "Homebrew installed"
  save_state "homebrew"
}

install_rosetta() {
  if step_done "rosetta"; then return 0; fi

  if [[ "$ARCH" != "arm64" ]]; then
    save_state "rosetta"
    return 0
  fi

  if /usr/bin/pgrep -q oahd 2>/dev/null; then
    success "Rosetta 2 — already installed"
    save_state "rosetta"
    return 0
  fi

  if dry "Install Rosetta 2"; then save_state "rosetta"; return 0; fi

  info "Installing Rosetta 2 (required for some Docker images)..."
  softwareupdate --install-rosetta --agree-to-license 2>/dev/null

  success "Rosetta 2 installed"
  save_state "rosetta"
}

install_docker() {
  if step_done "docker"; then return 0; fi

  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    success "Docker Desktop — already installed and running"
    save_state "docker"
    return 0
  fi

  # Install Docker Desktop if the binary doesn't exist
  if ! command -v docker &>/dev/null; then
    if dry "Install Docker Desktop via brew"; then save_state "docker"; return 0; fi
    info "Installing Docker Desktop..."
    brew install --cask docker

    if [[ ! -d "/Applications/Docker.app" ]]; then
      fail "Docker Desktop installation failed."
      exit 1
    fi
    success "Docker Desktop installed"
  fi

  # Launch Docker Desktop
  if ! docker info &>/dev/null 2>&1; then
    info "Starting Docker Desktop..."
    open -a Docker

    echo ""
    echo -e "  ${YELLOW}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${YELLOW}║${RESET}                                                            ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}  ${BOLD}Action Required:${RESET} Docker Desktop has opened.              ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}                                                            ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}  If this is your first time, please:                       ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}    1. Accept the license agreement in the Docker window    ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}    2. Enter your password if prompted                      ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}    3. Wait for Docker to finish starting                   ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}                                                            ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}  The installer will continue automatically once Docker     ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}  is ready...                                               ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}║${RESET}                                                            ${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Poll for Docker to be ready
    local elapsed=0
    local timeout=180  # 3 minutes
    while ! docker info &>/dev/null 2>&1; do
      if (( elapsed >= timeout )); then
        fail "Docker Desktop did not start within ${timeout} seconds."
        echo ""
        warn "Please open Docker Desktop manually, accept the license, and re-run this installer."
        exit 1
      fi
      printf "\r  ${DIM}Waiting for Docker Desktop... (${elapsed}s)${RESET}  "
      sleep 3
      elapsed=$((elapsed + 3))
    done
    printf "\r                                                      \r"
  fi

  success "Docker Desktop is running"

  # Check Docker Compose v2
  if ! docker compose version &>/dev/null; then
    fail "Docker Compose v2 is not available. Please update Docker Desktop."
    exit 1
  fi
  success "Docker Compose v2 available"

  # Check Docker resource allocation
  local docker_mem
  docker_mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
  if [[ -n "$docker_mem" ]] && (( docker_mem < 4294967296 )); then  # 4 GB
    local docker_mem_formatted
    docker_mem_formatted=$(format_bytes "$docker_mem")
    warn "Docker is allocated only ${docker_mem_formatted} of memory."
    warn "We recommend at least 8 GB for N.O.M.A.D. with AI features."
    warn "Increase it in: Docker Desktop → Settings → Resources"
  fi

  save_state "docker"
}

install_ollama() {
  if step_done "ollama"; then return 0; fi

  if command -v ollama &>/dev/null; then
    success "Ollama — already installed"
  else
    if dry "Install Ollama via brew"; then save_state "ollama"; return 0; fi
    info "Installing Ollama (for local AI with Metal GPU acceleration)..."
    brew install ollama

    if ! command -v ollama &>/dev/null; then
      fail "Ollama installation failed."
      exit 1
    fi
    success "Ollama installed"
  fi

  # Start Ollama service
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    info "Starting Ollama..."
    brew services start ollama 2>/dev/null || ollama serve &>/dev/null &

    # Wait for Ollama to be ready
    local elapsed=0
    while ! curl -sf http://localhost:11434/api/tags &>/dev/null; do
      if (( elapsed >= 30 )); then
        warn "Ollama didn't start automatically. You can start it later with: ollama serve"
        break
      fi
      sleep 2
      elapsed=$((elapsed + 2))
    done
  fi

  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    success "Ollama is running (Metal GPU acceleration enabled)"
  fi

  save_state "ollama"
}

install_dependencies() {
  step "Step 3 — Installing Dependencies"

  install_xcode_clt
  install_homebrew
  install_rosetta
  install_docker
  install_ollama
}

###################################################################################################################################################################################################
#                                                                                   Directory & Compose Setup                                                                                     #
###################################################################################################################################################################################################

setup_directories() {
  if step_done "directories"; then return 0; fi

  step "Step 4 — Setting Up N.O.M.A.D."

  if dry "Create directories at ${NOMAD_DIR}/{storage,mysql,redis}"; then
    save_state "directories"
    return 0
  fi

  # Create directory structure
  info "Creating directory structure at ${NOMAD_DIR}..."
  mkdir -p "${NOMAD_DIR}"/{storage/logs,storage/kb_uploads,mysql,redis}

  # Suppress Spotlight indexing on large data
  touch "${NOMAD_DIR}/.metadata_never_index"
  touch "${NOMAD_DIR}/storage/.metadata_never_index"

  success "Directory structure created"
  save_state "directories"
}

setup_compose() {
  if step_done "compose"; then return 0; fi

  local compose_file="${NOMAD_DIR}/compose.yml"

  if $DRY_RUN; then
    info "[dry-run] Would download compose file and inject credentials"
    dry "Generate secure passwords for APP_KEY, DB_PASSWORD, MYSQL_ROOT_PASSWORD"
    dry "Substitute NOMAD_DIR_PLACEHOLDER → ${NOMAD_DIR}"
    dry "Substitute URL=replaceme → URL=http://$(get_local_ip):8080"
    success "[dry-run] Compose configuration validated"
    save_state "compose"
    return 0
  fi

  info "Downloading macOS Docker Compose configuration..."

  # Download macOS-specific compose file
  if ! curl -fsSL "$COMPOSE_FILE_URL" -o "$compose_file" 2>/dev/null; then
    # Fallback: generate it locally
    info "Generating compose configuration locally..."
    generate_macos_compose "$compose_file"
  fi

  # Generate secure credentials
  local app_key
  app_key=$(generate_password)
  local db_root_password
  db_root_password=$(generate_password)
  local db_user_password
  db_user_password=$(generate_password)
  local redis_password
  redis_password=$(generate_password)
  local local_ip
  local_ip=$(get_local_ip)

  # If MySQL data directory exists from a previous install, remove it
  # (MySQL only initializes credentials on first startup with empty data dir)
  if [[ -d "${NOMAD_DIR}/mysql/data" ]] || [[ -d "${NOMAD_DIR}/mysql" && "$(ls -A "${NOMAD_DIR}/mysql" 2>/dev/null)" ]]; then
    warn "Removing old MySQL data to ensure credentials match..."
    rm -rf "${NOMAD_DIR}/mysql"
    mkdir -p "${NOMAD_DIR}/mysql"
  fi

  # Escape sed special characters in NOMAD_DIR (handles &, \, / in volume names)
  local escaped_dir
  escaped_dir=$(printf '%s\n' "$NOMAD_DIR" | sed 's/[&\\/]/\\&/g')

  # Inject credentials into compose file (BSD sed compatible)
  sed -i '' "s|NOMAD_DIR_PLACEHOLDER|${escaped_dir}|g" "$compose_file"
  sed -i '' "s|URL=replaceme|URL=http://${local_ip}:8080|g" "$compose_file"
  sed -i '' "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file"
  sed -i '' "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file"
  sed -i '' "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file"
  sed -i '' "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file"
  sed -i '' "s|replaceme_redis|${redis_password}|g" "$compose_file"

  # Restrict permissions on compose file (contains credentials)
  chmod 600 "$compose_file"
  chmod 700 "${NOMAD_DIR}"

  success "Docker Compose configured with secure credentials"
  save_state "compose"
}

# Fallback: generate compose file locally if download fails
generate_macos_compose() {
  local file="$1"
  cat > "$file" << 'COMPOSE_EOF'
# Project N.O.M.A.D. — macOS Docker Compose Configuration
# Security hardened: localhost-only ports, Redis auth, network segmentation
name: project-nomad
services:
  admin:
    image: ghcr.io/crosstalk-solutions/project-nomad:latest
    pull_policy: always
    container_name: nomad_admin
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - NOMAD_DIR_PLACEHOLDER/storage:/app/storage
      - /var/run/docker.sock:/var/run/docker.sock
      - nomad-update-shared:/app/update-shared
    environment:
      - NODE_ENV=production
      - PORT=8080
      - LOG_LEVEL=info
      - APP_KEY=replaceme
      - HOST=0.0.0.0
      - URL=replaceme
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_DATABASE=nomad
      - DB_USER=nomad_user
      - DB_PASSWORD=replaceme
      - DB_NAME=nomad
      - DB_SSL=false
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=replaceme_redis
      - DISABLE_COMPRESSION=false
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - frontend
      - backend
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
  dozzle:
    image: amir20/dozzle:v10.0
    container_name: nomad_dozzle
    restart: unless-stopped
    ports:
      - "127.0.0.1:9999:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DOZZLE_ENABLE_ACTIONS=false
      - DOZZLE_ENABLE_SHELL=false
    networks:
      - frontend
  mysql:
    image: mysql:8.0
    container_name: nomad_mysql
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=replaceme
      - MYSQL_DATABASE=nomad
      - MYSQL_USER=nomad_user
      - MYSQL_PASSWORD=replaceme
    volumes:
      - NOMAD_DIR_PLACEHOLDER/mysql:/var/lib/mysql
    networks:
      - backend
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 10
  redis:
    image: redis:7-alpine
    container_name: nomad_redis
    restart: unless-stopped
    command: ["redis-server", "--requirepass", "replaceme_redis"]
    volumes:
      - NOMAD_DIR_PLACEHOLDER/redis:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "replaceme_redis", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
  updater:
    image: ghcr.io/crosstalk-solutions/project-nomad-sidecar-updater:latest
    pull_policy: always
    container_name: nomad_updater
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - NOMAD_DIR_PLACEHOLDER:NOMAD_DIR_PLACEHOLDER
      - nomad-update-shared:/shared
    networks:
      - frontend

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge

volumes:
  nomad-update-shared:
    driver: local
COMPOSE_EOF
}

###################################################################################################################################################################################################
#                                                                                   Download Helper Scripts                                                                                       #
###################################################################################################################################################################################################

download_helpers() {
  if step_done "helpers"; then return 0; fi

  if dry "Download start_nomad.sh and stop_nomad.sh to ${NOMAD_DIR}"; then
    save_state "helpers"
    return 0
  fi

  info "Downloading helper scripts..."

  local start_script="${NOMAD_DIR}/start_nomad.sh"
  local stop_script="${NOMAD_DIR}/stop_nomad.sh"

  # Download or generate start script
  if ! curl -fsSL "$START_SCRIPT_URL" -o "$start_script" 2>/dev/null; then
    generate_start_script "$start_script"
  fi
  chmod +x "$start_script"

  # Download or generate stop script
  if ! curl -fsSL "$STOP_SCRIPT_URL" -o "$stop_script" 2>/dev/null; then
    generate_stop_script "$stop_script"
  fi
  chmod +x "$stop_script"

  success "Helper scripts installed"
  save_state "helpers"
}

generate_start_script() {
  cat > "$1" << 'START_EOF'
#!/bin/bash
# Start Project N.O.M.A.D. on macOS

echo "Starting Project N.O.M.A.D..."

# Ensure Docker Desktop is running
if ! docker info &>/dev/null 2>&1; then
  echo "Starting Docker Desktop..."
  open -a Docker
  while ! docker info &>/dev/null 2>&1; do
    sleep 2
  done
  echo "Docker Desktop is ready."
fi

# Start Ollama (native, for Metal GPU)
if command -v ollama &>/dev/null; then
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "Starting Ollama..."
    brew services start ollama 2>/dev/null || ollama serve &>/dev/null &
    sleep 3
  fi
  echo "✓ Ollama is running"
fi

# Start N.O.M.A.D. containers
echo "Starting N.O.M.A.D. containers..."
containers=$(docker ps -a --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
  echo "No containers found. Running docker compose..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  docker compose -p project-nomad -f "${SCRIPT_DIR}/compose.yml" up -d
else
  for container in $containers; do
    echo "Starting: $container"
    docker start "$container" >/dev/null 2>&1 && echo "  ✓ $container" || echo "  ✗ $container"
  done
fi

LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
echo ""
echo "N.O.M.A.D. is running!"
echo "  → http://localhost:8080"
echo "  → http://${LOCAL_IP}:8080"
START_EOF
}

generate_stop_script() {
  cat > "$1" << 'STOP_EOF'
#!/bin/bash
# Stop Project N.O.M.A.D. on macOS

echo "Stopping Project N.O.M.A.D..."

# Stop containers
containers=$(docker ps --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
  echo "No running N.O.M.A.D. containers found."
else
  for container in $containers; do
    echo "Stopping: $container"
    docker stop "$container" >/dev/null 2>&1 && echo "  ✓ $container" || echo "  ✗ $container"
  done
fi

# Optionally stop Ollama
echo ""
read -p "Also stop Ollama? (y/N): " choice
case "$choice" in
  y|Y)
    brew services stop ollama 2>/dev/null
    pkill -f "ollama serve" 2>/dev/null
    echo "✓ Ollama stopped"
    ;;
esac

echo ""
echo "N.O.M.A.D. has been stopped."
STOP_EOF
}

###################################################################################################################################################################################################
#                                                                                   Launch Services                                                                                               #
###################################################################################################################################################################################################

launch_services() {
  if step_done "launched"; then return 0; fi

  step "Step 5 — Launching N.O.M.A.D."

  if $DRY_RUN; then
    dry "docker compose -p project-nomad pull"
    dry "docker compose -p project-nomad up -d"
    dry "Wait for health check at http://localhost:8080/api/health"
    success "[dry-run] Services would be launched"
    save_state "launched"
    return 0
  fi

  info "Pulling Docker images (this may take a few minutes on first run)..."
  docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" pull

  info "Starting containers..."
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    fail "Failed to start containers."
    echo ""
    warn "Check the logs with: docker compose -p project-nomad -f ${NOMAD_DIR}/compose.yml logs"
    exit 1
  fi

  # Wait for health check
  info "Waiting for N.O.M.A.D. to be ready..."
  local elapsed=0
  local timeout=120
  while ! curl -sf http://localhost:8080/api/health &>/dev/null; do
    if (( elapsed >= timeout )); then
      warn "N.O.M.A.D. hasn't responded within ${timeout}s. It may still be starting up."
      warn "Check status with: docker ps --filter 'name=nomad_'"
      break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  if curl -sf http://localhost:8080/api/health &>/dev/null; then
    success "N.O.M.A.D. is running and healthy!"
  fi

  save_state "launched"
}

###################################################################################################################################################################################################
#                                                                                  AI Model Recommendation                                                                                        #
###################################################################################################################################################################################################

# Returns the best Ollama model for the given unified memory (in GB)
get_recommended_model() {
  local mem_gb=$1

  if (( mem_gb >= 128 )); then
    echo "qwen3.5:122b-a10b|~81 GB|122B params (10B active MoE)|20-35 tok/s|Massive knowledge depth, 10B active for fast inference"
  elif (( mem_gb >= 96 )); then
    echo "deepseek-r1:70b|~43 GB|70B params|12-18 tok/s|Best-in-class reasoning for complex document analysis"
  elif (( mem_gb >= 64 )); then
    echo "deepseek-r1:70b|~43 GB|70B params|12-18 tok/s|Superior reasoning engine with comfortable headroom"
  elif (( mem_gb >= 48 )); then
    echo "deepseek-r1:32b|~20 GB|32B params|25-40 tok/s|RL-trained reasoning, excellent for RAG Q&A"
  elif (( mem_gb >= 36 )); then
    echo "qwen3.5:35b-a3b|~24 GB|35B params (3B active MoE)|50-80 tok/s|Best value — 35B knowledge at 3B speed"
  elif (( mem_gb >= 32 )); then
    echo "qwen3.5:35b-a3b|~24 GB|35B params (3B active MoE)|50-80 tok/s|MoE architecture: fast and capable"
  elif (( mem_gb >= 24 )); then
    echo "qwen3:30b-a3b|~19 GB|30B params (3B active MoE)|50-84 tok/s|MoE punches way above its weight class"
  elif (( mem_gb >= 18 )); then
    echo "qwen3:14b|~9.3 GB|14B params|30-45 tok/s|Sweet spot for 18GB — strong reasoning and RAG"
  elif (( mem_gb >= 16 )); then
    echo "qwen3:8b|~5.2 GB|8B params|45-65 tok/s|Fast and capable with plenty of headroom"
  else
    echo "qwen3:4b|~2.5 GB|4B params|55-80 tok/s|Best sub-5B model, fits tight memory budgets"
  fi
}

configure_ollama_hint() {
  step "Step 6 — AI Setup"

  # Detect unified memory
  local total_mem_bytes
  total_mem_bytes=$(sysctl -n hw.memsize 2>/dev/null)
  local total_mem_gb=$(( total_mem_bytes / 1073741824 ))

  # Get model recommendation
  local recommendation
  recommendation=$(get_recommended_model "$total_mem_gb")

  local model_tag download_size model_desc speed reason
  IFS='|' read -r model_tag download_size model_desc speed reason <<< "$recommendation"

  echo -e "  ${BOLD}Your Mac: ${total_mem_gb} GB unified memory${RESET}"
  echo ""
  echo -e "  ${BOLD}${WHITE}Recommended AI model:${RESET}"
  echo ""
  echo -e "    ${CYAN}${model_tag}${RESET}"
  echo -e "    ${DIM}${model_desc} · ${download_size} download · ${speed}${RESET}"
  echo -e "    ${DIM}${reason}${RESET}"
  echo ""

  # Check if any Ollama models are already installed
  local installed_models=""
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    installed_models=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | head -5)
  fi

  if [[ -n "$installed_models" ]]; then
    info "You already have models installed:"
    echo "$installed_models" | while read -r m; do
      echo -e "    ${DIM}• ${m}${RESET}"
    done
    echo ""
  fi

  if $DRY_RUN; then
    dry "Would offer to pull ${model_tag}"
  else
    echo -ne "  Download ${BOLD}${model_tag}${RESET} now? ${DIM}(y/N)${RESET} "
    local pull_choice
    prompt pull_choice
    case "$pull_choice" in
      y|Y)
        info "Pulling ${model_tag} (this may take a while)..."
        if ollama pull "$model_tag"; then
          success "Model ${model_tag} downloaded!"
        else
          warn "Download failed. You can pull it later with: ollama pull ${model_tag}"
        fi
        ;;
      *)
        info "Skipped. Pull it anytime with: ${CYAN}ollama pull ${model_tag}${RESET}"
        ;;
    esac
  fi

  echo ""
  divider
  echo ""
  echo -e "  ${BOLD}Connect N.O.M.A.D. to Ollama:${RESET}"
  echo ""
  echo "  After opening the N.O.M.A.D. interface, go to:"
  echo -e "    ${BOLD}Settings → Models → Remote Ollama Server${RESET}"
  echo "  and set the URL to:"
  echo -e "    ${CYAN}http://host.docker.internal:11434${RESET}"
  echo ""
  echo "  This connects the containerized N.O.M.A.D. to your native Ollama instance,"
  echo "  giving AI full access to your Apple Silicon GPU."
  echo ""
}

###################################################################################################################################################################################################
#                                                                                     Success Message                                                                                             #
###################################################################################################################################################################################################

success_message() {
  local local_ip
  local_ip=$(get_local_ip)

  if $DRY_RUN; then
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}   ${BOLD}${WHITE}Dry-Run Complete — All checks passed!${RESET}                       ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}   The installer validated:                                   ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}     - macOS version and architecture                         ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}     - Disk space and network connectivity                    ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}     - External drive detection and filesystem checks         ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}     - Dependency detection (brew, docker, ollama)             ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}     - Compose file generation and credential injection       ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}   To install for real, run without --dry-run                 ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    return 0
  fi

  # Clean up install state file (complete install)
  rm -f "$INSTALL_STATE_FILE" 2>/dev/null

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${BOLD}${WHITE}Installation Complete!${RESET}                                       ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   Open N.O.M.A.D. in your browser:                           ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${CYAN}→ http://localhost:8080${RESET}                                    ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${CYAN}→ http://${local_ip}:8080${RESET}$(printf '%*s' $((29 - ${#local_ip})) '')${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   Install location: ${DIM}${NOMAD_DIR}${RESET}$(printf '%*s' $((32 - ${#NOMAD_DIR})) '')${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   Helper commands:                                           ${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${DIM}${NOMAD_DIR}/start_nomad.sh${RESET}$(printf '%*s' $((37 - ${#NOMAD_DIR})) '')${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}   ${DIM}${NOMAD_DIR}/stop_nomad.sh${RESET}$(printf '%*s' $((38 - ${#NOMAD_DIR})) '')${GREEN}║${RESET}"
  echo -e "${GREEN}║${RESET}                                                              ${GREEN}║${RESET}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo "  Thank you for supporting Project N.O.M.A.D.!"
  echo ""
}

###################################################################################################################################################################################################
#                                                                                        Main                                                                                                     #
###################################################################################################################################################################################################

# Wrap everything in main() for curl|bash safety (ensures full script is downloaded before execution)
main() {
  banner
  preflight_checks
  accept_license
  select_install_location
  install_dependencies
  setup_directories
  setup_compose
  download_helpers
  launch_services
  configure_ollama_hint
  success_message
}

main "$@"
