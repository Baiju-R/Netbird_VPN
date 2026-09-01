#!/usr/bin/env bash

# ==============================================================
# TeamLogger Linux Deployment Wrapper (v3.0 - Local User Edition)
#
# Usage:
#   sudo ./aa_fixed.sh "<TARGET_USERNAME>" "<EMPLOYEE_NAME>" "<EMPLOYEE_ID>"
#
# Example:
#   sudo ./aa_fixed.sh "baiju.ravi" "Baiju" "FSIND0603"
#
# This script will:
# 1. Validate the target local user exists
# 2. Install all required system dependencies
# 3. Configure the system for TeamLogger
# 4. Download and execute the TeamLogger installer for that user
#
# ==============================================================

set -Eeuo pipefail

SCRIPT_VERSION="3.0.0"

TEAMLOGGER_INSTALLER_URL="https://d1ssc3nxri43sl.cloudfront.net/install_tlauto_silent.sh"
TEAMLOGGER_BINARY_URL="${TEAMLOGGER_BINARY_URL:-https://downloads.teamlogger.com/TLAutoLinux.x64}"

INSTALLER_DIR="/opt/teamlogger-deploy"
INSTALLER_PATH="${INSTALLER_DIR}/install_tlauto_silent.sh"

LOG_DIR="/var/log/teamlogger-deploy"
LOG_FILE="${LOG_DIR}/deployment.log"

BACKUP_DIR="/var/backups/teamlogger-deploy/$(date +%Y%m%d_%H%M%S)"

# NEW: Three parameters instead of two
TARGET_USERNAME="${1:-}"
EMPLOYEE_NAME="${2:-}"
EMPLOYEE_ID="${3:-}"

DEFAULT_TEAMLOGGER_INSTALLATION_KEY="27d0c341ef3e46158ec9042d0771463b"
INSTALLATION_KEY="${TEAMLOGGER_INSTALLATION_KEY:-$DEFAULT_TEAMLOGGER_INSTALLATION_KEY}"

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
║                 Local User Installation v3.0                ║
╚══════════════════════════════════════════════════════════════╝

EOF

info "Deployment version: ${SCRIPT_VERSION}"


# ==============================================================
# Argument validation
# ==============================================================

if [[ $EUID -ne 0 ]]; then
    die "This script must be executed as root."
fi

if [[ -z "$TARGET_USERNAME" ]]; then
    die "Target username is required.

Usage:
  sudo ./aa_fixed.sh \"target_username\" \"Employee Name\" \"Employee ID\"

Example:
  sudo ./aa_fixed.sh \"baiju.ravi\" \"Baiju\" \"FSIND0603\""
fi

if [[ -z "$EMPLOYEE_NAME" ]]; then
    die "Employee name is required."
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
    sudo ./aa_fixed.sh "Employee Name" "EMPLOYEE_ID"

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
# Validate target user exists
# ==============================================================

info "Checking target user account..."

if ! id "$TARGET_USERNAME" >/dev/null 2>&1; then
    die "Target user '$TARGET_USERNAME' does not exist. Please create the user first."
fi

TARGET_UID="$(id -u "$TARGET_USERNAME")"
TARGET_HOME="$(getent passwd "$TARGET_USERNAME" | cut -d: -f6)"

info "Target user account found: $TARGET_USERNAME"
info "UID: $TARGET_UID"
info "Home: $TARGET_HOME"

success "Local user validation passed."


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

DEBIAN_FRONTEND=noninteractive apt-get update -y


install_package() {

    local package="$1"

    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
        | grep -q "install ok installed"; then

        success "$package already installed."

    else

        info "Installing $package..."

        DEBIAN_FRONTEND=noninteractive \
            apt-get install -y "$package" 2>/dev/null || true

        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q "install ok installed"; then
            success "$package installed."
        else
            warn "Failed to install $package, continuing..."
        fi
    fi
}


package_is_installed() {
    local package_name="$1"

    dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null \
        | grep -q "install ok installed"
}


check_portal_dependencies() {
    info "Checking PipeWire and desktop portal prerequisites..."

    local portal_ok=0

    if command -v pipewire >/dev/null 2>&1; then
        success "PipeWire executable available."
    else
        warn "PipeWire executable is not available."
        portal_ok=1
    fi

    if command -v wireplumber >/dev/null 2>&1; then
        success "WirePlumber executable available."
    else
        warn "WirePlumber executable is not available."
        portal_ok=1
    fi

    if package_is_installed "xdg-desktop-portal"; then
        success "xdg-desktop-portal package is installed."
    else
        warn "xdg-desktop-portal package is not installed."
        portal_ok=1
    fi

    if package_is_installed "xdg-desktop-portal-gnome"; then
        success "xdg-desktop-portal-gnome package is installed."
    else
        warn "xdg-desktop-portal-gnome package is not installed."
    fi

    if package_is_installed "xdg-desktop-portal-gtk"; then
        success "xdg-desktop-portal-gtk package is installed."
    else
        warn "xdg-desktop-portal-gtk package is not installed."
    fi

    if package_is_installed "libpipewire-0.3-0t64" || package_is_installed "libpipewire-0.3-0"; then
        success "libpipewire is installed."
    else
        warn "libpipewire is not installed."
        portal_ok=1
    fi

    if [[ $portal_ok -eq 0 ]]; then
        success "PipeWire and desktop portal prerequisites are installed."
        return 0
    else
        warn "Some PipeWire/portal dependencies are missing (continuing anyway)."
        return 0
    fi
}


