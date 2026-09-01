#!/usr/bin/env bash

# ============================================================================
# TeamLogger Automated Linux Deployment
# ============================================================================
#
# Usage:
#
#   sudo ./deploy_teamlogger.sh "<EMPLOYEE_NAME>" "<EMPLOYEE_ID>"
#
# Example:
#
#   sudo ./deploy_teamlogger.sh "John Doe" "EMP001"
#
# Requirements:
#   - Ubuntu
#   - Root/sudo privileges
#   - Employee Linux account must exist
#   - Employee should be logged into the graphical desktop
#
# IMPORTANT:
#   The TeamLogger Installation Key is embedded below.
#
# ============================================================================

set -Eeuo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_VERSION="1.0.0"

TEAMLOGGER_INSTALLATION_KEY="27d0c341ef3e46158ec9042d0771463b"

TEAMLOGGER_INSTALLER_URL="https://d1ssc3nxri43sl.cloudfront.net/install_tlauto_silent.sh"

BASE_DIR="/opt/teamlogger-deploy"
INSTALLER_PATH="${BASE_DIR}/install_tlauto_silent.sh"

LOG_DIR="/var/log/teamlogger"
LOG_FILE="${LOG_DIR}/deployment.log"

BACKUP_DIR="/var/backups/teamlogger/$(date +%Y%m%d_%H%M%S)"

# Packages required for TeamLogger prerequisites.
REQUIRED_PACKAGES=(
    ca-certificates
    curl
    wget
    jq
    dbus
    dbus-user-session
    xorg
    x11-xserver-utils
    xdotool
    maim
    xprintidle
    pipewire
    wireplumber
    libpipewire-0.3-0
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
)

# ============================================================================
# ARGUMENTS
# ============================================================================

EMPLOYEE_NAME="${1:-}"
EMPLOYEE_ID="${2:-}"

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================================
# FUNCTIONS
# ============================================================================

info() {
    echo "[INFO] $*"
}

success() {
    echo "[SUCCESS] $*"
}

