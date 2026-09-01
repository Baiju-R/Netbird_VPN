#!/usr/bin/env bash

# ==============================================================
# TeamLogger Linux Deployment Wrapper
#
# Usage:
#   sudo ./deploy_teamlogger.sh "<EMPLOYEE_NAME>" "<EMPLOYEE_ID>"
#
# Example:
#   sudo ./deploy_teamlogger.sh "John Doe" "EMP001"
#
# IMPORTANT:
# - Run this script as root.
# - Do NOT provide Linux passwords as command-line arguments.
# - The TeamLogger installation key should be supplied securely
#   through the environment:
#
#     TEAMLOGGER_INSTALLATION_KEY='YOUR_KEY' \
#       sudo -E ./deploy_teamlogger.sh "John Doe" "EMP001"
#
# ==============================================================

set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"

TEAMLOGGER_INSTALLER_URL="https://d1ssc3nxri43sl.cloudfront.net/install_tlauto_silent.sh"
TEAMLOGGER_BINARY_URL="${TEAMLOGGER_BINARY_URL:-https://downloads.teamlogger.com/TLAutoLinux.x64}"

INSTALLER_DIR="/opt/teamlogger-deploy"
INSTALLER_PATH="${INSTALLER_DIR}/install_tlauto_silent.sh"

LOG_DIR="/var/log/teamlogger-deploy"
LOG_FILE="${LOG_DIR}/deployment.log"

BACKUP_DIR="/var/backups/teamlogger-deploy/$(date +%Y%m%d_%H%M%S)"

EMPLOYEE_NAME="${1:-}"
EMPLOYEE_ID="${2:-}"

INSTALLATION_KEY="${TEAMLOGGER_INSTALLATION_KEY:-}"

FAILED=0


# ==============================================================
# Logging
# ==============================================================

mkdir -p "$LOG_DIR"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1


info() {
    echo "[INFO] $*"
}

success() {
    echo "[SUCCESS] $*"
}

warn() {
    echo "[WARNING] $*"
}

error() {
    echo "[ERROR] $*" >&2
}


die() {
    error "$*"
    error "Deployment stopped."
    exit 1
}


# ==============================================================
# Error handling
# ==============================================================

trap 'error "Unexpected error at line $LINENO. Command: $BASH_COMMAND"' ERR


# ==============================================================
# Header
# ==============================================================

clear 2>/dev/null || true

cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║              TEAMLOGGER LINUX DEPLOYMENT                    ║
║                     Deployment Wrapper                      ║
╚══════════════════════════════════════════════════════════════╝

EOF

info "Deployment version: ${SCRIPT_VERSION}"


# ==============================================================
# Argument validation
# ==============================================================

if [[ $EUID -ne 0 ]]; then
    die "This script must be executed as root."
fi

if [[ -z "$EMPLOYEE_NAME" ]]; then
    die "Employee name is required.

Usage:
  sudo ./deploy_teamlogger.sh \"Employee Name\" \"EMP001\""
fi

if [[ -z "$EMPLOYEE_ID" ]]; then
    die "Employee ID is required."
fi


# ==============================================================
# Validate employee ID
# ==============================================================

if ! [[ "$EMPLOYEE_ID" =~ ^[A-Za-z0-9_/-]+$ ]]; then
    die "Invalid Employee ID: $EMPLOYEE_ID"
fi


# ==============================================================
# Validate installation key
# ==============================================================

if [[ -z "$INSTALLATION_KEY" ]]; then

    cat <<'EOF'

[ERROR] TeamLogger Installation Key is not available.

For security, the Installation Key is not stored directly in this script.

Supply it as an environment variable:

  TEAMLOGGER_INSTALLATION_KEY='YOUR_KEY' \
    sudo -E ./deploy_teamlogger.sh "Employee Name" "EMP001"

EOF

    exit 1
fi


# ==============================================================
# Basic OS detection
# ==============================================================

info "Detecting operating system..."

if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release not found."
fi

source /etc/os-release

info "Operating system: ${PRETTY_NAME:-unknown}"

if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "This deployment has been designed primarily for Ubuntu."
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"

