#!/bin/bash

# Start Project N.O.M.A.D. on macOS
# Handles Docker Desktop launch, native Ollama, and container startup.

RESET='\033[0m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
DIM='\033[2m'
BOLD='\033[1m'

echo ""
echo -e "${BOLD}Starting Project N.O.M.A.D...${RESET}"
echo ""

# --- Docker Desktop ---
if ! docker info &>/dev/null 2>&1; then
  echo -e "${YELLOW}▸${RESET} Starting Docker Desktop..."
  open -a Docker

  elapsed=0
  timeout=120
  while ! docker info &>/dev/null 2>&1; do
    if (( elapsed >= timeout )); then
      echo -e "${RED}✗${RESET} Docker Desktop did not start within ${timeout}s."
      echo "  Please open Docker Desktop manually and try again."
      exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
fi
echo -e "${GREEN}✓${RESET} Docker Desktop is running"

# --- Ollama (native for Metal GPU) ---
if command -v ollama &>/dev/null; then
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo -e "${YELLOW}▸${RESET} Starting Ollama..."
    brew services start ollama 2>/dev/null || ollama serve &>/dev/null &
    sleep 3
  fi
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo -e "${GREEN}✓${RESET} Ollama is running (Metal GPU)"
  else
    echo -e "${YELLOW}⚠${RESET} Ollama installed but not responding. Start manually: ollama serve"
  fi
else
  echo -e "${YELLOW}⚠${RESET} Ollama not found. Install with: brew install ollama"
fi

# --- N.O.M.A.D. Containers ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yml"

containers=$(docker ps -a --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
  if [[ -f "$COMPOSE_FILE" ]]; then
    echo -e "${YELLOW}▸${RESET} No containers found. Starting from compose file..."
    docker compose -p project-nomad -f "$COMPOSE_FILE" up -d
  else
    echo -e "${RED}✗${RESET} No containers found and no compose.yml at ${SCRIPT_DIR}."
    echo "  Please re-run the installer."
    exit 1
  fi
else
  echo -e "${YELLOW}▸${RESET} Starting N.O.M.A.D. containers..."
  for container in $containers; do
    if docker start "$container" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${RESET} $container"
    else
      echo -e "  ${RED}✗${RESET} $container"
    fi
  done
fi

# --- Ready ---
echo ""
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")

echo -e "${GREEN}N.O.M.A.D. is running!${RESET}"
echo -e "  ${CYAN}→ http://localhost:8080${RESET}"
echo -e "  ${CYAN}→ http://${LOCAL_IP}:8080${RESET}"
echo ""