warning() {
    echo "[WARNING] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

fatal() {
    error "$*"
    echo
    error "Deployment stopped."
    error "Log file: $LOG_FILE"
    exit 1
}

section() {
    echo
    echo "======================================================================"
    echo " $*"
    echo "======================================================================"
    echo
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg-query \
        -W \
        -f='${Status}' \
        "$1" 2>/dev/null \
        | grep -q "install ok installed"
}

# ============================================================================
# ERROR HANDLER
# ============================================================================

trap 'error "Unexpected error at line $LINENO"; error "Command: $BASH_COMMAND"' ERR

# ============================================================================
# HEADER
# ============================================================================

clear 2>/dev/null || true

cat <<'EOF'

╔══════════════════════════════════════════════════════════════════════╗
║                    TEAMLOGGER DEPLOYMENT                            ║
║                         Linux Edition                               ║
╚══════════════════════════════════════════════════════════════════════╝

EOF

info "Deployment version : $SCRIPT_VERSION"
info "Started            : $(date)"

# ============================================================================
# ROOT CHECK
# ============================================================================

section "ROOT PRIVILEGE CHECK"

if [[ "$EUID" -ne 0 ]]; then
    fatal "This script must be executed as root.

Example:

    sudo ./deploy_teamlogger.sh \"Employee Name\" \"EMP001\""
fi

success "Running with root privileges."

# ============================================================================
# ARGUMENT CHECK
# ============================================================================

section "INPUT VALIDATION"

if [[ -z "$EMPLOYEE_NAME" ]]; then
    fatal "Employee name is missing."
fi

if [[ -z "$EMPLOYEE_ID" ]]; then
    fatal "Employee ID is missing."
fi

if ! [[ "$EMPLOYEE_ID" =~ ^[A-Za-z0-9_/-]+$ ]]; then
    fatal "Invalid Employee ID: $EMPLOYEE_ID"
fi

info "Employee Name : $EMPLOYEE_NAME"
info "Employee ID   : $EMPLOYEE_ID"

# ============================================================================
# OS CHECK
# ============================================================================

section "OPERATING SYSTEM CHECK"

if [[ ! -f /etc/os-release ]]; then
    fatal "/etc/os-release not found."
fi

source /etc/os-release

info "OS       : ${PRETTY_NAME:-Unknown}"
info "Version  : ${VERSION_ID:-Unknown}"
info "Arch     : $(dpkg --print-architecture 2>/dev/null || echo Unknown)"

if [[ "${ID:-}" != "ubuntu" ]]; then
    warning "This script is designed primarily for Ubuntu."
fi

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

section "DEPLOYMENT DIRECTORY SETUP"

mkdir -p "$BASE_DIR"
mkdir -p "$BACKUP_DIR"

chmod 700 "$BASE_DIR"
chmod 700 "$BACKUP_DIR"

success "Deployment directories ready."

# ============================================================================
# NETWORK CHECK
# ============================================================================

section "NETWORK CHECK"

if ! command_exists curl; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl
fi

if curl \
    --silent \
    --show-error \
    --fail \
    --connect-timeout 10 \
    https://downloads.teamlogger.com/ \
    -o /dev/null; then

    success "Internet connectivity available."

else

    warning "Unable to verify TeamLogger download endpoint."

fi

# ============================================================================
# APT UPDATE
# ============================================================================

section "PACKAGE REPOSITORY UPDATE"

info "Updating apt package lists..."

DEBIAN_FRONTEND=noninteractive apt-get update

success "Package lists updated."

# ============================================================================
# PACKAGE INSTALLATION
# ============================================================================

section "SYSTEM PREREQUISITES"

info "Installing/checking required packages."

PACKAGE_FAILURES=0

for package in "${REQUIRED_PACKAGES[@]}"; do

    if package_installed "$package"; then

        success "$package already installed."

        continue

    fi

    info "Installing $package..."

    if DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "$package"; then

        success "$package installed."

    else

        error "Failed to install $package."
        PACKAGE_FAILURES=$((PACKAGE_FAILURES + 1))

    fi

done

if [[ "$PACKAGE_FAILURES" -ne 0 ]]; then

    error "$PACKAGE_FAILURES package(s) failed to install."

    fatal "Required system dependencies are incomplete."

fi

success "All required packages installed."

# ============================================================================
# XORG CHECK
# ============================================================================

section "XORG / X11 CHECK"

if command_exists Xorg; then
    success "Xorg is available."
else
    fatal "Xorg is not available."
fi

if command_exists xrandr; then
    success "xrandr is available."
else
    fatal "xrandr is not available."
fi

if command_exists xdotool; then
    success "xdotool is available."
else
    fatal "xdotool is not available."
fi

if command_exists maim; then
    success "maim is available."
else
    fatal "maim is not available."
fi

if command_exists xprintidle; then
    success "xprintidle is available."
else
    warning "xprintidle is not available."
fi

# ============================================================================
# GDM CHECK
# ============================================================================

section "GDM / X11 CONFIGURATION"

GDM_CONFIG="/etc/gdm3/custom.conf"

if [[ -f "$GDM_CONFIG" ]]; then

    info "Backing up GDM configuration."

    cp -a \
        "$GDM_CONFIG" \
        "$BACKUP_DIR/custom.conf"

    success "GDM configuration backed up."

    # Check current configuration.

    if grep -qE '^[[:space:]]*WaylandEnable=false' "$GDM_CONFIG"; then

        success "GDM is already configured to disable Wayland."

    else

        info "Configuring GDM to use X11."

        if grep -qE '^[[:space:]]*WaylandEnable=' "$GDM_CONFIG"; then

            sed -i \
                's/^[[:space:]]*WaylandEnable=.*/WaylandEnable=false/' \
                "$GDM_CONFIG"

        else

            printf '\nWaylandEnable=false\n' >> "$GDM_CONFIG"

        fi

        success "GDM X11 configuration applied."

    fi

else

    warning "GDM configuration file not found."

fi

# ============================================================================
# PIPEWIRE / PORTAL CHECK
# ============================================================================

section "PIPEWIRE / DESKTOP PORTAL CHECK"

if command_exists pipewire; then
    success "PipeWire executable available."
else
    fatal "PipeWire is not available."
fi

if command_exists wireplumber; then
    success "WirePlumber available."
else
    warning "WirePlumber executable not found."
fi

if command_exists xdg-desktop-portal; then
    success "xdg-desktop-portal available."
else
    fatal "xdg-desktop-portal is not available."
fi

if command_exists dbus-update-activation-environment; then
    success "D-Bus session support available."
else
    warning "dbus-update-activation-environment not found."
fi

# ============================================================================
# EMPLOYEE ACCOUNT
# ============================================================================

section "EMPLOYEE ACCOUNT CHECK"

if ! id "$EMPLOYEE_ID" >/dev/null 2>&1; then

    fatal "Linux user '$EMPLOYEE_ID' does not exist.

The Employee ID supplied to this script must correspond to the
Linux account that will run the TeamLogger user installation."

fi

TARGET_USER="$EMPLOYEE_ID"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

info "Linux user : $TARGET_USER"
info "UID        : $TARGET_UID"
info "Home       : $TARGET_HOME"

success "Employee Linux account found."

# ============================================================================
# USER DIRECTORY
# ============================================================================

section "EMPLOYEE ENVIRONMENT"

USER_CONFIG_DIR="$TARGET_HOME/.config"
USER_LOCAL_DIR="$TARGET_HOME/.local"

mkdir -p "$USER_CONFIG_DIR"
mkdir -p "$USER_LOCAL_DIR"

chown "$TARGET_USER:$TARGET_USER" \
    "$USER_CONFIG_DIR" \
    "$USER_LOCAL_DIR"

success "Employee user environment ready."

# ============================================================================
# .NET ENVIRONMENT
# ============================================================================

section ".NET ENVIRONMENT"

BASHRC="$TARGET_HOME/.bashrc"

if [[ -f "$BASHRC" ]]; then

    if grep -q "DOTNET_BUNDLE_EXTRACT_BASE_DIR" "$BASHRC"; then

        success "DOTNET_BUNDLE_EXTRACT_BASE_DIR already configured."

    else

        cat >> "$BASHRC" <<'EOF'

# TeamLogger .NET bundle extraction directory
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotnet_bundle"

EOF

        chown "$TARGET_USER:$TARGET_USER" "$BASHRC"

        success ".NET environment configured."

    fi

else

    warning "$BASHRC not found."

fi

# ============================================================================
# ACTIVE GRAPHICAL SESSION
# ============================================================================

section "GRAPHICAL SESSION CHECK"

SESSION_ID=""
SESSION_TYPE=""
SESSION_DISPLAY=""
SESSION_STATE=""

while read -r sid uid user seat rest; do

    [[ -z "$sid" ]] && continue

    if [[ "$user" != "$TARGET_USER" ]]; then
        continue
    fi

    type="$(
        loginctl show-session "$sid" \
            -p Type \
            --value 2>/dev/null || true
    )"

    state="$(
        loginctl show-session "$sid" \
            -p State \
            --value 2>/dev/null || true
    )"

    display="$(
        loginctl show-session "$sid" \
            -p Display \
            --value 2>/dev/null || true
    )"

    if [[ "$type" == "x11" || "$type" == "wayland" ]]; then

        SESSION_ID="$sid"
        SESSION_TYPE="$type"
        SESSION_DISPLAY="$display"
        SESSION_STATE="$state"

        break

    fi