info "Architecture: ${ARCH:-unknown}"

case "$ARCH" in
    amd64|arm64)
        success "Supported architecture detected."
        ;;
    *)
        die "Unsupported architecture: $ARCH"
        ;;
esac


# ==============================================================
# Create directories
# ==============================================================

info "Preparing deployment directories..."

mkdir -p "$INSTALLER_DIR"
mkdir -p "$BACKUP_DIR"

chmod 700 "$INSTALLER_DIR"
chmod 700 "$BACKUP_DIR"


# ==============================================================
# Locate employee
# ==============================================================

info "Checking employee account..."

if id "$EMPLOYEE_ID" >/dev/null 2>&1; then

    TARGET_USER="$EMPLOYEE_ID"

else

    # Try username lookup based on supplied employee ID.
    if getent passwd "$EMPLOYEE_ID" >/dev/null 2>&1; then
        TARGET_USER="$EMPLOYEE_ID"
    else
        warn "Employee ID '$EMPLOYEE_ID' is not a local Linux username."
        warn "The TeamLogger Employee ID will still be passed to the vendor installer."
        TARGET_USER=""
    fi

fi

if [[ -n "$TARGET_USER" ]]; then

    TARGET_UID="$(id -u "$TARGET_USER")"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    info "Local employee account: $TARGET_USER"
    info "UID: $TARGET_UID"
    info "Home: $TARGET_HOME"

else

    TARGET_UID=""
    TARGET_HOME=""

    warn "Local Linux employee account could not be resolved automatically."
fi


# ==============================================================
# Package manager
# ==============================================================

if ! command -v apt-get >/dev/null 2>&1; then
    die "apt-get is required."
fi


# ==============================================================
# Root package installation
# ==============================================================

info "Updating package repositories..."

DEBIAN_FRONTEND=noninteractive apt-get update


install_package() {

    local package="$1"

    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
        | grep -q "install ok installed"; then

        success "$package already installed."

    else

        info "Installing $package..."

        DEBIAN_FRONTEND=noninteractive \
            apt-get install -y "$package"

        success "$package installed."
    fi
}


package_is_installed() {
    local package_name="$1"

    dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null \
        | grep -q "install ok installed"
}


check_portal_dependencies() {
    info "Checking PipeWire and desktop portal prerequisites..."

    if command -v pipewire >/dev/null 2>&1; then
        success "PipeWire executable available."
    else
        error "PipeWire executable is not available."
        return 1
    fi

    if command -v wireplumber >/dev/null 2>&1; then
        success "WirePlumber executable available."
    else
        error "WirePlumber executable is not available."
        return 1
    fi

    if package_is_installed "xdg-desktop-portal"; then
        success "xdg-desktop-portal package is installed."
    else
        error "xdg-desktop-portal package is not installed."
        return 1
    fi

    if package_is_installed "xdg-desktop-portal-gnome"; then
        success "xdg-desktop-portal-gnome package is installed."
    else
        error "xdg-desktop-portal-gnome package is not installed."
        return 1
    fi

    if package_is_installed "xdg-desktop-portal-gtk"; then
        success "xdg-desktop-portal-gtk package is installed."
    else
        error "xdg-desktop-portal-gtk package is not installed."
        return 1
    fi

    if package_is_installed "libpipewire-0.3-0t64" || package_is_installed "libpipewire-0.3-0"; then
        success "libpipewire is installed."
    else
        error "libpipewire is not installed."
        return 1
    fi

    success "PipeWire and desktop portal prerequisites are installed."
    return 0
}


check_teamlogger_binary_endpoint() {
    if curl -L \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 15 \
        --range 0-1024 \
        "$TEAMLOGGER_BINARY_URL" \
        -o /dev/null; then

        success "TeamLogger binary endpoint is reachable."
        return 0

    else

        warn "TeamLogger binary endpoint could not be pre-validated."
        warn "The actual TeamLogger installer download will still be tested during installation."
        return 0
    fi
}


info "Installing TeamLogger prerequisite packages..."