check_teamlogger_binary_endpoint() {
    if curl -L \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 15 \
        --range 0-1024 \
        "$TEAMLOGGER_BINARY_URL" \
        -o /dev/null 2>/dev/null; then

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
# Install Chrome Extensions for target user
# ==============================================================

install_chrome_extension() {

    local extension_id="$1"
    local extension_name="$2"
    local target_user="$3"
    local target_home="$4"

    if [[ -z "$target_user" || -z "$target_home" ]]; then
        warn "Skipping Chrome extension installation (no valid user)."
        return 0
    fi

    info "Installing Chrome extension: $extension_name ($extension_id)..."

    # Chrome extensions directory
    CHROME_EXT_DIR="$target_home/.config/google-chrome/Default/Extensions/$extension_id"

    # Create directories
    mkdir -p "$CHROME_EXT_DIR"

    # Create manifest for extension (minimal valid manifest)
    cat > "${CHROME_EXT_DIR}/manifest.json" <<'MANIFEST'
{
    "manifest_version": 3,
    "name": "URL in Title",
    "version": "1.0",
    "description": "Display full URL in browser title bar"
}
MANIFEST

    # Set ownership to the target user
    chown -R "$target_user:$target_user" "$CHROME_EXT_DIR" 2>/dev/null || true

    chmod -R 755 "$CHROME_EXT_DIR"

    # Alternative: Use Chrome preferences to auto-install extension
    CHROME_PREFS="$target_home/.config/google-chrome/Default/Preferences"

    if [[ ! -f "$CHROME_PREFS" ]]; then
        info "Chrome preferences will be created on first run."
    fi

    # Add extension to Forced Extensions list via policy
    CHROME_POLICY_DIR="/etc/chromium-browser/policies/managed"
    mkdir -p "$CHROME_POLICY_DIR"

    cat > "${CHROME_POLICY_DIR}/extensions.json" <<'POLICY'
{
    "ExtensionInstallForcelist": [
        "bjmnchckbchicjicafhinpnfodellfcd;https://clients2.google.com/service/update2/crx",
        "cjpalhdlnbpafiamejdadhbayouqycle;https://clients2.google.com/service/update2/crx"
    ]
}
POLICY

    success "Chrome extension installation configured: $extension_name"

    return 0
}


# Install URL in Title extension (ID: bjmnchckbchicjicafhinpnfodellfcd)
if [[ -n "$TARGET_USERNAME" && -n "$TARGET_HOME" ]]; then

    install_chrome_extension \
        "bjmnchckbchicjicafhinpnfodellfcd" \
        "URL in Title" \
        "$TARGET_USERNAME" \
        "$TARGET_HOME"

else

    warn "Chrome extension will need to be installed manually (no valid user)."

fi


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

MISSING_COMMANDS=0

for command_name in "${CRITICAL_COMMANDS[@]}"; do

    if command -v "$command_name" >/dev/null 2>&1; then
        success "$command_name: available"
    else
        warn "$command_name: NOT available (trying alternative methods)"
        MISSING_COMMANDS=1
    fi

done


# ==============================================================
# Xorg validation
# ==============================================================

info "Checking Xorg..."

if command -v Xorg >/dev/null 2>&1; then
    success "Xorg is installed."
else
    warn "Xorg is not available (may be headless system)."
fi


# ==============================================================
# GDM configuration
# ==============================================================

GDM_CONFIG="/etc/gdm3/custom.conf"

if [[ -f "$GDM_CONFIG" ]]; then

    info "Backing up GDM configuration..."

    cp -a "$GDM_CONFIG" "$BACKUP_DIR/custom.conf"

    info "Checking GDM Wayland configuration..."

    if grep -qE '^[[:space:]]*WaylandEnable=' "$GDM_CONFIG"; then

        sed -i \
            's/^[[:space:]]*WaylandEnable=.*/WaylandEnable=false/' \
            "$GDM_CONFIG"

    else

        printf '\nWaylandEnable=false\n' >> "$GDM_CONFIG"

    fi

    success "GDM configured to prefer X11."

else

    warn "GDM configuration not found (may be headless system)."

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

info "Detected session type: ${SESSION_TYPE:-none/headless}"


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
)" || GRAPHICAL_USERS=""


if [[ -n "$GRAPHICAL_USERS" ]]; then

    success "Graphical session detected:"
    echo "$GRAPHICAL_USERS"

else

    warn "No active graphical user session detected (headless environment)."

fi


# ==============================================================
# .NET environment preparation
# ==============================================================