done < <(loginctl list-sessions --no-legend 2>/dev/null || true)


if [[ -n "$SESSION_ID" ]]; then

    success "Employee graphical session detected."

    info "Session ID : $SESSION_ID"
    info "Type       : $SESSION_TYPE"
    info "Display    : ${SESSION_DISPLAY:-unknown}"
    info "State      : ${SESSION_STATE:-unknown}"

else

    warning "Employee is not currently logged into a graphical session."

    warning "The system preparation can continue, but the TeamLogger"
    warning "vendor installer must execute from the employee's desktop."

fi

# ============================================================================
# DOWNLOAD TEAMLOGGER INSTALLER
# ============================================================================

section "TEAMLOGGER INSTALLER"

info "Downloading official TeamLogger installer."

TEMP_INSTALLER="${INSTALLER_PATH}.tmp"

rm -f "$TEMP_INSTALLER"

curl \
    --fail \
    --location \
    --show-error \
    --retry 3 \
    --connect-timeout 20 \
    --max-time 300 \
    "$TEAMLOGGER_INSTALLER_URL" \
    -o "$TEMP_INSTALLER"

if [[ ! -s "$TEMP_INSTALLER" ]]; then
    fatal "TeamLogger installer download failed."
fi

chmod 755 "$TEMP_INSTALLER"