REQUIRED_PACKAGES=(
    ca-certificates
    curl
    wget
    unzip
    jq
    dbus
    dbus-user-session
    xorg
    x11-xserver-utils
    xdotool
    xrandr
    maim
    xprintidle
    pipewire
    libpipewire-0.3-0
    wireplumber
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
)

for package in "${REQUIRED_PACKAGES[@]}"; do

    if apt-cache show "$package" >/dev/null 2>&1; then
        install_package "$package"
    else
        warn "Package '$package' is not available from current repositories."
    fi

done


# ==============================================================
# Verify critical packages
# ==============================================================

info "Validating installed prerequisites..."

CRITICAL_COMMANDS=(
    curl
    wget
    jq
    xdotool
    xrandr
    maim
    xprintidle
)

for command_name in "${CRITICAL_COMMANDS[@]}"; do

    if command -v "$command_name" >/dev/null 2>&1; then
        success "$command_name: available"
    else
        warn "$command_name: NOT available"
        FAILED=1
    fi

done


# ==============================================================
# Xorg validation
# ==============================================================

info "Checking Xorg..."

if command -v Xorg >/dev/null 2>&1; then
    success "Xorg is installed."
else
    FAILED=1
    error "Xorg is not available."
fi


# ==============================================================
# GDM configuration
# ==============================================================

GDM_CONFIG="/etc/gdm3/custom.conf"

if [[ -f "$GDM_CONFIG" ]]; then

    info "Backing up GDM configuration..."

    cp -a "$GDM_CONFIG" "$BACKUP_DIR/custom.conf"

else

    warn "GDM configuration not found."
fi


# ==============================================================
# Configure GDM for X11
# ==============================================================

if [[ -f "$GDM_CONFIG" ]]; then

    info "Checking GDM Wayland configuration..."

    if grep -qE '^[[:space:]]*WaylandEnable=' "$GDM_CONFIG"; then

        sed -i \
            's/^[[:space:]]*WaylandEnable=.*/WaylandEnable=false/' \
            "$GDM_CONFIG"

    else

        printf '\nWaylandEnable=false\n' >> "$GDM_CONFIG"

    fi

    success "GDM configured to prefer X11."

fi


# ==============================================================
# Current graphical session
# ==============================================================

info "Checking graphical session..."

SESSION_TYPE=""

if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
    SESSION_TYPE="$XDG_SESSION_TYPE"
else

    SESSION_TYPE="$(
        loginctl list-sessions --no-legend 2>/dev/null \
        | awk 'NR==1 {print $3}' \
        || true
    )"

fi

info "Detected session type: ${SESSION_TYPE:-unknown}"


# ==============================================================
# Active graphical session detection
# ==============================================================

info "Detecting active graphical users..."

GRAPHICAL_USERS="$(
    loginctl list-sessions --no-legend 2>/dev/null \
        | while read -r session_id uid user seat rest; do

            [[ -z "$user" ]] && continue

            session_type="$(
                loginctl show-session "$session_id" \
                -p Type --value 2>/dev/null || true
            )"

            if [[ "$session_type" == "x11" ||
                  "$session_type" == "wayland" ]]; then

                echo "$user"

            fi

        done \
        | sort -u
)"


if [[ -n "$GRAPHICAL_USERS" ]]; then

    success "Graphical session detected:"
    echo "$GRAPHICAL_USERS"

else

    warn "No active graphical user session detected."

    warn "TeamLogger's installer requires the employee to be logged into the desktop."

fi


# ==============================================================
# .NET environment preparation
# ==============================================================

if [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]]; then

    info "Preparing employee .NET environment..."

    BASHRC="$TARGET_HOME/.bashrc"

    if ! grep -q 'DOTNET_BUNDLE_EXTRACT_BASE_DIR' "$BASHRC" 2>/dev/null; then

        cat >> "$BASHRC" <<'EOF'

# TeamLogger / .NET bundle extraction
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotnet_bundle"

EOF

        chown "$TARGET_USER:$TARGET_USER" "$BASHRC"

        success ".NET environment prepared."

    else

        success ".NET environment already configured."

    fi

fi


