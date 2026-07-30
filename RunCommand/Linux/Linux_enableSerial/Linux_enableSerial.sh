#!/bin/bash
#
# Linux_enableSerial.sh
# Test and enable Azure Serial Console functionality on a Linux VM.
# Designed to be run non-interactively as root (e.g. via Azure Run Command).

SERIAL_SERVICE="serial-getty@ttyS0.service"

# Report the status of the serial-getty@ttyS0.service unit.
# Sets globals for later steps:
#   SERIAL_ACTIVE_STATE   - systemd ActiveState (active, inactive, failed, ...)
#   SERIAL_UNIT_FILE_STATE - systemd UnitFileState (enabled, disabled, masked, static, ...)
#   SERIAL_LOAD_STATE     - systemd LoadState (loaded, not-found, masked, ...)
# Returns 0 if the unit is loaded and active, non-zero otherwise.
check_serial_service() {
    local unit="$SERIAL_SERVICE"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: systemctl not found; this host does not appear to use systemd." >&2
        SERIAL_LOAD_STATE="unknown"
        SERIAL_ACTIVE_STATE="unknown"
        SERIAL_UNIT_FILE_STATE="unknown"
        return 2
    fi

    SERIAL_LOAD_STATE=$(systemctl show -p LoadState --value "$unit" 2>/dev/null)
    SERIAL_ACTIVE_STATE=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null)
    SERIAL_UNIT_FILE_STATE=$(systemctl show -p UnitFileState --value "$unit" 2>/dev/null)

    : "${SERIAL_LOAD_STATE:=unknown}"
    : "${SERIAL_ACTIVE_STATE:=unknown}"
    : "${SERIAL_UNIT_FILE_STATE:=unknown}"

    echo "Serial console unit: $unit"
    echo "  LoadState     : $SERIAL_LOAD_STATE"
    echo "  ActiveState   : $SERIAL_ACTIVE_STATE"
    echo "  UnitFileState : $SERIAL_UNIT_FILE_STATE"

    if [ "$SERIAL_LOAD_STATE" != "loaded" ]; then
        return 1
    fi
    if [ "$SERIAL_ACTIVE_STATE" != "active" ]; then
        return 1
    fi
    return 0
}

# Enable and start serial-getty@ttyS0.service.
# All systemctl stdout/stderr is passed through to the caller for logging.
# Returns the exit status of the first failing systemctl call, or 0 on success.
enable_serial_service() {
    local unit="$SERIAL_SERVICE"
    local rc=0

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: systemctl not found; cannot enable $unit." >&2
        return 2
    fi

    # Unmask in case the unit was masked; ignore "not masked" as a success case.
    echo "Unmasking $unit ..."
    systemctl unmask "$unit"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "WARNING: 'systemctl unmask $unit' returned $rc (continuing)." >&2
    fi

    echo "Enabling $unit ..."
    systemctl enable "$unit"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "ERROR: 'systemctl enable $unit' failed with exit $rc." >&2
        return $rc
    fi

    echo "Starting $unit ..."
    systemctl start "$unit"
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "ERROR: 'systemctl start $unit' failed with exit $rc." >&2
        return $rc
    fi

    systemctl daemon-reload

    return 0
}

# Source /etc/os-release and compare ID / ID_LIKE against Azure endorsed distros.
# Reports the detected OS; warns if it is not on the endorsed list.
# Sets globals: OS_ID, OS_ID_LIKE, OS_PRETTY_NAME, OS_VERSION, OS_ENDORSED (yes/no/unknown).
check_os_family() {
    OS_ID="unknown"
    OS_ID_LIKE=""
    OS_PRETTY_NAME="unknown"
    OS_VERSION="unknown"
    OS_ENDORSED="unknown"

    if [ ! -r /etc/os-release ]; then
        echo "WARNING: /etc/os-release not readable; cannot identify distribution." >&2
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-$OS_ID}"
    OS_VERSION="${VERSION:-unknown}"

    # Azure endorsed / commonly supported distro IDs.
    local endorsed="rhel centos rocky almalinux ol oracle sles sled opensuse-leap opensuse-tumbleweed ubuntu debian mariner azurelinux flatcar"
    # RHEL-family derivative markers found in ID_LIKE.
    local rhel_like="rhel fedora centos"

    local id_lc="${OS_ID,,}"
    local like_lc="${OS_ID_LIKE,,}"

    OS_ENDORSED="no"
    for e in $endorsed; do
        if [ "$id_lc" = "$e" ]; then
            OS_ENDORSED="yes"
            break
        fi
    done

    if [ "$OS_ENDORSED" = "no" ] && [ -n "$like_lc" ]; then
        for l in $rhel_like; do
            case " $like_lc " in
                *" $l "*)
                    OS_ENDORSED="yes"
                    break
                    ;;
            esac
        done
    fi

    echo "Detected OS: $OS_PRETTY_NAME (ID=$OS_ID, VERSION=$OS_VERSION, ID_LIKE=\"$OS_ID_LIKE\")"
    if [ "$OS_ENDORSED" = "yes" ]; then
        echo "  Distribution recognized, proceeding with confidence."
    else
        echo "WARNING: $OS_PRETTY_NAME uncommon distribution detected; this script may not work as expected." >&2
    fi
    return 0
}

main() {
    echo "=== OS identification ==="
    check_os_family

    echo "=== Initial state ==="
    check_serial_service
    local initial_rc=$?

    # rc 2 = no systemd / systemctl missing; enabling cannot succeed.
    if [ $initial_rc -eq 2 ]; then
        echo "FINAL STATE: cannot manage $SERIAL_SERVICE on this host (no systemd)."
        return $initial_rc
    fi

    if [ $initial_rc -eq 0 ]; then
        echo "FINAL STATE: $SERIAL_SERVICE already loaded/active (ActiveState=$SERIAL_ACTIVE_STATE, UnitFileState=$SERIAL_UNIT_FILE_STATE)."
        return 0
    fi

    echo "=== Enabling $SERIAL_SERVICE ==="
    enable_serial_service
    local enable_rc=$?
    if [ $enable_rc -ne 0 ]; then
        echo "FINAL STATE: enable_serial_service failed with exit $enable_rc."
        return $enable_rc
    fi

    echo "=== Post-enable validation ==="
    check_serial_service
    local final_rc=$?

    if [ $final_rc -eq 0 ]; then
        echo "FINAL STATE: $SERIAL_SERVICE enabled and active (ActiveState=$SERIAL_ACTIVE_STATE, UnitFileState=$SERIAL_UNIT_FILE_STATE)."
    else
        echo "FINAL STATE: $SERIAL_SERVICE still not fully active after enable (LoadState=$SERIAL_LOAD_STATE, ActiveState=$SERIAL_ACTIVE_STATE, UnitFileState=$SERIAL_UNIT_FILE_STATE)."
    fi
    return $final_rc
}

main
exit $?