mv "$TEMP_INSTALLER" "$INSTALLER_PATH"

success "TeamLogger installer downloaded."

info "Installer size: $(du -h "$INSTALLER_PATH" | awk '{print $1}')"

# ============================================================================
# INSTALLER VALIDATION
# ============================================================================

section "TEAMLOGGER INSTALLER VALIDATION"

if [[ ! -x "$INSTALLER_PATH" ]]; then
    fatal "Downloaded TeamLogger installer is not executable."
fi

if grep -q "TLAutoLinux Silent Installer" "$INSTALLER_PATH"; then
    success "Expected TLAutoLinux installer detected."
else
    warning "Expected installer signature was not detected."
fi

if grep -q "Installation Key Authentication" "$INSTALLER_PATH"; then
    success "Installation-key authentication detected."
else
    warning "Installation-key authentication text not detected."
fi

# ============================================================================
# INSTALLATION KEY FILE
# ============================================================================

section "TEAMLOGGER AUTHENTICATION PREPARATION"

KEY_FILE="${BASE_DIR}/installation.key"

umask 077

printf '%s\n' "$TEAMLOGGER_INSTALLATION_KEY" > "$KEY_FILE"

chmod 600 "$KEY_FILE"

success "Installation key stored with restricted permissions."

# ============================================================================
# FINAL SYSTEM VALIDATION
# ============================================================================

section "FINAL SYSTEM VALIDATION"

VALIDATION_FAILURES=0

validate_command() {

    local cmd="$1"

    if command_exists "$cmd"; then

        success "$cmd : PASS"

    else

        error "$cmd : FAIL"

        VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))

    fi
}

validate_command curl
validate_command wget
validate_command jq
validate_command Xorg
validate_command xrandr
validate_command xdotool
validate_command maim
validate_command pipewire
validate_command xdg-desktop-portal
validate_command dbus-update-activation-environment

if [[ "$VALIDATION_FAILURES" -ne 0 ]]; then

    fatal "Final prerequisite validation failed."

fi

success "All critical prerequisite checks passed."

# ============================================================================
# CREATE USER-STAGE WRAPPER
# ============================================================================

section "USER SESSION PREPARATION"

USER_STAGE="${BASE_DIR}/teamlogger-user-stage.sh"

cat > "$USER_STAGE" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

INSTALLER="/opt/teamlogger-deploy/install_tlauto_silent.sh"

EMPLOYEE_NAME="$1"
EMPLOYEE_ID="$2"

echo
echo "=============================================================="
echo " TeamLogger User Installation"
echo "=============================================================="
echo
echo "Employee : $EMPLOYEE_NAME"
echo "ID       : $EMPLOYEE_ID"
echo
echo "Running as:"
whoami
echo

if [[ "$(id -u)" -eq 0 ]]; then
    echo "[ERROR] TeamLogger user-stage must NOT run as root."
    exit 1
fi

if [[ ! -x "$INSTALLER" ]]; then
    echo "[ERROR] TeamLogger installer not found."
    exit 1
fi

echo "[INFO] Launching official TeamLogger installer."
echo

exec "$INSTALLER"
EOF

chmod 755 "$USER_STAGE"

chown root:root "$USER_STAGE"

success "User-stage wrapper prepared."

# ============================================================================
# REPORT ROOT PREPARATION
# ============================================================================

section "ROOT PREPARATION COMPLETED"

cat <<EOF

Employee
--------------------------------
Name       : $EMPLOYEE_NAME
Employee ID: $EMPLOYEE_ID
Linux user : $TARGET_USER


System
--------------------------------
OS         : ${PRETTY_NAME:-Unknown}
Architecture: $(dpkg --print-architecture 2>/dev/null || echo Unknown)


Graphical Session
--------------------------------
Session ID : ${SESSION_ID:-NOT FOUND}
Type       : ${SESSION_TYPE:-NOT FOUND}
Display    : ${SESSION_DISPLAY:-NOT FOUND}


TeamLogger
--------------------------------
Installer  : $INSTALLER_PATH


Backup
--------------------------------
Location   : $BACKUP_DIR


Log
--------------------------------
$LOG_FILE

EOF

# ============================================================================
# NO GRAPHICAL SESSION
# ============================================================================