# ==============================================================
# Download official TeamLogger installer
# ==============================================================

info "Downloading official TeamLogger installer..."

TMP_INSTALLER="${INSTALLER_PATH}.tmp"

rm -f "$TMP_INSTALLER"

curl \
    --fail \
    --location \
    --show-error \
    --retry 3 \
    --connect-timeout 15 \
    "$TEAMLOGGER_INSTALLER_URL" \
    -o "$TMP_INSTALLER"

chmod 755 "$TMP_INSTALLER"

mv "$TMP_INSTALLER" "$INSTALLER_PATH"

success "TeamLogger installer downloaded."


# ==============================================================
# Basic installer validation
# ==============================================================

info "Validating TeamLogger installer..."

if [[ ! -s "$INSTALLER_PATH" ]]; then
    die "Downloaded installer is empty."
fi

if ! head -n 1 "$INSTALLER_PATH" | grep -qE '^#!.*(bash|sh)'; then
    warn "Installer does not have a conventional shell shebang."
fi

if grep -q "Installation Key Authentication" "$INSTALLER_PATH"; then
    success "Expected TeamLogger installer detected."
else
    warn "Installer signature text was not detected."
fi


# ==============================================================
# Pre-install prerequisite validation
# ==============================================================

echo
echo "=============================================================="
echo "  PRE-INSTALL VALIDATION"
echo "=============================================================="

VALIDATION_FAILED=0


check_command() {

    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        printf '[PASS] %-30s\n' "$command_name"
    else
        printf '[FAIL] %-30s\n' "$command_name"
        VALIDATION_FAILED=1
    fi

}


check_command curl
check_command wget
check_command xdotool
check_command xrandr
check_command maim
check_command xprintidle
check_command dbus-launch


if command -v Xorg >/dev/null 2>&1; then
    echo "[PASS] Xorg"
else
    echo "[FAIL] Xorg"
    VALIDATION_FAILED=1
fi


if ! check_portal_dependencies; then
    echo
    error "Desktop portal prerequisites are incomplete."
    error "TeamLogger installation has NOT been started."
    error "See:"
    error "  $LOG_FILE"

    exit 1
fi

check_teamlogger_binary_endpoint

if [[ "$VALIDATION_FAILED" -ne 0 ]]; then

    echo
    error "Critical prerequisites are missing."
    error "TeamLogger installation has NOT been started."
    error "See:"
    error "  $LOG_FILE"

    exit 1

fi


success "Pre-install validation passed."


# ==============================================================
# Security: don't expose installation key in process arguments
# ==============================================================

KEY_FILE="${INSTALLER_DIR}/.installation_key"

umask 077

printf '%s' "$INSTALLATION_KEY" > "$KEY_FILE"

chmod 600 "$KEY_FILE"


# ==============================================================
# Generate user-stage helper
# ==============================================================

USER_STAGE="${INSTALLER_DIR}/run-teamlogger-user-stage.sh"

cat > "$USER_STAGE" <<'USERSTAGE'
#!/usr/bin/env bash

set -Eeuo pipefail

INSTALLER="/opt/teamlogger-deploy/install_tlauto_silent.sh"
KEY_FILE="/opt/teamlogger-deploy/.installation_key"

EMPLOYEE_NAME="$1"
EMPLOYEE_ID="$2"

if [[ ! -f "$INSTALLER" ]]; then
    echo "[ERROR] TeamLogger installer not found."
    exit 1
fi

if [[ ! -r "$KEY_FILE" ]]; then
    echo "[ERROR] Installation key is unavailable."
    exit 1
fi

INSTALLATION_KEY="$(cat "$KEY_FILE")"

echo
echo "=============================================================="
echo " TeamLogger Employee Installation"
echo "=============================================================="
echo
echo "Employee : $EMPLOYEE_NAME"
echo "ID       : $EMPLOYEE_ID"
echo
echo "The official TeamLogger installer will now run."
echo

# IMPORTANT:
# The vendor installer requires execution from the employee's
# graphical session. It is therefore intentionally executed as
# the logged-in employee rather than root.
#
# The installer itself will request its required information.