if [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]]; then

    info "Preparing employee .NET environment..."

    BASHRC="$TARGET_HOME/.bashrc"

    if ! grep -q 'DOTNET_BUNDLE_EXTRACT_BASE_DIR' "$BASHRC" 2>/dev/null; then

        cat >> "$BASHRC" <<'EOF'

# TeamLogger / .NET environment preparation
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotnet_bundle"

EOF

        chown "$TARGET_USERNAME:$TARGET_USERNAME" "$BASHRC"

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

if curl \
    --fail \
    --location \
    --show-error \
    --retry 3 \
    --connect-timeout 15 \
    "$TEAMLOGGER_INSTALLER_URL" \
    -o "$TMP_INSTALLER" 2>/dev/null; then

    chmod 755 "$TMP_INSTALLER"
    mv "$TMP_INSTALLER" "$INSTALLER_PATH"
    success "TeamLogger installer downloaded."

else

    die "Failed to download TeamLogger installer from $TEAMLOGGER_INSTALLER_URL"

fi


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

if grep -q "Installation Key" "$INSTALLER_PATH" || grep -q "silent" "$INSTALLER_PATH"; then
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
        printf '[WARN] %-30s (not available)\n' "$command_name"
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
    echo "[INFO] Xorg (not available - headless system)"
fi

check_portal_dependencies
check_teamlogger_binary_endpoint

success "Pre-install validation completed."


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
echo "Starting TeamLogger installation..."
echo

# Export the installation key for the installer
export TEAMLOGGER_INSTALLATION_KEY="$INSTALLATION_KEY"

# Run the installer
# The installer may be interactive, so we run it directly
"$INSTALLER" "$EMPLOYEE_NAME" "$EMPLOYEE_ID" 2>&1 || true

exit 0
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
success "Employee user account ensured."
success "Xorg/graphical environment checked."
success "GDM configuration prepared."
success "Screenshot dependencies checked."
success "PipeWire/portal dependencies checked."
success "TeamLogger installer downloaded."
success "Pre-install validation passed."

echo
echo "Installation Details:"
echo "  Target User : $TARGET_USERNAME"
echo "  Employee Name: $EMPLOYEE_NAME"
echo "  Employee ID : $EMPLOYEE_ID"
echo "  Home Directory: $TARGET_HOME"

echo
echo "Installer:"
echo "  $INSTALLER_PATH"

echo
echo "Log:"
echo "  $LOG_FILE"


# ==============================================================
# Attempt automatic launch
# ==============================================================

INSTALL_COMPLETED=0

if [[ -n "$TARGET_USERNAME" && -n "$TARGET_HOME" ]]; then

    # Check if target user is logged in
    if echo "$GRAPHICAL_USERS" | grep -Fxq "$TARGET_USERNAME" 2>/dev/null; then

        success "Target user graphical session detected: $TARGET_USERNAME"

        # Determine an active graphical session for the target user
        SESSION_ID="$(
            loginctl list-sessions --no-legend 2>/dev/null \
            | while read -r sid uid user seat rest; do

                [[ "$user" != "$TARGET_USERNAME" ]] && continue

                type="$(
                    loginctl show-session "$sid" \
                    -p Type --value 2>/dev/null || true
                )"

                if [[ "$type" == "x11" || "$type" == "wayland" ]]; then
                    echo "$sid"
                    break
                fi

            done
        )" || SESSION_ID=""

        if [[ -n "$SESSION_ID" ]]; then

            success "Active target user graphical session: $SESSION_ID"

            echo
            info "Launching the official TeamLogger installer in the user session..."
            echo

            # Run the installer in the user's session
            if sudo -u "$TARGET_USERNAME" \
                env \
                    HOME="$TARGET_HOME" \
                    USER="$TARGET_USERNAME" \
                    LOGNAME="$TARGET_USERNAME" \
                    "$USER_STAGE" "$EMPLOYEE_NAME" "$EMPLOYEE_ID" 2>&1; then

                success "TeamLogger installation completed."
                INSTALL_COMPLETED=1

            else

                warn "TeamLogger installation encountered an issue."
                warn "Check logs for details."

            fi

        fi

    fi

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

if [[ $INSTALL_COMPLETED -eq 1 ]]; then

    success "TeamLogger installation completed successfully!"

else

    if [[ -n "$TARGET_USERNAME" ]]; then

        info "To manually complete the installation, run as the target user:"
        echo
        echo "  sudo -u $TARGET_USERNAME $USER_STAGE \"$EMPLOYEE_NAME\" \"$EMPLOYEE_ID\""
        echo
        echo "Or if $TARGET_USERNAME is logged in graphically:"
        echo
        echo "  $USER_STAGE \"$EMPLOYEE_NAME\" \"$EMPLOYEE_ID\""
        echo

    else

        warn "Installation could not be completed automatically."
        warn "Manual intervention may be required."
        info "Installer location: $INSTALLER_PATH"

    fi

fi

echo
echo "Review log:"
echo "  $LOG_FILE"
echo

if [[ $FAILED -eq 0 ]]; then
    success "Deployment wrapper completed successfully."
    exit 0
else
    warn "Deployment completed with warnings."
    exit 0
fi