if [[ -z "$SESSION_ID" ]]; then

    warning "No graphical session was found for $TARGET_USER."

    cat <<EOF

The machine preparation is COMPLETE.

The TeamLogger vendor installer cannot safely be started from root
because the vendor explicitly requires it to run as the logged-in
employee.

After the employee logs into the Ubuntu desktop, run:

    $USER_STAGE "$EMPLOYEE_NAME" "$EMPLOYEE_ID"

as the employee.

EOF

    # Keep key because user-stage still needs it.
    # Restrict permissions.
    chmod 700 "$KEY_FILE"

    exit 0

fi

# ============================================================================
# GRAPHICAL SESSION FOUND
# ============================================================================

section "EMPLOYEE SESSION FOUND"

success "Employee desktop session is active."

info "User       : $TARGET_USER"
info "Session ID : $SESSION_ID"
info "Session    : $SESSION_TYPE"

# ============================================================================
# SESSION ENVIRONMENT
# ============================================================================

SESSION_ENV_FILE="${BASE_DIR}/session.env"

rm -f "$SESSION_ENV_FILE"

touch "$SESSION_ENV_FILE"

chmod 600 "$SESSION_ENV_FILE"

# Try to obtain environment from the active session.
#
# loginctl show-session does not always expose DISPLAY/XAUTHORITY,
# therefore we only populate variables that are safely discoverable.

SESSION_LEADER="$(
    loginctl show-session "$SESSION_ID" \
        -p Leader \
        --value 2>/dev/null || true
)"

if [[ -n "$SESSION_LEADER" ]]; then

    success "Session leader PID: $SESSION_LEADER"

    if [[ -r "/proc/$SESSION_LEADER/environ" ]]; then

        tr '\0' '\n' < "/proc/$SESSION_LEADER/environ" \
            | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|XDG_SESSION_TYPE)=' \
            > "$SESSION_ENV_FILE" || true

    fi

fi

# ============================================================================
# CHECK USER SESSION ENVIRONMENT
# ============================================================================

if grep -q '^DISPLAY=' "$SESSION_ENV_FILE"; then
    success "DISPLAY environment detected."
else
    warning "DISPLAY environment could not be extracted."
fi

if grep -q '^DBUS_SESSION_BUS_ADDRESS=' "$SESSION_ENV_FILE"; then
    success "D-Bus session detected."
else
    warning "D-Bus session address could not be extracted."
fi

# ============================================================================
# IMPORTANT VENDOR INSTALLER REQUIREMENT
# ============================================================================

section "TEAMLOGGER USER INSTALLATION"

cat <<EOF

The system-level TeamLogger prerequisites are complete.

The official TeamLogger installer must run as:

    $TARGET_USER

and inside the employee's graphical session.

The deployment will now launch the official installer under
the employee account.

Employee:
    $EMPLOYEE_NAME

Employee ID:
    $EMPLOYEE_ID

EOF

sleep 2

# ============================================================================
# LAUNCH USER INSTALLER
# ============================================================================

# We deliberately do not pass the Linux password.
#
# We also do not use sudo ./install_tlauto_silent.sh.
#
# The installer is launched as the employee.

if [[ -s "$SESSION_ENV_FILE" ]]; then

    # shellcheck disable=SC2046
    set +u

    SESSION_ENV_ARGS=""

    while IFS='=' read -r key value; do

        case "$key" in

            DISPLAY)
                SESSION_ENV_ARGS+=" DISPLAY=$value"
                ;;

            WAYLAND_DISPLAY)
                SESSION_ENV_ARGS+=" WAYLAND_DISPLAY=$value"
                ;;

            XAUTHORITY)
                SESSION_ENV_ARGS+=" XAUTHORITY=$value"
                ;;

            DBUS_SESSION_BUS_ADDRESS)
                SESSION_ENV_ARGS+=" DBUS_SESSION_BUS_ADDRESS=$value"
                ;;

            XDG_RUNTIME_DIR)
                SESSION_ENV_ARGS+=" XDG_RUNTIME_DIR=$value"
                ;;

            XDG_SESSION_TYPE)
                SESSION_ENV_ARGS+=" XDG_SESSION_TYPE=$value"
                ;;

        esac

    done < "$SESSION_ENV_FILE"

    set -u

else

    SESSION_ENV_ARGS=""

