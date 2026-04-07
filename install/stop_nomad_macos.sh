#!/bin/bash

# Stop Project N.O.M.A.D. on macOS
# Gracefully stops all containers and optionally stops Ollama.

RESET='\033[0m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'

echo ""
echo -e "${BOLD}Stopping Project N.O.M.A.D...${RESET}"
echo ""

# --- Stop Containers ---
containers=$(docker ps --filter "name=^nomad_" --format "{{.Names}}" 2>/dev/null)

if [ -z "$containers" ]; then
  echo -e "${YELLOW}⚠${RESET} No running N.O.M.A.D. containers found."
else
  for container in $containers; do
    echo -e "${YELLOW}▸${RESET} Stopping: $container"
    if docker stop "$container" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${RESET} $container stopped"
    else
      echo -e "  ${RED}✗${RESET} Failed to stop $container"
    fi
  done
fi

# --- Optionally Stop Ollama ---
if command -v ollama &>/dev/null; then
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo ""
    read -p "Also stop Ollama? (y/N): " choice
    case "$choice" in
      y|Y)
        brew services stop ollama 2>/dev/null
        pkill -f "ollama serve" 2>/dev/null
        echo -e "${GREEN}✓${RESET} Ollama stopped"
        ;;
      *)
        echo -e "${YELLOW}▸${RESET} Ollama left running (other apps may use it)"
        ;;
    esac
  fi
fi

echo ""
echo -e "${GREEN}N.O.M.A.D. has been stopped.${RESET}"
echo ""