exec "$INSTALLER"
USERSTAGE

chmod 700 "$USER_STAGE"


# ==============================================================
# Final preparation report
# ==============================================================

echo
echo "=============================================================="
echo "  ROOT PREPARATION COMPLETED"
echo "=============================================================="

success "System dependencies prepared."
success "Xorg checked."
success "GDM configuration prepared."
success "Screenshot dependencies checked."
success "PipeWire/portal dependencies checked."
success "TeamLogger installer downloaded."
success "Pre-install validation passed."

echo
echo "Employee:"
echo "  Name : $EMPLOYEE_NAME"
echo "  ID   : $EMPLOYEE_ID"

echo
echo "Installer:"
echo "  $INSTALLER_PATH"

echo
echo "Log:"
echo "  $LOG_FILE"

echo
echo "=============================================================="
echo "  IMPORTANT"
echo "=============================================================="

cat <<'EOF'

The TeamLogger vendor installer explicitly requires the installer
to run as the logged-in employee, not as root.

This wrapper therefore does NOT:
  - store an employee Linux password
  - pass a Linux password on the command line
  - inject passwords into sudo
  - run the vendor installer as root

The machine-level preparation is complete.

If the employee is currently logged into the graphical desktop,
the official installer can now be launched in that session.

EOF


# ==============================================================
# Automatically launch only when correct employee session exists
# ==============================================================

if [[ -n "$TARGET_USER" ]]; then

    if echo "$GRAPHICAL_USERS" | grep -Fxq "$TARGET_USER"; then

        success "Employee graphical session detected: $TARGET_USER"

        # Determine an active graphical session.
        SESSION_ID="$(
            loginctl list-sessions --no-legend 2>/dev/null \
            | while read -r sid uid user seat rest; do

                [[ "$user" != "$TARGET_USER" ]] && continue

                type="$(
                    loginctl show-session "$sid" \
                    -p Type --value 2>/dev/null || true
                )"

                if [[ "$type" == "x11" || "$type" == "wayland" ]]; then
                    echo "$sid"
                    break
                fi

            done
        )"

        if [[ -n "$SESSION_ID" ]]; then

            success "Active employee graphical session: $SESSION_ID"

            echo
            warn "Launching the official TeamLogger installer in the employee session."
            echo

            # Run inside the user's graphical context.
            #
            # The installer itself is responsible for its own
            # interactive prompts and vendor-supported configuration.

            loginctl show-session "$SESSION_ID" \
                -p Display \
                -p Remote \
                -p Type \
                -p Name \
                -p State \
                || true

            echo
            warn "The vendor installer may request information interactively."
            echo

            # We deliberately do not fabricate DISPLAY/XAUTHORITY/
            # DBUS variables because the vendor installer has its own
            # session-detection logic.

            sudo -u "$TARGET_USER" \
                env \
                    HOME="$TARGET_HOME" \
                    USER="$TARGET_USER" \
                    LOGNAME="$TARGET_USER" \
                    "$USER_STAGE" "$EMPLOYEE_NAME" "$EMPLOYEE_ID"

        else

            warn "Could not resolve an active graphical session."
            warn "Root preparation is complete."
            warn "Run the TeamLogger installer from the employee's desktop session:"
            echo
            echo "  $INSTALLER_PATH"
            echo

        fi

    else

        warn "Employee '$TARGET_USER' is not currently logged into a graphical session."
        warn "Root preparation is complete."
        warn "The vendor installer must be run from the employee's logged-in desktop session."

    fi

else

    warn "The supplied Employee ID does not correspond to a local Linux account."
    warn "Root preparation is complete."
    warn "The TeamLogger installer must be executed by the actual employee desktop user."

fi


# ==============================================================
# Cleanup secret
# ==============================================================

rm -f "$KEY_FILE"


# ==============================================================
# Final status
# ==============================================================

echo
echo "=============================================================="
echo "  DEPLOYMENT WRAPPER FINISHED"
echo "=============================================================="

success "Root preparation stage completed."

echo
echo "Review log:"
echo "  $LOG_FILE"
echo