fi

# ============================================================================
# RUN INSTALLER
# ============================================================================

info "Starting TeamLogger installer as $TARGET_USER."

if [[ -n "$SESSION_ENV_ARGS" ]]; then

    # Convert the controlled environment list into environment variables.
    #
    # The values originate from the current user's own login session.

    # shellcheck disable=SC2086
    sudo -u "$TARGET_USER" \
        env \
        HOME="$TARGET_HOME" \
        USER="$TARGET_USER" \
        LOGNAME="$TARGET_USER" \
        $SESSION_ENV_ARGS \
        "$INSTALLER_PATH"

else

    warning "No graphical environment variables could be extracted."

    warning "Starting installer with the employee's basic environment."

    sudo -u "$TARGET_USER" \
        env \
        HOME="$TARGET_HOME" \
        USER="$TARGET_USER" \
        LOGNAME="$TARGET_USER" \
        "$INSTALLER_PATH"

fi

INSTALLER_EXIT=$?

# ============================================================================
# INSTALLER RESULT
# ============================================================================

section "TEAMLOGGER INSTALLER RESULT"

if [[ "$INSTALLER_EXIT" -eq 0 ]]; then

    success "TeamLogger installer exited successfully."

else

    error "TeamLogger installer exited with code: $INSTALLER_EXIT"

    warning "This does not necessarily mean TeamLogger is unusable."
    warning "Review the TeamLogger installer output and deployment log."

fi

# ============================================================================
# POST INSTALLATION CHECK
# ============================================================================

section "POST-INSTALLATION CHECK"

info "Checking TeamLogger-related processes."

if pgrep -u "$TARGET_USER" -fa 'TLAuto|TeamLogger|tlauto' >/dev/null 2>&1; then

    success "TeamLogger-related process detected."

    pgrep -u "$TARGET_USER" -fa 'TLAuto|TeamLogger|tlauto' || true

else

    warning "No TeamLogger process was detected immediately."

fi

# ============================================================================
# USER SERVICE CHECK
# ============================================================================

section "USER SYSTEMD CHECK"

if command_exists loginctl; then

    loginctl user-status "$TARGET_USER" \
        --no-pager \
        2>/dev/null \
        | head -80 || true

fi

# ============================================================================
# SCREENSHOT CAPABILITY TEST
# ============================================================================

section "SCREENSHOT CAPABILITY TEST"

if [[ "$SESSION_TYPE" == "x11" ]]; then

    info "X11 session detected."

    if command_exists xrandr &&
       command_exists maim &&
       command_exists xdotool; then

        success "X11 screenshot tools are installed."

    else

        warning "Required X11 screenshot tools are incomplete."

    fi

else

    warning "Current session is not X11."
    warning "Screenshot behavior depends on TeamLogger's portal implementation."

fi

# ============================================================================
# SECURITY CLEANUP
# ============================================================================

section "CLEANUP"

# The installation key is no longer needed by this wrapper.
#
# The official TeamLogger installer uses its own authentication flow.
#
# Remove the temporary key file.

if [[ -f "$KEY_FILE" ]]; then

    shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE"

    success "Temporary installation key file removed."

fi

# ============================================================================
# FINAL REPORT
# ============================================================================

section "DEPLOYMENT COMPLETE"

cat <<EOF

╔══════════════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT SUMMARY                               ║
╚══════════════════════════════════════════════════════════════════════╝

Employee Name       : $EMPLOYEE_NAME
Employee ID         : $EMPLOYEE_ID
Linux User          : $TARGET_USER

Operating System    : ${PRETTY_NAME:-Unknown}
Architecture        : $(dpkg --print-architecture 2>/dev/null || echo Unknown)

Graphical Session   : ${SESSION_TYPE:-Unknown}
Session ID          : ${SESSION_ID:-Unknown}

TeamLogger Installer:
$INSTALLER_PATH

Deployment Log:
$LOG_FILE

Backup:
$BACKUP_DIR

Installer Exit Code:
$INSTALLER_EXIT

EOF

if [[ "$INSTALLER_EXIT" -eq 0 ]]; then

    success "Deployment script finished."

else

    warning "Deployment finished with TeamLogger installer exit code $INSTALLER_EXIT."

fi

echo
info "Completed: $(date)"
echo
