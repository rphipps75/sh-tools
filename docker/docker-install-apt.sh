#!/bin/bash

LOGGING_SRC=${LOGGING_SRC}
# 1. Fallback to PROFILE_SCRIPTS_SH if LOGGING_SRC is empty/unset
LOGGING_SRC="${LOGGING_SRC:-$PROFILE_SCRIPTS_SH}"
# 2. If it is still empty/unset, default to the current directory
LOGGING_SRC="${LOGGING_SRC:-./}"

# Ensure the logging utility framework path resolution is stable
if [ -f "${LOGGING_SRC}/_logging.sh" ]; then
  source "${LOGGING_SRC}/_logging.sh"
else
  # Minimal fallback logging mechanics if infrastructure is missing
  log_info() { echo -e "[INFO] $*"; }
  log_warn() { echo -e "[WARN] $*"; }
  log_fail() { echo -e "[FAIL] $*" >&2; }
  log_blank() { echo ""; }
fi
log_blank

SILENT=false
for arg in "$@"; do
  [[ "$arg" == "--silent" ]] && SILENT=true
done

pause() { [[ $SILENT == false ]] && pause; }

# 1
log_info "Checking if systemd is enabled (You should see systemd)..."
ps --pid 1
log_blank
pause

# 2
log_info "Removing any old Docker packages..."
sudo apt remove -y docker docker-engine docker.io containerd runc
log_blank
pause

# 3
log_info "Installing required dependencies..."
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  gnupg
log_blank
pause

# 4
log_info "Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
log_blank
pause

# 5
log_info "Setting up the repository / Adding the Docker APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
log_blank
pause

# 6
log_info "Installing Docker Engine..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
log_blank
pause

# 7
log_info "Starting and enabling Docker..."
sudo systemctl start docker
sudo systemctl enable docker
log_blank
pause

# 8
log_info "Adding current user to the docker group..."
sudo usermod -aG docker $USER
log_info "Allowing Docker without sudo (recommended)..."
newgrp docker
log_blank
pause

# 9
log_info "Verifying installation..."
docker --version
docker compose version
sudo systemctl is-active docker
log_blank

log_info "Done."
log_blank