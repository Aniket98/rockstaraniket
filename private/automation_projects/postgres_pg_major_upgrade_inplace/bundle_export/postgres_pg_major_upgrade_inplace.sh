#!/usr/bin/env bash

#  ---------------------------------------------------------------------------------
# |
# | Author : Aniket Tomar
# | Automation Purpose : Perform Prechecks and Major Version Upgrade the PostgreSQL Cluster
# | Automation Version : 2.0
# | First Draft : September 2026
# | Supported OS : Rocky Linux
# |
#  ---------------------------------------------------------------------------------

# ------> NOTE: This automation script is currently strictly for Rocky Linux OS only.

set -o pipefail

###############################################################################
# PostgreSQL In-Place Major Upgrade Framework
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG="$ROOT/config/pgupgrade.conf"
RUNS="$ROOT/runs"

DELAY=0.4

###############################################################################
# Basic functions
###############################################################################

usage() {
    cat <<EOF

Usage:

  $0 prechecks --runid=new
  $0 prechecks --runid=R<n>

  $0 upgrade --runid=R<n> --mode=copy
  $0 upgrade --runid=R<n> --mode=link

Examples:

  $0 prechecks --runid=new
  $0 prechecks --runid=R1

  $0 upgrade --runid=R1 --mode=copy
  $0 upgrade --runid=R1 --mode=link

EOF
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

full_id() {
    echo "PG_RUN_ID_$1"
}

run_dir() {
    echo "$RUNS/$(full_id "$RUN_ID")"
}

valid_id() {
    [[ "$1" =~ ^R[1-9][0-9]*$ ]]
}

###############################################################################
# Find highest existing RUN ID
###############################################################################

highest() {

    local m=0
    local p
    local n

    shopt -s nullglob

    for p in "$RUNS"/PG_RUN_ID_R*; do

        [[ -d "$p" ]] || continue

        [[ "$(basename "$p")" =~ ^PG_RUN_ID_R([1-9][0-9]*)$ ]] || continue

        n="${BASH_REMATCH[1]}"

        (( n > m )) && m=$n

    done

    shopt -u nullglob

    echo "$m"
}

###############################################################################
# Create next RUN ID
###############################################################################

create_new_run() {

    local highest_num
    local next_num

    highest_num="$(highest)"
    next_num=$((highest_num + 1))

    RUN_ID="R$next_num"

    local dir
    dir="$(run_dir)"

    mkdir -p \
        "$dir/prechecks" \
        "$dir/upgrade"

    log "Created new run: $(full_id "$RUN_ID")"

    echo "$RUN_ID"
}

###############################################################################
# Validate existing RUN
###############################################################################

validate_existing_run() {

    valid_id "$RUN_ID" ||
        die "Invalid run ID: $RUN_ID"

    local dir
    dir="$(run_dir)"

    [[ -d "$dir" ]] ||
        die "Run does not exist: $(full_id "$RUN_ID")"

    mkdir -p \
        "$dir/prechecks" \
        "$dir/upgrade"
}

###############################################################################
# Progress animation
###############################################################################

progress() {

    local message="$1"

    for dots in "." ".." "..." "...."; do

        printf "\r[%-4s] %s" "$dots" "$message"

        sleep "$DELAY"

    done

    printf "\r\033[K"
}

###############################################################################
# Run one step
###############################################################################

run_step() {

    local step_name="$1"
    local step_dir="$2"
    shift 2

    local base="$step_dir/$step_name"
    local wip="$base.WIP"
    local success="$base.SUCCESS"
    local failed="$base.FAILED"

    ###########################################################################
    # Already successful
    ###########################################################################

    if [[ -f "$success" ]]; then

        log "SKIP $step_name"

        return 0
    fi

    ###########################################################################
    # Remove old FAILED/WIP state before retry
    ###########################################################################

    rm -f "$failed"

    ###########################################################################
    # Create WIP log/state file
    ###########################################################################

    : > "$wip" ||
        die "Cannot create step log: $wip"

#    log "RUN $step_name"

    ###########################################################################
    # Execute step
    #
    # stdout and stderr from the step are written into the WIP file.
    ###########################################################################

    if "$@" >> "$wip" 2>&1; then

        mv "$wip" "$success" ||
            die "Cannot rename $wip to $success"

        log "PASS $step_name"

        return 0

    else

        mv "$wip" "$failed" ||
            die "Cannot rename $wip to $failed"

        log "FAIL $step_name"

        return 1
    fi
}

###############################################################################
# Dummy PRECHECK steps
#
# These functions will later contain the real PostgreSQL checks.
###############################################################################

check_pg_os_user() {

    echo "Configured PG_OS_USER : ${PG_OS_USER:-<empty>}"

    if [[ -z "${PG_OS_USER:-}" ]]; then
        echo "Result                : FAIL"
        echo "Reason                : PG_OS_USER is empty."
        return 1
    fi

    if ! id "$PG_OS_USER" >/dev/null 2>&1; then
        echo "Result                : FAIL"
        echo "Reason                : OS user '$PG_OS_USER' does not exist."
        return 1
    fi

    echo "Result                : PASS"
    echo "Reason                : OS user '$PG_OS_USER' exists."

    return 0
}

check_running_user() {

    local running_user

    running_user="$(id -un)"

    echo "Expected OS user : $PG_OS_USER"
    echo "Running OS user  : $running_user"

    if [[ "$running_user" == "$PG_OS_USER" ]]; then

        echo "Result           : PASS"
        echo "Reason           : Script is running as PG_OS_USER."

        return 0

    else

        echo "Result           : FAIL"
        echo "Reason           : Script must be run as PG_OS_USER."

        return 1

    fi
}

check_old_pg_bin() {

    echo "Configured OLD_PG_BIN : ${OLD_PG_BIN:-<empty>}"

    if [[ -z "${OLD_PG_BIN:-}" ]]; then
        echo "Result               : FAIL"
        echo "Reason               : OLD_PG_BIN is empty."
        return 1
    fi

    if ! "$OLD_PG_BIN/pg_config" --version >/dev/null 2>&1; then
        echo "Result               : FAIL"
        echo "Reason               : pg_config could not be executed from OLD_PG_BIN."
        return 1
    fi

    echo "Result               : PASS"
    echo "Reason               : pg_config is executable from OLD_PG_BIN."

    return 0
}

check_new_pg_bin() {

    echo "Configured NEW_PG_BIN : ${NEW_PG_BIN:-<empty>}"

    if [[ -z "${NEW_PG_BIN:-}" ]]; then
        echo "Result               : FAIL"
        echo "Reason               : NEW_PG_BIN is empty."
        return 1
    fi

    if ! "$NEW_PG_BIN/pg_config" --version >/dev/null 2>&1; then
        echo "Result               : FAIL"
        echo "Reason               : pg_config could not be executed from NEW_PG_BIN."
        return 1
    fi

    echo "Result               : PASS"
    echo "Reason               : pg_config is executable from NEW_PG_BIN."

    return 0
}

check_old_pg_binary_version() {

    local reported_version
    local actual_major_version

    echo "Configured PG_OLD_VERSION : ${PG_OLD_VERSION:-<empty>}"

    if [[ -z "${PG_OLD_VERSION:-}" ]]; then
        echo "Result                   : FAIL"
        echo "Reason                   : PG_OLD_VERSION is empty."
        return 1
    fi

    reported_version="$("$OLD_PG_BIN/pg_config" --version)" || {
        echo "Result                   : FAIL"
        echo "Reason                   : Unable to execute pg_config."
        return 1
    }

    echo "pg_config output         : $reported_version"

    actual_major_version="${reported_version#PostgreSQL }"

    if [[ "$actual_major_version" =~ ^([0-9]+)\.([0-9]+)\. ]]; then
        # PostgreSQL 9.x
        actual_major_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    elif [[ "$actual_major_version" =~ ^([0-9]+)\. ]]; then
        # PostgreSQL 10+
        actual_major_version="${BASH_REMATCH[1]}"
    else
        echo "Result                   : FAIL"
        echo "Reason                   : Unable to determine PostgreSQL major version."
        return 1
    fi

    echo "Detected major version   : $actual_major_version"

    if [[ "$actual_major_version" == "$PG_OLD_VERSION" ]]; then
        echo "Result                   : PASS"
        echo "Reason                   : Binary version matches PG_OLD_VERSION."
        return 0
    fi

    echo "Result                   : FAIL"
    echo "Reason                   : Binary version does not match PG_OLD_VERSION."

    return 1
}

check_new_pg_binary_version() {

    local reported_version
    local actual_major_version

    echo "Configured PG_NEW_VERSION : ${PG_NEW_VERSION:-<empty>}"

    if [[ -z "${PG_NEW_VERSION:-}" ]]; then
        echo "Result                   : FAIL"
        echo "Reason                   : PG_NEW_VERSION is empty."
        return 1
    fi

    reported_version="$("$NEW_PG_BIN/pg_config" --version)" || {
        echo "Result                   : FAIL"
        echo "Reason                   : Unable to execute pg_config."
        return 1
    }

    echo "pg_config output         : $reported_version"

    actual_major_version="${reported_version#PostgreSQL }"

    if [[ "$actual_major_version" =~ ^([0-9]+)\.([0-9]+)\. ]]; then
        # PostgreSQL 9.x
        actual_major_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    elif [[ "$actual_major_version" =~ ^([0-9]+)\. ]]; then
        # PostgreSQL 10+
        actual_major_version="${BASH_REMATCH[1]}"
    else
        echo "Result                   : FAIL"
        echo "Reason                   : Unable to determine PostgreSQL major version."
        return 1
    fi

    echo "Detected major version   : $actual_major_version"

    if [[ "$actual_major_version" == "$PG_NEW_VERSION" ]]; then
        echo "Result                   : PASS"
        echo "Reason                   : Binary version matches PG_NEW_VERSION."
        return 0
    fi

    echo "Result                   : FAIL"
    echo "Reason                   : Binary version does not match PG_NEW_VERSION."

    return 1
}

check_old_data_dir() {

    echo "Configured OLD_DATA_DIR : ${OLD_DATA_DIR:-<empty>}"

    if [[ -z "${OLD_DATA_DIR:-}" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : OLD_DATA_DIR Variable is empty."
        return 1
    fi

    if [[ ! -d "$OLD_DATA_DIR" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : OLD_DATA_DIR does not exist or is not a directory."
        return 1
    fi

    if [[ ! -r "$OLD_DATA_DIR" || ! -x "$OLD_DATA_DIR" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : OLD_DATA_DIR is not accessible."
        return 1
    fi

    echo "Result                  : PASS"
    echo "Reason                  : OLD_DATA_DIR exists and is accessible."

    return 0
}

check_old_pg_cluster() {

    local pg_version_file
    local cluster_version

    pg_version_file="$OLD_DATA_DIR/PG_VERSION"

    echo "Old data directory : $OLD_DATA_DIR"

    if [[ ! -f "$pg_version_file" ]]; then
        echo "Result              : FAIL"
        echo "Reason              : PG_VERSION file does not exist in OLD_DATA_DIR."
        return 1
    fi

    cluster_version="$(cat "$pg_version_file")" || {
        echo "Result              : FAIL"
        echo "Reason              : Unable to read PG_VERSION."
        return 1
    }

    echo "PG_VERSION          : $cluster_version"

    if [[ "$cluster_version" == "$PG_OLD_VERSION" ]]; then
        echo "Result              : PASS"
        echo "Reason              : OLD_DATA_DIR contains a PostgreSQL cluster matching PG_OLD_VERSION."
        return 0
    fi

    echo "Result              : FAIL"
    echo "Reason              : PG_VERSION does not match PG_OLD_VERSION."

    return 1
}

check_new_data_dir() {

    echo "Configured NEW_DATA_DIR : ${NEW_DATA_DIR:-<empty>}"

    if [[ -z "${NEW_DATA_DIR:-}" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : NEW_DATA_DIR Variable is empty."
        return 1
    fi

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : NEW_DATA_DIR does not exist or is not a directory."
        return 1
    fi

    if [[ ! -r "$NEW_DATA_DIR" || ! -w "$NEW_DATA_DIR" || ! -x "$NEW_DATA_DIR" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : NEW_DATA_DIR is not accessible."
        return 1
    fi

    if [[ -n "$(ls -A "$NEW_DATA_DIR")" ]]; then
        echo "Result                  : FAIL"
        echo "Reason                  : NEW_DATA_DIR is not empty."
        return 1
    fi

    echo "Result                  : PASS"
    echo "Reason                  : NEW_DATA_DIR exists, is accessible, and is empty."

    return 0
}

check_data_dir_owner() {

    local old_owner
    local new_owner

    old_owner="$(stat -c '%U' "$OLD_DATA_DIR")" || {
        echo "Result              : FAIL"
        echo "Reason              : Unable to determine owner of OLD_DATA_DIR."
        return 1
    }

    new_owner="$(stat -c '%U' "$NEW_DATA_DIR")" || {
        echo "Result              : FAIL"
        echo "Reason              : Unable to determine owner of NEW_DATA_DIR."
        return 1
    }

    echo "Expected owner      : $PG_OS_USER"
    echo "OLD_DATA_DIR owner  : $old_owner"
    echo "NEW_DATA_DIR owner  : $new_owner"

    if [[ "$old_owner" != "$PG_OS_USER" ]]; then
        echo "Result              : FAIL"
        echo "Reason              : OLD_DATA_DIR is not owned by PG_OS_USER."
        return 1
    fi

    if [[ "$new_owner" != "$PG_OS_USER" ]]; then
        echo "Result              : FAIL"
        echo "Reason              : NEW_DATA_DIR is not owned by PG_OS_USER."
        return 1
    fi

    echo "Result              : PASS"
    echo "Reason              : Both data directories are owned by PG_OS_USER."

    return 0
}

check_pg_systemctl_services() {

    echo "Old service name : ${OLD_PG_SYSTEMCTL_SERVICE_NAME:-<empty>}"
    echo "New service name : ${NEW_PG_SYSTEMCTL_SERVICE_NAME:-<empty>}"

    if [[ -z "${OLD_PG_SYSTEMCTL_SERVICE_NAME:-}" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : OLD_PG_SYSTEMCTL_SERVICE_NAME configuration variable is empty."
        return 1
    fi

    if [[ -z "${NEW_PG_SYSTEMCTL_SERVICE_NAME:-}" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : NEW_PG_SYSTEMCTL_SERVICE_NAME configuration variable is empty."
        return 1
    fi

    if ! systemctl cat "$OLD_PG_SYSTEMCTL_SERVICE_NAME" >/dev/null 2>&1; then
        echo "Result           : FAIL"
        echo "Reason           : Old PostgreSQL systemd service does not exist."
        return 1
    fi

    if ! systemctl cat "$NEW_PG_SYSTEMCTL_SERVICE_NAME" >/dev/null 2>&1; then
        echo "Result           : FAIL"
        echo "Reason           : New PostgreSQL systemd service does not exist."
        return 1
    fi

    echo "Result           : PASS"
    echo "Reason           : Both PostgreSQL systemd services exist."

    return 0
}

check_old_pg_service_datadir() {

    local systemd_environment
    local systemd_pgdata

    echo "Old service name : $OLD_PG_SYSTEMCTL_SERVICE_NAME"
    echo "Expected data dir: $OLD_DATA_DIR"

    systemd_environment="$(
        systemctl show "$OLD_PG_SYSTEMCTL_SERVICE_NAME" -p Environment --value
    )" || {
        echo "Result           : FAIL"
        echo "Reason           : Unable to read systemd service environment."
        return 1
    }

    systemd_pgdata=""

    for env_var in $systemd_environment; do
        if [[ "$env_var" == PGDATA=* ]]; then
            systemd_pgdata="${env_var#PGDATA=}"
            break
        fi
    done

    if [[ -z "$systemd_pgdata" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : PGDATA is not configured in the systemd service."
        return 1
    fi

    # Remove trailing slashes for comparison.
    systemd_pgdata="${systemd_pgdata%/}"
    local expected_data_dir="${OLD_DATA_DIR%/}"

    echo "Systemd PGDATA   : $systemd_pgdata"

    if [[ "$systemd_pgdata" != "$expected_data_dir" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : Systemd PGDATA does not match OLD_DATA_DIR."
        return 1
    fi

    echo "Result           : PASS"
    echo "Reason           : Systemd PGDATA matches OLD_DATA_DIR."

    return 0
}

check_old_pg_service_status() {

    echo "Old service name : $OLD_PG_SYSTEMCTL_SERVICE_NAME"

    if ! systemctl is-active --quiet "$OLD_PG_SYSTEMCTL_SERVICE_NAME"; then
        echo "Result           : FAIL"
        echo "Reason           : Old PostgreSQL systemd service is not running."
        return 1
    fi

    echo "Result           : PASS"
    echo "Reason           : Old PostgreSQL systemd service is running."

    return 0
}

check_new_pg_service_datadir() {

    local systemd_environment
    local systemd_pgdata
    local expected_data_dir

    echo "New service name : $NEW_PG_SYSTEMCTL_SERVICE_NAME"
    echo "Expected data dir: $NEW_DATA_DIR"

    systemd_environment="$(
        systemctl show "$NEW_PG_SYSTEMCTL_SERVICE_NAME" -p Environment --value
    )" || {
        echo "Result           : FAIL"
        echo "Reason           : Unable to read systemd service environment."
        return 1
    }

    systemd_pgdata=""

    for env_var in $systemd_environment; do
        if [[ "$env_var" == PGDATA=* ]]; then
            systemd_pgdata="${env_var#PGDATA=}"
            break
        fi
    done

    if [[ -z "$systemd_pgdata" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : PGDATA is not configured in the new systemd service."
        return 1
    fi

    systemd_pgdata="${systemd_pgdata%/}"
    expected_data_dir="${NEW_DATA_DIR%/}"

    echo "Systemd PGDATA   : $systemd_pgdata"

    if [[ "$systemd_pgdata" != "$expected_data_dir" ]]; then
        echo "Result           : FAIL"
        echo "Reason           : Systemd PGDATA does not match NEW_DATA_DIR."
        return 1
    fi

    echo "Result           : PASS"
    echo "Reason           : Systemd PGDATA matches NEW_DATA_DIR."

    return 0
}

check_new_pg_service_status() {

    echo "New service name : $NEW_PG_SYSTEMCTL_SERVICE_NAME"

    if systemctl is-active --quiet "$NEW_PG_SYSTEMCTL_SERVICE_NAME"; then
        echo "Result           : FAIL"
        echo "Reason           : New PostgreSQL systemd service is running."
        return 1
    fi

    echo "Result           : PASS"
    echo "Reason           : New PostgreSQL systemd service is stopped."

    return 0
}

check_pg_packages() {

    local old_components
    local new_components

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo

    old_components="$(
        rpm -qa --queryformat '%{NAME}\n' |
        grep "^postgresql${PG_OLD_VERSION}\($\|-\\)" |
        sed "s/^postgresql${PG_OLD_VERSION}//" |
        sed 's/^-//' |
        sed 's/^$/base/' |
        sort
    )"

    new_components="$(
        rpm -qa --queryformat '%{NAME}\n' |
        grep "^postgresql${PG_NEW_VERSION}\($\|-\\)" |
        sed "s/^postgresql${PG_NEW_VERSION}//" |
        sed 's/^-//' |
        sed 's/^$/base/' |
        sort
    )"

    echo "Old package components:"
    echo "$old_components"
    echo

    echo "New package components:"
    echo "$new_components"
    echo

    if [[ -z "$old_components" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : No PostgreSQL $PG_OLD_VERSION packages are installed."
        return 1
    fi

    if [[ -z "$new_components" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : No PostgreSQL $PG_NEW_VERSION packages are installed."
        return 1
    fi

    if [[ "$old_components" != "$new_components" ]]; then

        echo "Result                 : FAIL"
        echo "Reason                 : PostgreSQL package components do not match."

        echo
        echo "Missing components in new PostgreSQL version:"
        comm -23 \
            <(echo "$old_components") \
            <(echo "$new_components")

        echo
        echo "Additional components in new PostgreSQL version:"
        comm -13 \
            <(echo "$old_components") \
            <(echo "$new_components")

        return 1
    fi

    echo "Result                 : PASS"
    echo "Reason                 : PostgreSQL package components match between old and new versions."

    return 0
}

check_pg_cron() {

    local old_pg_cron_package
    local new_pg_cron_package

    old_pg_cron_package="pg_cron_${PG_OLD_VERSION}"
    new_pg_cron_package="pg_cron_${PG_NEW_VERSION}"

    echo "Old pg_cron package : $old_pg_cron_package"
    echo "New pg_cron package : $new_pg_cron_package"
    echo

    if rpm -q "$old_pg_cron_package" >/dev/null 2>&1; then

        echo "Old pg_cron package : INSTALLED"

        if rpm -q "$new_pg_cron_package" >/dev/null 2>&1; then
            echo "New pg_cron package : INSTALLED"
            echo
            echo "Result               : PASS"
            echo "Reason               : pg_cron is installed for both PostgreSQL versions."
            return 0
        fi

        echo "New pg_cron package : NOT INSTALLED"
        echo
        echo "Result               : FAIL"
        echo "Reason               : pg_cron is installed for the old PostgreSQL version but not for the new PostgreSQL version."
        return 1
    fi

    echo "Old pg_cron package : NOT INSTALLED"
    echo

    echo "Result               : PASS"
    echo "Reason               : pg_cron is not installed for the old PostgreSQL version; no corresponding package is required for the new version."

    return 0
}

check_extensions() {

    local contrib_package
    local installed_extensions
    local contrib_extensions=""
    local extension
    local external_extensions=""

    contrib_package="postgresql${PG_OLD_VERSION}-contrib"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Contrib package        : $contrib_package"
    echo

    installed_extensions="$(
        psql -Atc "
            SELECT extname
            FROM pg_extension
            ORDER BY extname;
        "
    )" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to retrieve installed extensions from the old PostgreSQL cluster."
        return 1
    }

    if rpm -q "$contrib_package" >/dev/null 2>&1; then

        contrib_extensions="$(
            rpm -ql "$contrib_package" |
            grep '/extension/.*\.control$' |
            sed 's#.*/##' |
            sed 's/\.control$//' |
            sort
        )"

    fi

    echo "Installed extensions on OLD PG Cluster:"
    echo "$installed_extensions"
    echo

    for extension in $installed_extensions; do

        if [[ "$extension" == "plpgsql" ]]; then
            continue
        fi

        if ! echo "$contrib_extensions" | grep -Fxq "$extension"; then
            external_extensions+="$extension"$'\n'
        fi

    done

    if [[ -n "$external_extensions" ]]; then

        echo "External/non-contrib extensions detected:"
        echo "$external_extensions"

        echo "Result                 : FAIL"
        echo "Reason                 : One or more installed extensions are not built-in or provided by the PostgreSQL contrib package. Manual review is required."

        return 1
    fi

    echo "Result                 : PASS"
    echo "Reason                 : All installed extensions are built-in or provided by the PostgreSQL contrib package."

    return 0
}

check_backup_old_pg_configs() {

    local backup_dir
    local datadir_backup_dir
    local systemctl_backup_dir
    local service_file
    local conf_files

    backup_dir="$(run_dir)/backups"
    datadir_backup_dir="$backup_dir/old_PG_${PG_OLD_VERSION}_datadir_confs"
    systemctl_backup_dir="$backup_dir/old_PG_${PG_OLD_VERSION}_systemctl_confs"

    echo "Old data directory : $OLD_DATA_DIR"
    echo "Backup directory   : $backup_dir"
    echo

    mkdir -p "$datadir_backup_dir" "$systemctl_backup_dir" || {
        echo "Result             : FAIL"
        echo "Reason             : Unable to create PostgreSQL configuration backup directories."
        return 1
    }

    conf_files=( "$OLD_DATA_DIR"/*conf* )

    if [[ ! -e "${conf_files[0]}" ]]; then
        echo "Result             : FAIL"
        echo "Reason             : No *conf* files were found in OLD_DATA_DIR."
        return 1
    fi

    echo "Configuration files to backup:"
    printf '%s\n' "${conf_files[@]}"
    echo

    cp -a "${conf_files[@]}" "$datadir_backup_dir/" || {
        echo "Result             : FAIL"
        echo "Reason             : Unable to backup configuration files from OLD_DATA_DIR."
        return 1
    }

    service_file="$(
        systemctl show \
            "$OLD_PG_SYSTEMCTL_SERVICE_NAME" \
            -p FragmentPath \
            --value
    )" || {
        echo "Result             : FAIL"
        echo "Reason             : Unable to determine the systemd service file path."
        return 1
    }

    if [[ -z "$service_file" || ! -f "$service_file" ]]; then
        echo "Result             : FAIL"
        echo "Reason             : PostgreSQL systemd service file does not exist."
        return 1
    fi

    echo "Systemd service file:"
    echo "$service_file"
    echo

    cp -a "$service_file" "$systemctl_backup_dir/" || {
        echo "Result             : FAIL"
        echo "Reason             : Unable to backup PostgreSQL systemd service file."
        return 1
    }

    echo "Result             : PASS"
    echo "Reason             : Old PostgreSQL configuration files and systemd service file were backed up."

    return 0
}

prepare_new_pg_configs_hba_ident() {

    local backup_dir
    local old_config_dir
    local prepared_config_dir

    backup_dir="$(run_dir)/backups"
    old_config_dir="$backup_dir/old_PG_${PG_OLD_VERSION}_datadir_confs"
    prepared_config_dir="$backup_dir/prepared_PG_${PG_NEW_VERSION}_datadir_confs"

    echo "Old configuration directory : $old_config_dir"
    echo "Prepared configuration dir   : $prepared_config_dir"
    echo

    mkdir -p "$prepared_config_dir" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to create prepared configuration directory."
        return 1
    }

    if [[ ! -f "$old_config_dir/pg_hba.conf" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : pg_hba.conf was not found in the old configuration backup."
        return 1
    fi

    if [[ ! -f "$old_config_dir/pg_ident.conf" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : pg_ident.conf was not found in the old configuration backup."
        return 1
    fi

    cp -a \
        "$old_config_dir/pg_hba.conf" \
        "$old_config_dir/pg_ident.conf" \
        "$prepared_config_dir/" || {
            echo "Result                 : FAIL"
            echo "Reason                 : Unable to copy pg_hba.conf and pg_ident.conf."
            return 1
        }

    echo "Copied:"
    echo "  pg_hba.conf"
    echo "  pg_ident.conf"
    echo

    echo "Result                 : PASS"
    echo "Reason                 : pg_hba.conf and pg_ident.conf were copied unchanged."

    return 0
}

check_old_pg_pending_restart() {

    local pending_count

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Old data directory      : $OLD_DATA_DIR"
    echo

    pending_count="$(
        "$OLD_PG_BIN/psql" \
            -X \
            -v ON_ERROR_STOP=1 \
            -Atqc "
                SELECT count(*)
                FROM pg_settings
                WHERE pending_restart = true;
            "
    )" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to check pending_restart from the old PostgreSQL cluster."
        return 1
    }

    echo "Pending restart parameters : $pending_count"
    echo

    if [[ "$pending_count" -gt 0 ]]; then

        echo "Parameters pending restart:"
        echo

        "$OLD_PG_BIN/psql" \
            -X \
            -v ON_ERROR_STOP=1 \
            -c "
                SELECT
                    name,
                    setting,
                    source,
                    sourcefile,
                    sourceline
                FROM pg_settings
                WHERE pending_restart = true
                ORDER BY name;
            " || {
                echo
                echo "Result                 : FAIL"
                echo "Reason                 : Configuration parameters are pending restart."
                echo "                         Unable to display the complete pending-restart list."
                return 1
            }

        echo
        echo "Result                 : FAIL"
        echo "Reason                 : One or more PostgreSQL configuration parameters are pending restart."

        return 1
    fi

    echo "Result                 : PASS"
    echo "Reason                 : No PostgreSQL configuration parameters are pending restart."

    return 0
}

collect_old_config_inventory() {

    local backup_dir
    local parms_dir
    local inventory_file
    local parameter_count

    backup_dir="$(run_dir)/backups"
    parms_dir="$backup_dir/parms"
    inventory_file="$parms_dir/old_config_inventory.csv"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Old data directory      : $OLD_DATA_DIR"
    echo "Parameter directory     : $parms_dir"
    echo "Inventory file          : $inventory_file"
    echo

    mkdir -p "$parms_dir" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to create parameter directory."
        return 1
    }

    "$OLD_PG_BIN/psql" \
        -X \
        -v ON_ERROR_STOP=1 \
        -c "
            COPY (
  		SELECT
    			name,
   			setting,
    			boot_val,
    			reset_val,
    			min_val,
    			max_val,
    			enumvals,
    			vartype,
    			unit,
    			context,
    			pending_restart,
    			source,
    			sourcefile,
    			sourceline
		FROM pg_settings
		WHERE sourcefile IS NOT NULL
		ORDER BY name          	
		)
            TO STDOUT
            WITH (FORMAT csv, HEADER true);
        " > "$inventory_file" || {
            echo "Result                 : FAIL"
            echo "Reason                 : Unable to collect old PostgreSQL parameter information."
            return 1
        }

    if [[ ! -s "$inventory_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Old parameter inventory file was not created or is empty."
        return 1
    fi

    parameter_count="$(
        tail -n +2 "$inventory_file" | wc -l
    )"

    echo "Parameters inventoried : $parameter_count"
    echo "Inventory file         : $inventory_file"
    echo

    echo "Result                 : PASS"
    echo "Reason                 : Old PostgreSQL parameter information was collected successfully."

    return 0
}

collect_old_initdb_profile() {
    local backup_dir
    local parms_dir
    local profile_file

    local template0_info
    local encoding
    local lc_collate
    local lc_ctype
    local locale_provider
    local data_checksums

    backup_dir="$(run_dir)/backups"
    parms_dir="$backup_dir/parms"
    profile_file="$parms_dir/old_initdb_profile.csv"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Reference database     : template0"
    echo "Profile file           : $profile_file"
    echo

    mkdir -p "$parms_dir" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to create parameter directory."
        return 1
    }

    # ------------------------------------------------------------
    # Collect template0 encoding, LC_COLLATE and LC_CTYPE
    # ------------------------------------------------------------

    template0_info="$(
        "$OLD_PG_BIN/psql" \
            -X \
            -v ON_ERROR_STOP=1 \
            -Atqc "
                SELECT
                    pg_encoding_to_char(encoding),
                    datcollate,
                    datctype
                FROM pg_database
                WHERE datname = 'template0';
            "
    )" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to collect template0 initialization properties."
        return 1
    }

    if [[ -z "$template0_info" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : template0 database was not found."
        return 1
    fi

    IFS='|' read -r encoding lc_collate lc_ctype <<< "$template0_info"

    echo "Encoding               : $encoding"
    echo "LC_COLLATE             : $lc_collate"
    echo "LC_CTYPE               : $lc_ctype"

    if [[ -z "$encoding" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : template0 encoding is empty."
        return 1
    fi

    if [[ -z "$lc_collate" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : template0 LC_COLLATE is empty."
        return 1
    fi

    if [[ -z "$lc_ctype" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : template0 LC_CTYPE is empty."
        return 1
    fi

    # ------------------------------------------------------------
    # Collect locale provider
    # ------------------------------------------------------------

    if (( PG_OLD_VERSION >= 15 )); then
        locale_provider="$(
            "$OLD_PG_BIN/psql" \
                -X \
                -v ON_ERROR_STOP=1 \
                -Atqc "
                    SELECT
                        CASE datlocprovider
                            WHEN 'b' THEN 'builtin'
                            WHEN 'c' THEN 'libc'
                            WHEN 'i' THEN 'icu'
                            ELSE NULL
                        END
                    FROM pg_database
                    WHERE datname = 'template0';
                "
        )" || {
            echo "Result                 : FAIL"
            echo "Reason                 : Unable to determine locale provider from template0."
            return 1
        }
    else
        locale_provider="libc"
    fi

    if [[ -z "$locale_provider" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to determine locale provider."
        return 1
    fi

    echo "Locale Provider        : $locale_provider"

    # ------------------------------------------------------------
    # Collect data checksum status
    # ------------------------------------------------------------

    data_checksums="$(
        "$OLD_PG_BIN/psql" \
            -X \
            -v ON_ERROR_STOP=1 \
            -Atqc "SHOW data_checksums;"
    )" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to determine data checksum status."
        return 1
    }

    if [[ "$data_checksums" != "on" && "$data_checksums" != "off" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Unexpected data_checksums value: '$data_checksums'."
        return 1
    fi

    echo "Data Checksums         : $data_checksums"
    echo

    # ------------------------------------------------------------
    # Write profile only after all properties were collected
    # successfully.
    # ------------------------------------------------------------

    {
        printf '%s\n' 'property,value,source'
        printf '%s\n' "encoding,$encoding,pg_database.template0"
        printf '%s\n' "lc_collate,$lc_collate,pg_database.template0"
        printf '%s\n' "lc_ctype,$lc_ctype,pg_database.template0"
        printf '%s\n' "locale_provider,$locale_provider,version-aware"
        printf '%s\n' "data_checksums,$data_checksums,SHOW data_checksums"
    } > "$profile_file" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to write old initialization profile."
        return 1
    }

    if [[ ! -s "$profile_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Old initialization profile was not created or is empty."
        return 1
    fi

    echo "Initialization profile :"
    cat "$profile_file"
    echo

    echo "Result                 : PASS"
    echo "Reason                 : Old PostgreSQL initialization properties were collected and saved successfully."

    return 0
}

initialize_temp_new_cluster() {
    local backup_dir
    local parms_dir
    local profile_file
    local temp_dir
    local temp_data_dir

    local encoding
    local lc_collate
    local lc_ctype
    local locale_provider
    local data_checksums

    local initdb_cmd

    backup_dir="$(run_dir)/backups"
    parms_dir="$backup_dir/parms"
    profile_file="$parms_dir/old_initdb_profile.csv"

    temp_dir="$(run_dir)/temp/PG_${PG_NEW_VERSION}"
    temp_data_dir="$temp_dir/data"

    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Profile file           : $profile_file"
    echo "Temporary holder dir  : $temp_dir"
    echo "Temporary data dir     : $temp_data_dir"
    echo

    # ------------------------------------------------------------
    # Validate profile
    # ------------------------------------------------------------

    if [[ ! -f "$profile_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Old initialization profile does not exist."
        return 1
    fi

    # ------------------------------------------------------------
    # Read initialization profile
    # ------------------------------------------------------------

    encoding="$(
        awk -F',' '$1 == "encoding" {print $2}' "$profile_file"
    )"

    lc_collate="$(
        awk -F',' '$1 == "lc_collate" {print $2}' "$profile_file"
    )"

    lc_ctype="$(
        awk -F',' '$1 == "lc_ctype" {print $2}' "$profile_file"
    )"

    locale_provider="$(
        awk -F',' '$1 == "locale_provider" {print $2}' "$profile_file"
    )"

    data_checksums="$(
        awk -F',' '$1 == "data_checksums" {print $2}' "$profile_file"
    )"

    # ------------------------------------------------------------
    # Validate collected values
    # ------------------------------------------------------------

    if [[ -z "$encoding" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Encoding is missing from the initialization profile."
        return 1
    fi

    if [[ -z "$lc_collate" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : LC_COLLATE is missing from the initialization profile."
        return 1
    fi

    if [[ -z "$lc_ctype" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : LC_CTYPE is missing from the initialization profile."
        return 1
    fi

    if [[ -z "$locale_provider" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Locale provider is missing from the initialization profile."
        return 1
    fi

    if [[ "$data_checksums" != "on" && "$data_checksums" != "off" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Invalid data_checksums value: '$data_checksums'."
        return 1
    fi

    echo "Initialization profile:"
    echo "  Encoding             : $encoding"
    echo "  LC_COLLATE           : $lc_collate"
    echo "  LC_CTYPE             : $lc_ctype"
    echo "  Locale Provider      : $locale_provider"
    echo "  Data Checksums       : $data_checksums"
    echo

    # ------------------------------------------------------------
    # Validate temporary data directory
    # ------------------------------------------------------------

    if [[ -e "$temp_data_dir" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Temporary data directory already exists."
        echo "                         $temp_data_dir"
        return 1
    fi

    mkdir -p "$temp_dir" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to create temporary holder directory."
        return 1
    }

    # ------------------------------------------------------------
    # Build initdb command
    # ------------------------------------------------------------

    initdb_cmd=(
        "$NEW_PG_BIN/initdb"
        "--pgdata=$temp_data_dir"
        "--encoding=$encoding"
        "--lc-collate=$lc_collate"
        "--lc-ctype=$lc_ctype"
        "--locale-provider=$locale_provider"
    )

    # ------------------------------------------------------------
    # Version-aware checksum handling
    # ------------------------------------------------------------

    if [[ "$data_checksums" == "on" ]]; then
        initdb_cmd+=( "--data-checksums" )
    elif (( PG_NEW_VERSION >= 18 )); then
        initdb_cmd+=( "--no-data-checksums" )
    fi

    echo "initdb command:"
    printf '  %q ' "${initdb_cmd[@]}"
    echo
    echo

    # ------------------------------------------------------------
    # Initialize temporary cluster
    # ------------------------------------------------------------

    "${initdb_cmd[@]}" || {
        echo
        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL cluster initialization failed."
        return 1
    }

    # ------------------------------------------------------------
    # Verify initialization
    # ------------------------------------------------------------

    if [[ ! -f "$temp_data_dir/PG_VERSION" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : PG_VERSION was not created in temporary data directory."
        return 1
    fi

    if [[ "$(cat "$temp_data_dir/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Temporary cluster PG_VERSION does not match PG_NEW_VERSION."
        return 1
    fi

    echo
    echo "Result                 : PASS"
    echo "Reason                 : Temporary PostgreSQL $PG_NEW_VERSION cluster was initialized successfully."

    return 0
}

start_temp_new_cluster() {
    local temp_dir
    local temp_data_dir
    local temp_log_file

    temp_dir="$(run_dir)/temp/PG_${PG_NEW_VERSION}"
    temp_data_dir="$temp_dir/data"
    temp_log_file="$temp_dir/postgresql.log"

    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Temporary holder dir   : $temp_dir"
    echo "Temporary data dir     : $temp_data_dir"
    echo "Temporary port         : 7433"
    echo "Temporary log file     : $temp_log_file"
    echo

    # ------------------------------------------------------------
    # Validate temporary data directory
    # ------------------------------------------------------------

    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL data directory does not exist."
        return 1
    fi

    if [[ ! -f "$temp_data_dir/PG_VERSION" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : PG_VERSION does not exist in temporary data directory."
        return 1
    fi

    # ------------------------------------------------------------
    # Make sure temporary cluster is not already running
    # ------------------------------------------------------------

    if "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        status >/dev/null 2>&1; then

        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL cluster is already running."
        return 1
    fi

    # ------------------------------------------------------------
    # Start temporary PostgreSQL cluster
    # ------------------------------------------------------------

    echo "Starting temporary PostgreSQL cluster..."
    echo

    "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        -l "$temp_log_file" \
        -o "-p 7433" \
        start || {
        echo
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to start temporary PostgreSQL cluster."
        return 1
    }

    echo
    echo "pg_ctl start completed."
    echo

    # ------------------------------------------------------------
    # Verify PostgreSQL process/cluster status
    # ------------------------------------------------------------

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        status >/dev/null 2>&1; then

        echo "Result                 : FAIL"
        echo "Reason                 : PostgreSQL cluster did not remain running after pg_ctl start."
        return 1
    fi

    echo "Cluster status         : RUNNING"

    # ------------------------------------------------------------
    # Verify connection
    # ------------------------------------------------------------

    if ! "$NEW_PG_BIN/psql" \
        -X \
        -p 7433 \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -Atqc "SELECT 1;" >/dev/null 2>&1; then

        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL cluster is running but is not accepting connections on port 7433."
        return 1
    fi

    echo "Connection status      : ACCEPTING CONNECTIONS"
    echo "Port                   : 7433"
    echo

local archive_mode
local archive_command

archive_mode="$(
    "$NEW_PG_BIN/psql" \
        -X \
        -p 7433 \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -Atqc "SHOW archive_mode;"
)" || {
    echo "Result                 : FAIL"
    echo "Reason                 : Unable to determine temporary cluster archive_mode."
    return 1
}

archive_command="$(
    "$NEW_PG_BIN/psql" \
        -X \
        -p 7433 \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -Atqc "SHOW archive_command;"
)" || {
    echo "Result                 : FAIL"
    echo "Reason                 : Unable to determine temporary cluster archive_command."
    return 1
}

echo "Archive mode           : $archive_mode"
echo "Archive command        : $archive_command"

if [[ "$archive_mode" != "off" ]]; then
    echo "Result                 : FAIL"
    echo "Reason                 : Temporary PostgreSQL cluster has archive_mode enabled."
    return 1
fi

if [[ "$archive_command" != "(disabled)" ]]; then
    echo "Result                 : FAIL"
    echo "Reason                 : Temporary PostgreSQL cluster has an active archive_command."
    return 1
fi

    echo "Result                 : PASS"
    echo "Reason                 : Temporary PostgreSQL cluster is running, accepting connections on port 7433 and archiving is disabled."

    return 0
}

compare_old_config_with_temp_new() {
    local backup_dir
    local parms_dir
    local inventory_file
    local comparison_file
    local temp_data_dir

    backup_dir="$(run_dir)/backups"
    parms_dir="$backup_dir/parms"
    inventory_file="$parms_dir/old_config_inventory.csv"
    comparison_file="$parms_dir/config_comparison.csv"

    temp_data_dir="$(run_dir)/temp/PG_${PG_NEW_VERSION}/data"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Old inventory file     : $inventory_file"
    echo "Temporary data dir     : $temp_data_dir"
    echo "Temporary port         : 7433"
    echo "Comparison file        : $comparison_file"
    echo

    if [[ ! -f "$inventory_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Old configuration inventory does not exist."
        return 1
    fi

    if [[ ! -s "$inventory_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Old configuration inventory is empty."
        return 1
    fi

    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL data directory does not exist."
        return 1
    fi

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        status >/dev/null 2>&1; then

        echo "Result                 : FAIL"
        echo "Reason                 : Temporary PostgreSQL cluster is not running."
        return 1
    fi

    mkdir -p "$parms_dir" || {
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to create parameter directory."
        return 1
    }

    rm -f "$comparison_file"

    if ! "$NEW_PG_BIN/psql" \
        -X \
        -p 7433 \
        -d postgres \
        -v ON_ERROR_STOP=1 <<SQL
CREATE TEMP TABLE old_config_inventory (
    name            text,
    setting         text,
    boot_val        text,
    reset_val       text,
    min_val         text,
    max_val         text,
    enumvals        text,
    vartype         text,
    unit            text,
    context         text,
    pending_restart text,
    source          text,
    sourcefile      text,
    sourceline      text
);

\copy old_config_inventory FROM '$inventory_file' WITH (FORMAT csv, HEADER true);

COPY (
    SELECT
        old.name,

        old.setting         AS old_setting,
        old.boot_val        AS old_boot_val,
        old.reset_val       AS old_reset_val,
        old.min_val         AS old_min_val,
        old.max_val         AS old_max_val,
        old.enumvals        AS old_enumvals,
        old.vartype         AS old_vartype,
        old.unit            AS old_unit,
        old.context         AS old_context,
        old.pending_restart AS old_pending_restart,
        old.source          AS old_source,
        old.sourcefile      AS old_sourcefile,
        old.sourceline      AS old_sourceline,

        CASE
            WHEN new.name IS NULL THEN 'NO'
            ELSE 'YES'
        END                 AS new_parameter_exists,

        new.setting         AS new_setting,
        new.boot_val        AS new_boot_val,
        new.reset_val       AS new_reset_val,
        new.min_val         AS new_min_val,
        new.max_val         AS new_max_val,
        new.enumvals        AS new_enumvals,
        new.vartype         AS new_vartype,
        new.unit            AS new_unit,
        new.context         AS new_context,
        new.pending_restart AS new_pending_restart,
        new.source          AS new_source,
        new.sourcefile      AS new_sourcefile,
        new.sourceline      AS new_sourceline

    FROM old_config_inventory old

    LEFT JOIN pg_settings new
        ON new.name = old.name

    ORDER BY old.name

) TO '$comparison_file'
WITH (FORMAT csv, HEADER true);
SQL
    then
        echo "Result                 : FAIL"
        echo "Reason                 : Unable to compare old configuration parameters with the temporary PostgreSQL cluster."
        return 1
    fi

    if [[ ! -s "$comparison_file" ]]; then
        echo "Result                 : FAIL"
        echo "Reason                 : Configuration comparison file was not created or is empty."
        return 1
    fi

    echo "Comparison file created:"
    echo "  $comparison_file"
    echo

    echo "Comparison preview:"
    head -n 6 "$comparison_file"
    echo

    echo "Result                 : PASS"
    echo "Reason                 : Old configuration parameters were compared with the live temporary PostgreSQL cluster."

    return 0
}

initialize_temp_old_cluster() {
    local profile_file
    local temp_holder_dir
    local temp_data_dir
    local encoding
    local lc_collate
    local lc_ctype
    local locale_provider
    local data_checksums
    local checksum_option=""
    local initdb_cmd

    profile_file="$(run_dir)/backups/parms/old_initdb_profile.csv"
    temp_holder_dir="$(run_dir)/temp/PG_${PG_OLD_VERSION}_baseline"
    temp_data_dir="$temp_holder_dir/data"
    initdb_cmd="$OLD_PG_BIN/initdb"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Profile file           : $profile_file"
    echo "Temporary holder dir   : $temp_holder_dir"
    echo "Temporary data dir     : $temp_data_dir"

    # ------------------------------------------------------------
    # Validate required profile
    # ------------------------------------------------------------
    if [[ ! -f "$profile_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Required initdb profile file does not exist."
        return 1
    fi

    encoding="$(awk -F',' '$1=="encoding" {print $2}' "$profile_file")"
    lc_collate="$(awk -F',' '$1=="lc_collate" {print $2}' "$profile_file")"
    lc_ctype="$(awk -F',' '$1=="lc_ctype" {print $2}' "$profile_file")"
    locale_provider="$(awk -F',' '$1=="locale_provider" {print $2}' "$profile_file")"
    data_checksums="$(awk -F',' '$1=="data_checksums" {print $2}' "$profile_file")"

    if [[ -z "$encoding" ||
          -z "$lc_collate" ||
          -z "$lc_ctype" ||
          -z "$locale_provider" ||
          -z "$data_checksums" ]]; then

        echo "Result : FAIL"
        echo "Reason : One or more required initdb profile values are missing."
        return 1
    fi

    # ------------------------------------------------------------
    # Validate initdb
    # ------------------------------------------------------------
    if [[ ! -x "$initdb_cmd" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old PostgreSQL initdb executable not found: $initdb_cmd"
        return 1
    fi

    # ------------------------------------------------------------
    # Temporary directory must not already exist
    # ------------------------------------------------------------
    if [[ -e "$temp_holder_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version baseline directory already exists:"
        echo "        $temp_holder_dir"
        return 1
    fi

    mkdir -p "$temp_holder_dir"

    # ------------------------------------------------------------
    # Determine checksum option
    #
    # Checksums ON:
    #   Any PostgreSQL version -> --data-checksums
    #
    # Checksums OFF:
    #   PostgreSQL >= 18 -> --no-data-checksums
    #   PostgreSQL < 18  -> no option
    # ------------------------------------------------------------
    if [[ "$data_checksums" == "on" ]]; then
        checksum_option="--data-checksums"

    elif [[ "$data_checksums" == "off" ]]; then
        if (( PG_OLD_VERSION >= 18 )); then
            checksum_option="--no-data-checksums"
        fi

    else
        echo "Result : FAIL"
        echo "Reason : Invalid data_checksums value in initdb profile: $data_checksums"
        return 1
    fi

    # ------------------------------------------------------------
    # Build initdb command
    # ------------------------------------------------------------
    echo "Initializing fresh PostgreSQL $PG_OLD_VERSION baseline cluster..."
    echo "Encoding               : $encoding"
    echo "LC_COLLATE             : $lc_collate"
    echo "LC_CTYPE               : $lc_ctype"
    echo "Locale provider        : $locale_provider"
    echo "Data checksums         : $data_checksums"

    if [[ -n "$checksum_option" ]]; then
        echo "Checksum option        : $checksum_option"
    else
        echo "Checksum option        : none"
    fi

    if (( PG_OLD_VERSION >= 15 )); then

        if [[ -n "$checksum_option" ]]; then
            "$initdb_cmd" \
                "--pgdata=$temp_data_dir" \
                "--encoding=$encoding" \
                "--lc-collate=$lc_collate" \
                "--lc-ctype=$lc_ctype" \
                "--locale-provider=$locale_provider" \
                "$checksum_option"
        else
            "$initdb_cmd" \
                "--pgdata=$temp_data_dir" \
                "--encoding=$encoding" \
                "--lc-collate=$lc_collate" \
                "--lc-ctype=$lc_ctype" \
                "--locale-provider=$locale_provider"
        fi

    else
        # PostgreSQL versions before 15 do not support
        # --locale-provider.
        if [[ -n "$checksum_option" ]]; then
            "$initdb_cmd" \
                "--pgdata=$temp_data_dir" \
                "--encoding=$encoding" \
                "--lc-collate=$lc_collate" \
                "--lc-ctype=$lc_ctype" \
                "$checksum_option"
        else
            "$initdb_cmd" \
                "--pgdata=$temp_data_dir" \
                "--encoding=$encoding" \
                "--lc-collate=$lc_collate" \
                "--lc-ctype=$lc_ctype"
        fi
    fi

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : initdb failed while creating the temporary old-version baseline cluster."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify initialization
    # ------------------------------------------------------------
    if [[ ! -f "$temp_data_dir/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION was not created."
        return 1
    fi

    if [[ "$(cat "$temp_data_dir/PG_VERSION")" != "$PG_OLD_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary cluster PG_VERSION does not match PG_OLD_VERSION."
        echo "        Expected : $PG_OLD_VERSION"
        echo "        Actual   : $(cat "$temp_data_dir/PG_VERSION")"
        return 1
    fi

    echo "Cluster initialized successfully."
    echo "Cluster remains stopped by design."

    echo "Result : PASS"
    echo "Reason : Fresh PostgreSQL $PG_OLD_VERSION baseline cluster initialized successfully."

    return 0
}

start_temp_old_cluster() {
    local temp_holder_dir
    local temp_data_dir
    local log_file
    local temp_port=7432

    temp_holder_dir="$(run_dir)/temp/PG_${PG_OLD_VERSION}_baseline"
    temp_data_dir="$temp_holder_dir/data"
    log_file="$temp_holder_dir/postgresql.log"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Temporary data dir     : $temp_data_dir"
    echo "Temporary port         : $temp_port"
    echo "Log file               : $log_file"

    # ------------------------------------------------------------
    # Validate temporary cluster
    # ------------------------------------------------------------
    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version data directory does not exist."
        return 1
    fi

    if [[ ! -f "$temp_data_dir/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not exist in temporary old-version cluster."
        return 1
    fi

    if [[ "$(cat "$temp_data_dir/PG_VERSION")" != "$PG_OLD_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary cluster PG_VERSION does not match PG_OLD_VERSION."
        return 1
    fi

    # ------------------------------------------------------------
    # Make sure cluster is not already running
    # ------------------------------------------------------------
    if "$OLD_PG_BIN/pg_ctl" -D "$temp_data_dir" status >/dev/null 2>&1; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version cluster is already running."
        return 1
    fi

    # ------------------------------------------------------------
    # Start temporary cluster
    # ------------------------------------------------------------
    echo "Starting temporary PostgreSQL $PG_OLD_VERSION baseline cluster..."

    "$OLD_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        -l "$log_file" \
        -o "-p $temp_port" \
        start

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to start temporary old-version baseline cluster."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify pg_ctl status
    # ------------------------------------------------------------
    if ! "$OLD_PG_BIN/pg_ctl" -D "$temp_data_dir" status >/dev/null 2>&1; then
        echo "Result : FAIL"
        echo "Reason : pg_ctl reports that the temporary cluster is not running."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify SQL connectivity
    # ------------------------------------------------------------
    if ! "$OLD_PG_BIN/psql" \
        -p "$temp_port" \
        -d postgres \
        -Atqc "SELECT 1" >/dev/null 2>&1; then

        echo "Result : FAIL"
        echo "Reason : Temporary PostgreSQL $PG_OLD_VERSION cluster is running but SQL connection failed."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify this is really the expected PostgreSQL version
    # ------------------------------------------------------------
    local actual_version

    actual_version="$(
        "$OLD_PG_BIN/psql" \
            -p "$temp_port" \
            -d postgres \
            -Atqc "SHOW server_version_num"
    )"

    if [[ "${actual_version:0:${#PG_OLD_VERSION}}" != "$PG_OLD_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Running temporary cluster version does not match PG_OLD_VERSION."
        echo "        Expected major version : $PG_OLD_VERSION"
        echo "        Actual server_version_num : $actual_version"
        return 1
    fi

    echo "Temporary PostgreSQL $PG_OLD_VERSION baseline cluster is running."
    echo "Port                     : $temp_port"
    echo "SQL connectivity         : PASS"
    echo "Server version           : $actual_version"

    echo "Result : PASS"
    echo "Reason : Temporary old-version baseline cluster started successfully."

    return 0
}

collect_temp_old_config_baseline() {
    local inventory_file
    local temp_holder_dir
    local temp_data_dir
    local output_file
    local temp_port=7432
    local row_count

    inventory_file="$(run_dir)/backups/parms/old_config_inventory.csv"
    temp_holder_dir="$(run_dir)/temp/PG_${PG_OLD_VERSION}_baseline"
    temp_data_dir="$temp_holder_dir/data"
    output_file="$(run_dir)/backups/parms/old_initdb_config_baseline.csv"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Inventory file          : $inventory_file"
    echo "Temporary data dir      : $temp_data_dir"
    echo "Temporary port          : $temp_port"
    echo "Output file             : $output_file"

    # ------------------------------------------------------------
    # Validate inventory
    # ------------------------------------------------------------
    if [[ ! -f "$inventory_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old configuration inventory does not exist."
        return 1
    fi

    # ------------------------------------------------------------
    # Validate temporary cluster
    # ------------------------------------------------------------
    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version data directory does not exist."
        return 1
    fi

    if ! "$OLD_PG_BIN/pg_ctl" -D "$temp_data_dir" status >/dev/null 2>&1; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version baseline cluster is not running."
        return 1
    fi

    # ------------------------------------------------------------
    # Create output directory
    # ------------------------------------------------------------
    mkdir -p "$(dirname "$output_file")"

    # ------------------------------------------------------------
    # Create temporary table, load inventory and collect baseline
    # in the SAME PostgreSQL session.
    # ------------------------------------------------------------
    "$OLD_PG_BIN/psql" \
        -p "$temp_port" \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        <<SQL

CREATE TEMP TABLE old_config_inventory (
    name text,
    setting text,
    boot_val text,
    reset_val text,
    min_val text,
    max_val text,
    enumvals text,
    vartype text,
    unit text,
    context text,
    pending_restart boolean,
    source text,
    sourcefile text,
    sourceline integer
);

\copy old_config_inventory FROM '$inventory_file' WITH CSV HEADER

COPY (
    SELECT
        s.name,
        s.setting,
        s.boot_val,
        s.reset_val,
        s.min_val,
        s.max_val,
        s.enumvals,
        s.vartype,
        s.unit,
        s.context,
        s.pending_restart,
        s.source,
        s.sourcefile,
        s.sourceline
    FROM pg_settings s
    JOIN old_config_inventory o
      ON o.name = s.name
    ORDER BY s.name
) TO '$output_file' WITH CSV HEADER;

SQL

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to collect PG$PG_OLD_VERSION initdb configuration baseline."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify output
    # ------------------------------------------------------------
    if [[ ! -s "$output_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Configuration baseline file was not created or is empty."
        return 1
    fi

    row_count="$(tail -n +2 "$output_file" | wc -l)"

    if (( row_count == 0 )); then
        echo "Result : FAIL"
        echo "Reason : Configuration baseline contains no matching parameters."
        return 1
    fi

    echo "Configuration baseline collected successfully."
    echo "Baseline parameters     : $row_count"
    echo "Baseline file           : $output_file"

    echo "Result : PASS"
    echo "Reason : Fresh PostgreSQL $PG_OLD_VERSION baseline collected for parameters present in the old configuration inventory."

    return 0
}

stop_temp_old_cluster() {
    local temp_holder_dir
    local temp_data_dir

    temp_holder_dir="$(run_dir)/temp/PG_${PG_OLD_VERSION}_baseline"
    temp_data_dir="$temp_holder_dir/data"

    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "Temporary data dir     : $temp_data_dir"
    echo "Temporary port         : 7432"

    # ------------------------------------------------------------
    # Validate temporary cluster
    # ------------------------------------------------------------
    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version data directory does not exist."
        return 1
    fi

    # ------------------------------------------------------------
    # Check cluster status
    # ------------------------------------------------------------
    if ! "$OLD_PG_BIN/pg_ctl" -D "$temp_data_dir" status >/dev/null 2>&1; then
        echo "Cluster is already stopped."

        echo "Result : PASS"
        echo "Reason : Temporary old-version baseline cluster is already stopped."

        return 0
    fi

    # ------------------------------------------------------------
    # Stop temporary cluster
    # ------------------------------------------------------------
    echo "Stopping temporary PostgreSQL $PG_OLD_VERSION baseline cluster..."

    "$OLD_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        stop

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to stop temporary old-version baseline cluster."
        return 1
    fi

    # ------------------------------------------------------------
    # Verify stopped
    # ------------------------------------------------------------
    if "$OLD_PG_BIN/pg_ctl" -D "$temp_data_dir" status >/dev/null 2>&1; then
        echo "Result : FAIL"
        echo "Reason : Temporary old-version baseline cluster is still running."
        return 1
    fi

    echo "Temporary PostgreSQL $PG_OLD_VERSION baseline cluster stopped successfully."

    echo "Result : PASS"
    echo "Reason : Temporary old-version baseline cluster stopped successfully."

    return 0
}

generate_config_migration_plan() {
    local inventory_file
    local baseline_file
    local comparison_file
    local output_file
    local row_count
    local manual_count

    inventory_file="$(run_dir)/backups/parms/old_config_inventory.csv"
    baseline_file="$(run_dir)/backups/parms/old_initdb_config_baseline.csv"
    comparison_file="$(run_dir)/backups/parms/config_comparison.csv"
    output_file="$(run_dir)/backups/parms/config_migration_plan.csv"

    echo "Old configuration inventory : $inventory_file"
    echo "Old initdb baseline         : $baseline_file"
    echo "PG${PG_OLD_VERSION} vs PG${PG_NEW_VERSION} comparison : $comparison_file"
    echo "Migration plan              : $output_file"

    if [[ ! -s "$inventory_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old configuration inventory does not exist or is empty."
        return 1
    fi

    if [[ ! -s "$baseline_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old-version initdb configuration baseline does not exist or is empty."
        return 1
    fi

    if [[ ! -s "$comparison_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old versus new configuration comparison does not exist or is empty."
        return 1
    fi

    mkdir -p "$(dirname "$output_file")"

    "$NEW_PG_BIN/psql" \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        <<SQL

CREATE TEMP TABLE old_config_inventory (
    name text,
    setting text,
    boot_val text,
    reset_val text,
    min_val text,
    max_val text,
    enumvals text,
    vartype text,
    unit text,
    context text,
    pending_restart boolean,
    source text,
    sourcefile text,
    sourceline integer
);

CREATE TEMP TABLE old_initdb_baseline (
    name text,
    setting text,
    boot_val text,
    reset_val text,
    min_val text,
    max_val text,
    enumvals text,
    vartype text,
    unit text,
    context text,
    pending_restart boolean,
    source text,
    sourcefile text,
    sourceline integer
);

CREATE TEMP TABLE config_comparison (
    name text,
    old_setting text,
    old_boot_val text,
    old_reset_val text,
    old_min_val text,
    old_max_val text,
    old_enumvals text,
    old_vartype text,
    old_unit text,
    old_context text,
    old_pending_restart boolean,
    old_source text,
    old_sourcefile text,
    old_sourceline integer,
    new_parameter_exists boolean,
    new_setting text,
    new_boot_val text,
    new_reset_val text,
    new_min_val text,
    new_max_val text,
    new_enumvals text,
    new_vartype text,
    new_unit text,
    new_context text,
    new_pending_restart boolean,
    new_source text,
    new_sourcefile text,
    new_sourceline integer
);

\copy old_config_inventory FROM '$inventory_file' WITH CSV HEADER

\copy old_initdb_baseline FROM '$baseline_file' WITH CSV HEADER

\copy config_comparison FROM '$comparison_file' WITH CSV HEADER

COPY (
    SELECT
        c.name,
        c.old_setting,
        b.setting AS old_initdb_setting,
        c.new_parameter_exists,
        c.new_setting,

        CASE

            /*
             * Parameter does not exist in the new version.
             *
             * If the old value was only the old initdb baseline,
             * there is no customization to migrate.
             */
            WHEN NOT c.new_parameter_exists THEN
                CASE
                    WHEN b.name IS NOT NULL
                         AND c.old_setting = b.setting
                    THEN 'LEAVE_DEFAULT'

                    ELSE 'MANUAL_REVIEW'
                END

            /*
             * Parameter exists in the new version.
             *
             * First determine whether the old value was actually
             * customized. If it was not customized, no migration
             * is required.
             */
            WHEN c.old_setting = b.setting THEN
                'SKIP'

            /*
             * Enum parameter:
             *
             * The enum definition itself may have changed.
             * That is acceptable as long as the currently configured
             * old value is still a valid PG17 enum value.
             */
            WHEN c.new_vartype = 'enum'
                 AND c.old_setting IS NOT NULL
                 AND c.new_enumvals IS NOT NULL
                 AND NOT (
                     c.old_setting = ANY (
                         string_to_array(
                             trim(both '{}' from c.new_enumvals),
                             ','
                         )
                     )
                 )
            THEN 'MANUAL_REVIEW'

            /*
             * Integer / real parameter:
             *
             * Validate the actual old configured value against
             * the PG17 supported range.
             */
            WHEN c.new_vartype IN ('integer', 'real')
                 AND c.old_setting IS NOT NULL
                 AND c.old_setting ~ '^-?[0-9]+([.][0-9]+)?$'
                 AND c.new_min_val IS NOT NULL
                 AND c.old_setting::numeric < c.new_min_val::numeric
            THEN 'MANUAL_REVIEW'

            WHEN c.new_vartype IN ('integer', 'real')
                 AND c.old_setting IS NOT NULL
                 AND c.old_setting ~ '^-?[0-9]+([.][0-9]+)?$'
                 AND c.new_max_val IS NOT NULL
                 AND c.old_setting::numeric > c.new_max_val::numeric
            THEN 'MANUAL_REVIEW'

            /*
             * Type changed between versions.
             */
            WHEN c.old_vartype IS DISTINCT FROM c.new_vartype
            THEN 'MANUAL_REVIEW'

            /*
             * Parameter exists, was customized, and the old
             * configured value is compatible with PG17.
             */
            ELSE 'MIGRATE'

        END AS decision,

        CASE

            WHEN NOT c.new_parameter_exists
                 AND b.name IS NOT NULL
                 AND c.old_setting = b.setting
            THEN
                'Parameter does not exist in PG' || '$PG_NEW_VERSION' ||
                '; old value matches fresh PG' || '$PG_OLD_VERSION' ||
                ' initdb baseline.'

            WHEN NOT c.new_parameter_exists
            THEN
                'Parameter does not exist in PG' || '$PG_NEW_VERSION' ||
                ' and old value differs from fresh PG' || '$PG_OLD_VERSION' ||
                ' initdb baseline.'

            WHEN c.old_setting = b.setting
            THEN
                'Old value matches fresh PG' || '$PG_OLD_VERSION' ||
                ' initdb baseline; no DBA customization can be inferred.'

            WHEN c.new_vartype = 'enum'
                 AND c.old_setting IS NOT NULL
                 AND c.new_enumvals IS NOT NULL
                 AND NOT (
                     c.old_setting = ANY (
                         string_to_array(
                             trim(both '{}' from c.new_enumvals),
                             ','
                         )
                     )
                 )
            THEN
                'Old configured enum value is not available in PG' ||
                '$PG_NEW_VERSION' || '.'

            WHEN c.new_vartype IN ('integer', 'real')
                 AND c.old_setting IS NOT NULL
                 AND c.old_setting ~ '^-?[0-9]+([.][0-9]+)?$'
                 AND c.new_min_val IS NOT NULL
                 AND c.old_setting::numeric < c.new_min_val::numeric
            THEN
                'Old configured value is below the PG' ||
                '$PG_NEW_VERSION' || ' minimum.'

            WHEN c.new_vartype IN ('integer', 'real')
                 AND c.old_setting IS NOT NULL
                 AND c.old_setting ~ '^-?[0-9]+([.][0-9]+)?$'
                 AND c.new_max_val IS NOT NULL
                 AND c.old_setting::numeric > c.new_max_val::numeric
            THEN
                'Old configured value is above the PG' ||
                '$PG_NEW_VERSION' || ' maximum.'

            WHEN c.old_vartype IS DISTINCT FROM c.new_vartype
            THEN
                'Parameter data type changed between PostgreSQL versions.'

            ELSE
                'Old value differs from fresh PG' || '$PG_OLD_VERSION' ||
                ' initdb baseline and is compatible with PG' ||
                '$PG_NEW_VERSION' || '.'
        END AS reason,

        c.old_vartype,
        c.new_vartype,
        c.old_unit,
        c.new_unit,
        c.old_context,
        c.new_context,
        c.old_source,
        c.old_sourcefile,
        c.old_sourceline,
        c.new_min_val,
        c.new_max_val,
        c.new_enumvals

    FROM config_comparison c

    LEFT JOIN old_initdb_baseline b
      ON b.name = c.name

    ORDER BY c.name
) TO '$output_file' WITH CSV HEADER;

SQL

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to generate configuration migration plan."
        return 1
    fi

    if [[ ! -s "$output_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Configuration migration plan was not created or is empty."
        return 1
    fi

    row_count="$(tail -n +2 "$output_file" | wc -l)"

    if (( row_count == 0 )); then
        echo "Result : FAIL"
        echo "Reason : Configuration migration plan contains no parameters."
        return 1
    fi

    manual_count="$(
        awk -F',' '
            NR > 1 && $6 == "MANUAL_REVIEW" { count++ }
            END { print count + 0 }
        ' "$output_file"
    )"

    echo "Configuration migration plan generated successfully."
    echo "Plan parameters            : $row_count"
    echo "Manual review parameters   : $manual_count"
    echo "Plan file                  : $output_file"

    echo "Result : PASS"
    echo "Reason : Configuration migration plan generated successfully."

    return 0
}

display_config_migration_plan() {
    local plan_file
    local yellow
    local orange
    local red
    local reset
    local display_output

    plan_file="$(run_dir)/backups/parms/config_migration_plan.csv"

    green=$'\033[32m'
    yellow=$'\033[33m'
    orange=$'\033[38;5;208m'
    red=$'\033[31m'
    reset=$'\033[0m'

    sleep 2

    echo "Configuration migration plan : $plan_file"

    if [[ ! -f "$plan_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Configuration migration plan file does not exist."
        return 1
    fi

    display_output="$(
        "$OLD_PG_BIN/psql" \
            -d postgres \
            -v ON_ERROR_STOP=1 \
            -X \
            -q \
            -P pager=off \
            -At \
            -F $'\t' \
            <<SQL
CREATE TEMP TABLE config_migration_plan (
    name text,
    old_setting text,
    old_initdb_setting text,
    new_parameter_exists boolean,
    new_setting text,
    decision text,
    reason text,
    old_vartype text,
    new_vartype text,
    old_unit text,
    new_unit text,
    old_context text,
    new_context text,
    old_source text,
    old_sourcefile text,
    old_sourceline integer,
    new_min_val text,
    new_max_val text,
    new_enumvals text
);

\copy config_migration_plan FROM '$plan_file' WITH CSV HEADER

SELECT
    name,
    old_setting,
    COALESCE(new_setting, '-'),
    decision,
    reason
FROM config_migration_plan
ORDER BY name;
SQL
    )"

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to read configuration migration plan."
        return 1
    fi

    {
        echo
        echo "Configuration Migration Plan"
        echo "============================"
        echo

        printf "%-35s %-30s %-30s %-18s\n" \
            "PARAMETER" "OLD VALUE" "NEW VALUE" "DECISION"

        printf "%-35s %-30s %-30s %-18s\n" \
            "-----------------------------------" \
            "------------------------------" \
            "------------------------------" \
            "------------------"

        while IFS=$'\t' read -r name old_setting new_setting decision reason
        do
            case "$decision" in
                MIGRATE)
                    printf "%-35s %-30s %-30s ${green}%-18s${reset}\n" \
                        "$name" "$old_setting" "$new_setting" "$decision"
                    ;;

                SKIP)
                    printf "%-35s %-30s %-30s ${yellow}%-18s${reset}\n" \
                        "$name" "$old_setting" "$new_setting" "$decision"
                    ;;

                LEAVE_DEFAULT)
                    printf "%-35s %-30s %-30s ${orange}%-18s${reset}\n" \
                        "$name" "$old_setting" "$new_setting" "$decision"
                    ;;

                MANUAL_REVIEW)
                    printf "%-35s %-30s %-30s ${red}%-18s${reset}\n" \
                        "$name" "$old_setting" "$new_setting" "$decision"
                    ;;

                *)
                    printf "%-35s %-30s %-30s ${red}%-18s${reset}\n" \
                        "$name" "$old_setting" "$new_setting" "UNKNOWN"
                    ;;
            esac

            printf "    Reason : %s\n" "$reason"
            echo

        done <<< "$display_output"

    } | tee /dev/tty

    echo
    echo "Result : PASS"
    echo "Reason : Configuration migration plan displayed successfully."

    return 0
}

generate_postgresql_auto_conf() {
    local plan_file
    local output_file
    local prepared_dir
    local temp_output
    local plan_rows

    local old_archive_command
    local transformed_archive_command
    local archive_command
    local archive_before_f
    local archive_path
    local archive_parent
    local archive_old_dir
    local archive_tmp_dir
    local archive_tmp_path

    local name
    local old_setting
    local new_setting
    local decision
    local reason

    plan_file="$(run_dir)/backups/parms/config_migration_plan.csv"
    prepared_dir="$(run_dir)/backups/prepared_PG_${PG_NEW_VERSION}_datadir_confs"
    output_file="$prepared_dir/postgresql.auto.conf"
    temp_output="$output_file.tmp"
    plan_rows="$(run_dir)/temp/config_migration_plan.tsv"

    echo "Configuration migration plan : $plan_file"
    echo "Prepared configuration dir  : $prepared_dir"
    echo "Output file                 : $output_file"

    if [[ ! -f "$plan_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Configuration migration plan file does not exist."
        return 1
    fi

    if [[ ! -d "$prepared_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Prepared PostgreSQL configuration directory does not exist."
        return 1
    fi

    if [[ -f "$output_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : postgresql.auto.conf already exists. Remove it before regenerating."
        return 1
    fi

    rm -f "$temp_output"
    rm -f "$plan_rows"

    "$OLD_PG_BIN/psql" \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -X \
        -q \
        -At \
        -F $'\t' \
        <<SQL > "$plan_rows"
CREATE TEMP TABLE config_migration_plan (
    name text,
    old_setting text,
    old_initdb_setting text,
    new_parameter_exists boolean,
    new_setting text,
    decision text,
    reason text,
    old_vartype text,
    new_vartype text,
    old_unit text,
    new_unit text,
    old_context text,
    new_context text,
    old_source text,
    old_sourcefile text,
    old_sourceline integer,
    new_min_val text,
    new_max_val text,
    new_enumvals text
);

\copy config_migration_plan FROM '$plan_file' WITH CSV HEADER

SELECT
    name,
    old_setting,
    COALESCE(new_setting, ''),
    decision,
    reason
FROM config_migration_plan
ORDER BY name;
SQL

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to read configuration migration plan."
        rm -f "$plan_rows"
        return 1
    fi

    echo
    echo "Generating PostgreSQL $PG_NEW_VERSION postgresql.auto.conf..."
    echo

    while IFS=$'\t' read -r name old_setting new_setting decision reason
    do
        case "$decision" in

            MIGRATE)

                if [[ "$name" == "archive_command" ]]; then

                    old_archive_command="$old_setting"

                    if [[ "$old_archive_command" != *"%f"* ]]; then
                        echo "Result : FAIL"
                        echo "Reason : archive_command does not contain %f; archive destination cannot be safely transformed."
                        rm -f "$temp_output"
                        rm -f "$plan_rows"
                        return 1
                    fi

                    # Everything before %f.
                    archive_before_f="${old_archive_command%%%f*}"

                    # The final whitespace-delimited value before %f
                    # is treated as the archive destination.
                    archive_path="${archive_before_f##* }"

                    # Remove trailing slash if present.
                    archive_path="${archive_path%/}"

                    if [[ "$archive_path" != /* ]]; then
                        echo "Result : FAIL"
                        echo "Reason : Could not identify an absolute archive destination before %f."
                        rm -f "$temp_output"
                        rm -f "$plan_rows"
                        return 1
                    fi

                    archive_parent="${archive_path%/*}/"
                    archive_old_dir="${archive_path##*/}"

                    if [[ -z "$archive_old_dir" ]]; then
                        echo "Result : FAIL"
                        echo "Reason : Could not identify the final archive directory before %f."
                        rm -f "$temp_output"
                        rm -f "$plan_rows"
                        return 1
                    fi

                    archive_tmp_dir="${archive_old_dir}_tmp_pg${PG_NEW_VERSION}"
                    archive_tmp_path="${archive_parent}${archive_tmp_dir}"

                    # Replace only:
                    #
                    #     <old_last_directory>/%f
                    #
                    # Everything else in archive_command remains unchanged.
                    archive_command="${old_archive_command/$archive_old_dir\/%f/$archive_tmp_dir\/%f}"

                    transformed_archive_command="$archive_command"

                    if [[ ! -d "$archive_parent" ]]; then
                        echo "Result : FAIL"
                        echo "Reason : Existing archive parent directory does not exist: $archive_parent"
                        rm -f "$temp_output"
                        rm -f "$plan_rows"
                        return 1
                    fi

                    if [[ -e "$archive_tmp_path" ]]; then

                        if [[ ! -d "$archive_tmp_path" ]]; then
                            echo "Result : FAIL"
                            echo "Reason : Temporary archive destination exists but is not a directory: $archive_tmp_path"
                            rm -f "$temp_output"
                            rm -f "$plan_rows"
                            return 1
                        fi

                        echo "Temporary archive destination already exists:"
                        echo "  $archive_tmp_path"

                    else

                        mkdir "$archive_tmp_path"

                        if [[ $? -ne 0 ]]; then
                            echo "Result : FAIL"
                            echo "Reason : Failed to create temporary archive destination: $archive_tmp_path"
                            rm -f "$temp_output"
                            rm -f "$plan_rows"
                            return 1
                        fi

                        echo "Temporary archive destination created:"
                        echo "  $archive_tmp_path"

                    fi

                    chown "$PG_OS_USER:$PG_OS_USER" "$archive_tmp_path"

                    if [[ $? -ne 0 ]]; then
                        echo "Result : FAIL"
                        echo "Reason : Failed to set ownership on temporary archive destination: $archive_tmp_path"
                        rm -f "$temp_output"
                        rm -f "$plan_rows"
                        return 1
                    fi

                    {
                        echo "Archive command migration:"
                        echo "  Old : $old_archive_command"
                        echo "  New : $transformed_archive_command"
                        echo
                    } | tee /dev/tty

                    printf "archive_command = '%s'\n" \
                        "${transformed_archive_command//\'/\'\'}" \
                        >> "$temp_output"

                else

                    printf "%s = '%s'\n" \
                        "$name" \
                        "${old_setting//\'/\'\'}" \
                        >> "$temp_output"

                fi
                ;;

            SKIP)
                ;;

            LEAVE_DEFAULT)
                ;;

            MANUAL_REVIEW)
                echo "Result : FAIL"
                echo "Reason : Parameter '$name' requires manual review."
                rm -f "$temp_output"
                rm -f "$plan_rows"
                return 1
                ;;

            *)
                echo "Result : FAIL"
                echo "Reason : Unknown migration decision '$decision' for parameter '$name'."
                rm -f "$temp_output"
                rm -f "$plan_rows"
                return 1
                ;;

        esac

    done < "$plan_rows"

    rm -f "$plan_rows"

    if [[ ! -f "$temp_output" ]]; then
        echo "Result : FAIL"
        echo "Reason : No generated configuration file was produced."
        return 1
    fi

    {
        echo "Other MIGRATE parameters:"
        echo "  Migrated to generated postgresql.auto.conf."
        echo
    } | tee /dev/tty

    mv "$temp_output" "$output_file"

    if [[ $? -ne 0 ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to create final postgresql.auto.conf."
        rm -f "$temp_output"
        return 1
    fi

    echo "postgresql.auto.conf generated successfully."
    echo "File : $output_file"

    echo
    echo "Generated configuration:"
    cat "$output_file"

    echo
    echo "Result : PASS"
    echo "Reason : PostgreSQL $PG_NEW_VERSION postgresql.auto.conf generated successfully."

    return 0
}

initialize_final_new_cluster() {
    local profile_file
    local encoding
    local lc_collate
    local lc_ctype
    local locale_provider
    local data_checksums

    local locale_provider_option=()
    local initdb_checksum_option=()

    profile_file="$(run_dir)/backups/parms/old_initdb_profile.csv"

    echo "Final PostgreSQL cluster initialization"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New PostgreSQL binary  : $NEW_PG_BIN"
    echo "New data directory     : $NEW_DATA_DIR"
    echo

    if [[ ! -f "$profile_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Old initdb profile does not exist: $profile_file"
        return 1
    fi

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    if [[ -n "$(find "$NEW_DATA_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "Result : FAIL"
        echo "Reason : New data directory is not empty: $NEW_DATA_DIR"
        return 1
    fi

    if [[ "$(stat -c '%U' "$NEW_DATA_DIR")" != "$PG_OS_USER" ]]; then
        echo "Result : FAIL"
        echo "Reason : New data directory is not owned by $PG_OS_USER."
        return 1
    fi

    encoding="$(
        awk -F',' '$1 == "encoding" {print $2}' "$profile_file"
    )"

    lc_collate="$(
        awk -F',' '$1 == "lc_collate" {print $2}' "$profile_file"
    )"

    lc_ctype="$(
        awk -F',' '$1 == "lc_ctype" {print $2}' "$profile_file"
    )"

    locale_provider="$(
        awk -F',' '$1 == "locale_provider" {print $2}' "$profile_file"
    )"

    data_checksums="$(
        awk -F',' '$1 == "data_checksums" {print $2}' "$profile_file"
    )"

    if [[ -z "$encoding" ||
          -z "$lc_collate" ||
          -z "$lc_ctype" ||
          -z "$locale_provider" ||
          -z "$data_checksums" ]]; then

        echo "Result : FAIL"
        echo "Reason : Old initdb profile is incomplete."
        return 1
    fi

    echo "Initdb profile:"
    echo "  Encoding        : $encoding"
    echo "  LC_COLLATE      : $lc_collate"
    echo "  LC_CTYPE        : $lc_ctype"
    echo "  Locale provider : $locale_provider"
    echo "  Data checksums  : $data_checksums"

    if (( PG_NEW_VERSION >= 15 )); then
        locale_provider_option=(
            "--locale-provider=$locale_provider"
        )
    fi

    case "$data_checksums" in

        on)
            initdb_checksum_option=(
                "--data-checksums"
            )
            ;;

        off)
            if (( PG_NEW_VERSION >= 18 )); then
                initdb_checksum_option=(
                    "--no-data-checksums"
                )
            else
                initdb_checksum_option=()
            fi
            ;;

        *)
            echo "Result : FAIL"
            echo "Reason : Invalid data_checksums value in initdb profile: $data_checksums"
            return 1
            ;;

    esac

    echo
    echo "Running initdb..."

    "$NEW_PG_BIN/initdb" \
        "--pgdata=$NEW_DATA_DIR" \
        "--encoding=$encoding" \
        "--lc-collate=$lc_collate" \
        "--lc-ctype=$lc_ctype" \
        "${locale_provider_option[@]}" \
        "${initdb_checksum_option[@]}"

    if [[ $? -ne 0 ]]; then
        echo
        echo "Result : FAIL"
        echo "Reason : initdb failed for final PostgreSQL $PG_NEW_VERSION cluster."
        return 1
    fi

    echo
    echo "Verifying initialized cluster..."

    if [[ ! -f "$NEW_DATA_DIR/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION was not created."
        return 1
    fi

    if [[ "$(cat "$NEW_DATA_DIR/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not match expected PostgreSQL version $PG_NEW_VERSION."
        return 1
    fi

    if [[ "$(stat -c '%U' "$NEW_DATA_DIR")" != "$PG_OS_USER" ]]; then
        echo "Result : FAIL"
        echo "Reason : New data directory ownership changed unexpectedly."
        return 1
    fi

    echo "  PG_VERSION : $(cat "$NEW_DATA_DIR/PG_VERSION")"
    echo "  Owner      : $(stat -c '%U:%G' "$NEW_DATA_DIR")"

    echo
    echo "Result : PASS"
    echo "Reason : Final PostgreSQL $PG_NEW_VERSION cluster initialized successfully."

    return 0
}

install_prepared_new_cluster_configs() {
    local prepared_dir
    local prepared_hba
    local prepared_ident
    local prepared_auto_conf

    prepared_dir="$(run_dir)/backups/prepared_PG_${PG_NEW_VERSION}_datadir_confs"

    prepared_hba="$prepared_dir/pg_hba.conf"
    prepared_ident="$prepared_dir/pg_ident.conf"
    prepared_auto_conf="$prepared_dir/postgresql.auto.conf"

    echo "Installing prepared PostgreSQL configuration files"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Prepared config dir    : $prepared_dir"
    echo

    if [[ ! -d "$prepared_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Prepared configuration directory does not exist: $prepared_dir"
        return 1
    fi

    for file in \
        "$prepared_hba" \
        "$prepared_ident" \
        "$prepared_auto_conf"
    do
        if [[ ! -f "$file" ]]; then
            echo "Result : FAIL"
            echo "Reason : Required prepared configuration file does not exist: $file"
            return 1
        fi
    done

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New PostgreSQL data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    if [[ ! -f "$NEW_DATA_DIR/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Final new cluster is not initialized: PG_VERSION is missing."
        return 1
    fi

    if [[ "$(cat "$NEW_DATA_DIR/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not match expected PostgreSQL version $PG_NEW_VERSION."
        return 1
    fi

    if [[ "$(stat -c '%U' "$NEW_DATA_DIR")" != "$PG_OS_USER" ]]; then
        echo "Result : FAIL"
        echo "Reason : New data directory is not owned by $PG_OS_USER."
        return 1
    fi

    echo "Prepared files:"
    echo "  pg_hba.conf"
    echo "  pg_ident.conf"
    echo "  postgresql.auto.conf"

    echo
    echo "Installing prepared configuration files..."

    cp "$prepared_hba" "$NEW_DATA_DIR/pg_hba.conf" || {
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to install pg_hba.conf."
        return 1
    }

    cp "$prepared_ident" "$NEW_DATA_DIR/pg_ident.conf" || {
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to install pg_ident.conf."
        return 1
    }

    cp "$prepared_auto_conf" "$NEW_DATA_DIR/postgresql.auto.conf" || {
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to install postgresql.auto.conf."
        return 1
    }

    chown "$PG_OS_USER:$PG_OS_USER" \
        "$NEW_DATA_DIR/pg_hba.conf" \
        "$NEW_DATA_DIR/pg_ident.conf" \
        "$NEW_DATA_DIR/postgresql.auto.conf" || {
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to set ownership on installed configuration files."
        return 1
    }

    echo
    echo "Verifying installed files..."

    if ! cmp -s "$prepared_hba" "$NEW_DATA_DIR/pg_hba.conf"; then
        echo "Result : FAIL"
        echo "Reason : Installed pg_hba.conf does not match prepared file."
        return 1
    fi

    if ! cmp -s "$prepared_ident" "$NEW_DATA_DIR/pg_ident.conf"; then
        echo "Result : FAIL"
        echo "Reason : Installed pg_ident.conf does not match prepared file."
        return 1
    fi

    if ! cmp -s "$prepared_auto_conf" "$NEW_DATA_DIR/postgresql.auto.conf"; then
        echo "Result : FAIL"
        echo "Reason : Installed postgresql.auto.conf does not match prepared file."
        return 1
    fi

    echo
    echo "Installed configuration:"
    echo "  $NEW_DATA_DIR/pg_hba.conf"
    echo "  $NEW_DATA_DIR/pg_ident.conf"
    echo "  $NEW_DATA_DIR/postgresql.auto.conf"

    echo
    echo "postgresql.conf:"
    echo "  Preserved from final initdb."
    echo "  No modification performed."

    echo
    echo "Result : PASS"
    echo "Reason : Prepared PostgreSQL configuration files installed successfully."

    return 0
}

add_validation_port_to_postgresql_auto_conf() {
    local auto_conf

    auto_conf="$NEW_DATA_DIR/postgresql.auto.conf"

    echo "Adding temporary validation port"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Configuration file    : $auto_conf"
    echo "Validation port       : 7433"
    echo

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New PostgreSQL data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    if [[ ! -f "$NEW_DATA_DIR/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not exist in new data directory."
        return 1
    fi

    if [[ "$(cat "$NEW_DATA_DIR/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not match expected PostgreSQL version $PG_NEW_VERSION."
        return 1
    fi

    if [[ ! -f "$auto_conf" ]]; then
        echo "Result : FAIL"
        echo "Reason : postgresql.auto.conf does not exist: $auto_conf"
        return 1
    fi

    if grep -Eq '^[[:space:]]*port[[:space:]]*=' "$auto_conf"; then
        echo "Result : FAIL"
        echo "Reason : A port parameter already exists in postgresql.auto.conf."
        return 1
    fi

    echo "Adding:"
    echo "  port = 7433"

if [[ -s "$auto_conf" ]]; then
    perl -0777 -i -pe 's/\n+\z//' "$auto_conf"
    printf '\n' >> "$auto_conf"
fi

    printf 'port = 7433\n' >> "$auto_conf" || {
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to add validation port to postgresql.auto.conf."
        return 1
    }

    if ! grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*7433[[:space:]]*$' \
        "$auto_conf"
    then
        echo
        echo "Result : FAIL"
        echo "Reason : Validation port was not written correctly."
        return 1
    fi

    if [[ "$(stat -c '%U' "$auto_conf")" != "$PG_OS_USER" ]]; then
        echo
        echo "Result : FAIL"
        echo "Reason : postgresql.auto.conf ownership is not $PG_OS_USER."
        return 1
    fi

    echo
    echo "Updated configuration:"
    echo "  port = 7433"

    echo
    echo "Result : PASS"
    echo "Reason : Temporary validation port 7433 added successfully."

    return 0
}

stop_temp_new_cluster() {
    local temp_holder
    local temp_data_dir

    temp_holder="$(run_dir)/temp/PG_${PG_NEW_VERSION}"
    temp_data_dir="$temp_holder/data"

    echo "Stopping temporary PostgreSQL cluster"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Temporary data dir     : $temp_data_dir"
    echo "Port                   : 7433"
    echo

    if [[ ! -d "$temp_data_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary PostgreSQL data directory does not exist: $temp_data_dir"
        return 1
    fi

    if [[ ! -f "$temp_data_dir/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary PostgreSQL cluster is not initialized: PG_VERSION is missing."
        return 1
    fi

    if [[ "$(cat "$temp_data_dir/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : Temporary cluster PG_VERSION does not match PostgreSQL $PG_NEW_VERSION."
        return 1
    fi

    echo "Checking current cluster status..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        status >/dev/null 2>&1
    then
        echo "  Cluster status : stopped"
        echo
        echo "Result : PASS"
        echo "Reason : Temporary PostgreSQL $PG_NEW_VERSION cluster is already stopped."

        return 0
    fi

    echo "  Cluster status : running"

    echo
    echo "Stopping temporary PostgreSQL cluster..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        stop
    then
        echo
        echo "Result : FAIL"
        echo "Reason : pg_ctl failed to stop the temporary PostgreSQL cluster."
        return 1
    fi

    echo
    echo "Verifying cluster status..."

    if "$NEW_PG_BIN/pg_ctl" \
        -D "$temp_data_dir" \
        status >/dev/null 2>&1
    then
        echo "Result : FAIL"
        echo "Reason : Temporary PostgreSQL cluster is still running after pg_ctl stop."
        return 1
    fi

    echo "  Cluster status : stopped"

    echo
    echo "Result : PASS"
    echo "Reason : Temporary PostgreSQL $PG_NEW_VERSION cluster stopped successfully."

    return 0
}

prepare_final_new_cluster_log() {
    local log_dir
    local latest_log
    local archived_log

    log_dir="$NEW_DATA_DIR/log"

    echo "Preparing PostgreSQL startup log"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Log directory          : $log_dir"
    echo

if [[ ! -d "$log_dir" ]]; then
    echo "No existing PostgreSQL log directory found."
    echo "  PostgreSQL will create the log directory during startup."

    echo
    echo "Result : PASS"
    echo "Reason : No existing PostgreSQL log required preparation."

    return 0
fi
    latest_log="$(
        find "$log_dir" \
            -maxdepth 1 \
            -type f \
            -name '*.log' \
            -printf '%T@ %p\n' |
        sort -n |
        tail -1 |
        cut -d' ' -f2-
    )"

    if [[ -z "$latest_log" ]]; then
        echo "No existing PostgreSQL log file found."
        echo "  PostgreSQL will create the startup log."

        echo
        echo "Result : PASS"
        echo "Reason : No existing PostgreSQL log required renaming."

        return 0
    fi

    archived_log="${latest_log}.pre_startup"

    echo "Latest PostgreSQL log:"
    echo "  $latest_log"

    echo
    echo "Renaming existing log:"
    echo "  $latest_log"
    echo "      ->"
    echo "  $archived_log"

    if ! mv -f "$latest_log" "$archived_log"; then
        echo
        echo "Result : FAIL"
        echo "Reason : Failed to rename existing PostgreSQL log."
        return 1
    fi

    echo
    echo "Verifying renamed log..."

    if [[ -f "$latest_log" ]]; then
        echo "Result : FAIL"
        echo "Reason : Original PostgreSQL log still exists after rename."
        return 1
    fi

    if [[ ! -f "$archived_log" ]]; then
        echo "Result : FAIL"
        echo "Reason : Renamed PostgreSQL log was not found."
        return 1
    fi

    echo "  Preserved log : $archived_log"

    echo
    echo "Result : PASS"
    echo "Reason : Existing PostgreSQL log renamed successfully before final startup."

    return 0
}

start_final_new_cluster() {
    echo "Starting final PostgreSQL cluster"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New PostgreSQL binary  : $NEW_PG_BIN"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Port                   : 7433"
    echo

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New PostgreSQL data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    if [[ ! -f "$NEW_DATA_DIR/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not exist in new data directory."
        return 1
    fi

    if [[ "$(cat "$NEW_DATA_DIR/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not match expected PostgreSQL version $PG_NEW_VERSION."
        return 1
    fi

    if [[ ! -f "$NEW_DATA_DIR/postgresql.auto.conf" ]]; then
        echo "Result : FAIL"
        echo "Reason : postgresql.auto.conf does not exist."
        return 1
    fi

    if ! grep -Eq '^[[:space:]]*port[[:space:]]*=[[:space:]]*7433[[:space:]]*$' \
        "$NEW_DATA_DIR/postgresql.auto.conf"
    then
        echo "Result : FAIL"
        echo "Reason : Validation port 7433 is not configured in postgresql.auto.conf."
        return 1
    fi

    echo "Checking current cluster status..."

    if "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        status >/dev/null 2>&1
    then
        echo
        echo "Result : FAIL"
        echo "Reason : Final PostgreSQL cluster is already running."
        return 1
    fi

    echo "  Cluster status : stopped"

    echo
    echo "Starting PostgreSQL with pg_ctl..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        start
    then
        echo
        echo "Result : FAIL"
        echo "Reason : pg_ctl failed to start the final PostgreSQL cluster."
        return 1
    fi

    echo
    echo "Verifying cluster status..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        status >/dev/null 2>&1
    then
        echo "Result : FAIL"
        echo "Reason : PostgreSQL cluster is not running after pg_ctl start."
        return 1
    fi

    echo "  Cluster status : running"

    echo
    echo "Result : PASS"
    echo "Reason : Final PostgreSQL $PG_NEW_VERSION cluster started successfully with pg_ctl."

    return 0
}

validate_final_new_cluster_startup() {
    local startup_validation_dir
    local ignore_file
    local snapshot_file
    local error_lines_file
    local log_dir
    local latest_log
    local unexpected_count
    local connection_result
    local ignored
    local pattern

    startup_validation_dir="$(run_dir)/backups/startup_validations"

    ignore_file="$startup_validation_dir/ignored_startup_log_patterns.conf"
    snapshot_file="$startup_validation_dir/final_pg_${PG_NEW_VERSION}_startup_log_snapshot.log"
    error_lines_file="$startup_validation_dir/startup_error_lines.log"

    log_dir="$NEW_DATA_DIR/log"

    echo "Validating final PostgreSQL cluster startup"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "PostgreSQL log dir     : $log_dir"
    echo "Startup snapshot       : $snapshot_file"
    echo

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New PostgreSQL data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    if [[ ! -f "$NEW_DATA_DIR/PG_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not exist in final PostgreSQL data directory."
        return 1
    fi

    if [[ "$(cat "$NEW_DATA_DIR/PG_VERSION")" != "$PG_NEW_VERSION" ]]; then
        echo "Result : FAIL"
        echo "Reason : PG_VERSION does not match expected PostgreSQL version $PG_NEW_VERSION."
        return 1
    fi

    if [[ ! -d "$startup_validation_dir" ]]; then
        if ! mkdir -p "$startup_validation_dir"; then
            echo "Result : FAIL"
            echo "Reason : Failed to create startup validation directory."
            return 1
        fi
    fi

    if [[ ! -f "$ignore_file" ]]; then
        if ! touch "$ignore_file"; then
            echo "Result : FAIL"
            echo "Reason : Failed to create startup log ignore file."
            return 1
        fi
    fi

    if [[ ! -d "$log_dir" ]]; then
        echo "Result : FAIL"
        echo "Reason : PostgreSQL log directory does not exist: $log_dir"
        return 1
    fi

    echo "Finding latest PostgreSQL startup log..."

    latest_log="$(
        find "$log_dir" \
            -maxdepth 1 \
            -type f \
            -name '*.log' \
            -printf '%T@ %p\n' |
        sort -n |
        tail -1 |
        cut -d' ' -f2-
    )"

    if [[ -z "$latest_log" ]]; then
        echo "Result : FAIL"
        echo "Reason : No PostgreSQL log file was found in: $log_dir"
        return 1
    fi

    echo "  Latest log : $latest_log"

    echo
    echo "Creating startup log snapshot..."

    if ! cp "$latest_log" "$snapshot_file"; then
        echo "Result : FAIL"
        echo "Reason : Failed to create startup log snapshot."
        return 1
    fi

    if [[ ! -s "$snapshot_file" ]]; then
        echo "Result : FAIL"
        echo "Reason : Startup log snapshot is empty."
        return 1
    fi

    echo "  Snapshot created : $snapshot_file"

    echo
    echo "Checking startup log for WARNING/ERROR/FATAL/PANIC messages..."

    : > "$error_lines_file"

    while IFS= read -r line
    do
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ (WARNING|ERROR|FATAL|PANIC): ]]; then

            ignored=false

            while IFS= read -r pattern
            do
                [[ -z "$pattern" ]] && continue
                [[ "$pattern" =~ ^[[:space:]]*# ]] && continue

                if printf '%s\n' "$line" | grep -Eq "$pattern"; then
                    ignored=true
                    break
                fi

            done < "$ignore_file"

            if [[ "$ignored" == true ]]; then
                printf '[IGNORED] %s\n' "$line" >> "$error_lines_file"
            else
                printf '[UNEXPECTED] %s\n' "$line" >> "$error_lines_file"
            fi
        fi

    done < "$snapshot_file"

    unexpected_count="$(
        grep -c '^\[UNEXPECTED\]' "$error_lines_file" 2>/dev/null || true
    )"

    if [[ "$unexpected_count" -gt 0 ]]; then
        echo
        echo "Unexpected startup messages detected:"
        cat "$error_lines_file"

        echo
        echo "Result : FAIL"
        echo "Reason : $unexpected_count unexpected WARNING/ERROR/FATAL/PANIC message(s) found in startup log."
        return 1
    fi

    echo "  Unexpected WARNING/ERROR/FATAL/PANIC messages : 0"

    if grep -q '^\[IGNORED\]' "$error_lines_file"; then
        echo
        echo "Ignored startup messages:"
        grep '^\[IGNORED\]' "$error_lines_file"
    fi

    echo
    echo "Checking final PostgreSQL cluster status..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        status >/dev/null 2>&1
    then
        echo "Result : FAIL"
        echo "Reason : Final PostgreSQL cluster is not running."
        return 1
    fi

    echo "  Cluster status : running"

    echo
    echo "Checking PostgreSQL connection..."

    connection_result="$(
        "$NEW_PG_BIN/psql" \
            -p 7433 \
            -d postgres \
            -Atqc "SELECT 1;" \
            2>&1
    )"

    if [[ "$connection_result" != "1" ]]; then
        echo "Result : FAIL"
        echo "Reason : Failed to connect to final PostgreSQL cluster or SELECT 1 did not return 1."
        echo "psql output:"
        echo "$connection_result"
        return 1
    fi

    echo "  Connection : successful"
    echo "  SELECT 1   : 1"

    echo
    echo "Startup validation artifacts:"
    echo "  PostgreSQL log       : $latest_log"
    echo "  Startup snapshot     : $snapshot_file"
    echo "  Error classification : $error_lines_file"

    echo
    echo "Result : PASS"
    echo "Reason : Final PostgreSQL $PG_NEW_VERSION cluster startup validated successfully."

    return 0
}

stop_final_new_cluster() {
    echo "Stopping final PostgreSQL cluster"
    echo
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "New PostgreSQL binary  : $NEW_PG_BIN"
    echo "New data directory     : $NEW_DATA_DIR"
    echo

    if [[ ! -d "$NEW_DATA_DIR" ]]; then
        echo "Result : FAIL"
        echo "Reason : New PostgreSQL data directory does not exist: $NEW_DATA_DIR"
        return 1
    fi

    echo "Checking current cluster status..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        status >/dev/null 2>&1
    then
        echo "Result : FAIL"
        echo "Reason : Final PostgreSQL cluster is not running."
        return 1
    fi

    echo "  Cluster status : running"

    echo
    echo "Stopping PostgreSQL with pg_ctl..."

    if ! "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        stop \
	-m fast
    then
        echo
        echo "Result : FAIL"
        echo "Reason : pg_ctl failed to stop the final PostgreSQL cluster."
        return 1
    fi

    echo
    echo "Verifying cluster status..."

    if "$NEW_PG_BIN/pg_ctl" \
        -D "$NEW_DATA_DIR" \
        status >/dev/null 2>&1
    then
        echo "Result : FAIL"
        echo "Reason : Final PostgreSQL cluster is still running after pg_ctl stop."
        return 1
    fi

    echo "  Cluster status : stopped"

    echo
    echo "Result : PASS"
    echo "Reason : Final PostgreSQL $PG_NEW_VERSION cluster stopped successfully."

    return 0
}

pg_upgrade_check_copy() {
    echo "Running pg_upgrade --check"
    echo
    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Old PostgreSQL binary  : $OLD_PG_BIN"
    echo "New PostgreSQL binary  : $NEW_PG_BIN"
    echo "Old data directory     : $OLD_DATA_DIR"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Upgrade mode           : copy"
    echo

    echo "Executing pg_upgrade --check..."

    if ! "$NEW_PG_BIN/pg_upgrade" \
        --check \
        --old-bindir="$OLD_PG_BIN" \
        --new-bindir="$NEW_PG_BIN" \
        --old-datadir="$OLD_DATA_DIR" \
        --new-datadir="$NEW_DATA_DIR"
    then
        echo
        echo "Result : FAIL"
        echo "Reason : pg_upgrade --check failed for copy mode."
        return 1
    fi

    echo
    echo "Result : PASS"
    echo "Reason : pg_upgrade --check completed successfully for copy mode."

    return 0
}

pg_upgrade_check_link() {
    echo "Running pg_upgrade --check --link"
    echo
    echo "Old PostgreSQL version : $PG_OLD_VERSION"
    echo "New PostgreSQL version : $PG_NEW_VERSION"
    echo "Old PostgreSQL binary  : $OLD_PG_BIN"
    echo "New PostgreSQL binary  : $NEW_PG_BIN"
    echo "Old data directory     : $OLD_DATA_DIR"
    echo "New data directory     : $NEW_DATA_DIR"
    echo "Upgrade mode           : link"
    echo

    echo "Executing pg_upgrade --check --link..."

    if ! "$NEW_PG_BIN/pg_upgrade" \
        --check \
        --link \
        --old-bindir="$OLD_PG_BIN" \
        --new-bindir="$NEW_PG_BIN" \
        --old-datadir="$OLD_DATA_DIR" \
        --new-datadir="$NEW_DATA_DIR"
    then
        echo
        echo "Result : FAIL"
        echo "Reason : pg_upgrade --check --link failed."
        return 1
    fi

    echo
    echo "Result : PASS"
    echo "Reason : pg_upgrade --check --link completed successfully."

    return 0
}

final_prechecks_message() {
    local bold
    local green
    local yellow
    local cyan
    local reset

    bold=$'\033[1m'
    green=$'\033[32m'
    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'

    {
        echo
        echo "${bold}${green}============================================================${reset}"
        echo "${bold}${green}     PostgreSQL Prechecks Completed Successfully${reset}"
        echo "${bold}${green}============================================================${reset}"
        echo
        echo "Old PostgreSQL version : ${PG_OLD_VERSION}"
        echo "New PostgreSQL version : ${PG_NEW_VERSION}"
        echo
        echo "${green}All prechecks and pg_upgrade compatibility checks have${reset}"
        echo "${green}completed successfully.${reset}"
        echo
        echo "${bold}${cyan}========================= NEXT =============================${reset}"
        echo
        echo "${yellow}On the day of the upgrade, ask the Linux team to run:${reset}"
        echo
        echo "${bold}sudo systemctl disable --now postgresql-${PG_OLD_VERSION}${reset}"
        echo
        echo "${yellow}When your turn comes to perform the upgrade, run:${reset}"
        echo
        echo "${bold}${cyan}Copy mode:${reset}"
        echo "./postgres_pg_major_upgrade_inplace.sh upgrade --runid=${RUN_ID} --mode=copy"
        echo
        echo "${bold}${cyan}or Link mode:${reset}"
        echo "./postgres_pg_major_upgrade_inplace.sh upgrade --runid=${RUN_ID} --mode=link"
        echo
        echo "${bold}${green}============================================================${reset}"
        echo
    } | tee /dev/tty

    return 0
}

###############################################################################
# PRECHECK workflow
###############################################################################

run_prechecks() {

    local dir
    local prechecks_dir

    dir="$(run_dir)"
    prechecks_dir="$dir/prechecks"

    ###########################################################################
    # If PRECHECKS_OK already exists, there is nothing to do.
    ###########################################################################

    if [[ -f "$prechecks_dir/PRECHECKS_OK" ]]; then

        log "PRECHECKS already completed successfully."

        return 0
    fi

    ###########################################################################
    # Individual precheck steps
    #
    # A failed step stops the workflow.
    # On the next execution, SUCCESS steps are skipped.
    ###########################################################################

run_step \
    "001_check_pg_os_user" \
    "$prechecks_dir" \
    check_pg_os_user ||
    return 1

run_step \
    "002_check_running_user" \
    "$prechecks_dir" \
    check_running_user ||
    return 1

run_step \
    "003_check_old_pg_bin" \
    "$prechecks_dir" \
    check_old_pg_bin ||
    return 1

run_step \
    "004_check_new_pg_bin" \
    "$prechecks_dir" \
    check_new_pg_bin ||
    return 1

run_step \
    "005_check_old_pg_binary_version" \
    "$prechecks_dir" \
    check_old_pg_binary_version ||
    return 1

run_step \
    "006_check_new_pg_binary_version" \
    "$prechecks_dir" \
    check_new_pg_binary_version ||
    return 1

run_step \
    "007_check_old_data_dir" \
    "$prechecks_dir" \
    check_old_data_dir ||
    return 1

run_step \
    "008_check_old_pg_cluster" \
    "$prechecks_dir" \
    check_old_pg_cluster ||
    return 1

run_step \
    "009_check_new_data_dir" \
    "$prechecks_dir" \
    check_new_data_dir ||
    return 1

run_step \
    "010_check_data_dir_owner" \
    "$prechecks_dir" \
    check_data_dir_owner ||
    return 1

run_step \
    "011_check_pg_systemctl_services" \
    "$prechecks_dir" \
    check_pg_systemctl_services ||
    return 1

run_step \
    "012_check_old_pg_service_datadir" \
    "$prechecks_dir" \
    check_old_pg_service_datadir ||
    return 1

run_step \
    "013_check_old_pg_service_status" \
    "$prechecks_dir" \
    check_old_pg_service_status ||
    return 1

run_step \
    "014_check_new_pg_service_datadir" \
    "$prechecks_dir" \
    check_new_pg_service_datadir ||
    return 1

run_step \
    "015_check_new_pg_service_status" \
    "$prechecks_dir" \
    check_new_pg_service_status ||
    return 1

run_step \
    "016_check_pg_packages" \
    "$prechecks_dir" \
    check_pg_packages ||
    return 1

run_step \
    "017_check_pg_cron" \
    "$prechecks_dir" \
    check_pg_cron ||
    return 1

run_step \
    "018_check_extensions" \
    "$prechecks_dir" \
    check_extensions ||
    return 1

run_step \
    "019_backup_old_pg_configs" \
    "$prechecks_dir" \
    check_backup_old_pg_configs ||
    return 1

run_step \
    "020_prepare_new_pg_configs_hba_ident" \
    "$prechecks_dir" \
    prepare_new_pg_configs_hba_ident ||
    return 1

run_step \
    "021_check_old_pg_pending_restart" \
    "$prechecks_dir" \
    check_old_pg_pending_restart ||
    return 1

run_step \
    "022_collect_old_config_inventory" \
    "$prechecks_dir" \
    collect_old_config_inventory ||
    return 1

run_step \
    "023_collect_old_initdb_profile" \
    "$prechecks_dir" \
    collect_old_initdb_profile ||
    return 1

run_step \
    "024_initialize_temp_new_cluster" \
    "$prechecks_dir" \
    initialize_temp_new_cluster ||
    return 1

run_step \
    "025_start_temp_new_cluster" \
    "$prechecks_dir" \
    start_temp_new_cluster ||
    return 1

run_step \
    "026_compare_old_config_with_temp_new" \
    "$prechecks_dir" \
    compare_old_config_with_temp_new ||
    return 1

run_step \
    "027_initialize_temp_old_cluster" \
    "$prechecks_dir" \
    initialize_temp_old_cluster ||
    return 1

run_step \
    "028_start_temp_old_cluster" \
    "$prechecks_dir" \
    start_temp_old_cluster ||
    return 1

run_step \
    "029_collect_temp_old_config_baseline" \
    "$prechecks_dir" \
    collect_temp_old_config_baseline ||
    return 1

run_step \
    "030_stop_temp_old_cluster" \
    "$prechecks_dir" \
    stop_temp_old_cluster ||
    return 1

run_step \
    "031_generate_config_migration_plan" \
    "$prechecks_dir" \
    generate_config_migration_plan ||
    return 1

run_step \
    "032_display_config_migration_plan" \
    "$prechecks_dir" \
    display_config_migration_plan ||
    return 1

run_step \
    "033_generate_postgresql_auto_conf" \
    "$prechecks_dir" \
    generate_postgresql_auto_conf ||
    return 1

run_step \
    "034_initialize_final_new_cluster" \
    "$prechecks_dir" \
    initialize_final_new_cluster ||
    return 1

run_step \
    "035_install_prepared_new_cluster_configs" \
    "$prechecks_dir" \
    install_prepared_new_cluster_configs ||
    return 1

run_step \
    "036_add_validation_port_to_postgresql_auto_conf" \
    "$prechecks_dir" \
    add_validation_port_to_postgresql_auto_conf ||
    return 1

run_step \
    "037_stop_temp_new_cluster" \
    "$prechecks_dir" \
    stop_temp_new_cluster ||
    return 1

run_step \
    "038_prepare_final_new_cluster_log" \
    "$prechecks_dir" \
    prepare_final_new_cluster_log ||
    return 1

run_step \
    "039_start_final_new_cluster" \
    "$prechecks_dir" \
    start_final_new_cluster ||
    return 1

run_step \
    "040_validate_final_new_cluster_startup" \
    "$prechecks_dir" \
    validate_final_new_cluster_startup ||
    return 1

run_step \
    "041_stop_final_new_cluster" \
    "$prechecks_dir" \
    stop_final_new_cluster ||
    return 1

run_step \
    "042_pg_upgrade_check_copy" \
    "$prechecks_dir" \
    pg_upgrade_check_copy ||
    return 1

run_step \
    "043_pg_upgrade_check_link" \
    "$prechecks_dir" \
    pg_upgrade_check_link ||
    return 1

run_step \
    "044_final_prechecks_message" \
    "$prechecks_dir" \
    final_prechecks_message ||
    return 1

    ###########################################################################
    # Reaching this point means every precheck succeeded.
    ###########################################################################

    touch "$prechecks_dir/PRECHECKS_OK" ||
        die "Cannot create PRECHECKS_OK"

    log "PRECHECKS_OK created."

    return 0
}

###############################################################################
# Dummy UPGRADE steps
#
# These functions will later contain the real upgrade operations.
###############################################################################

stop_postgres() {

    echo "Dummy action: stop PostgreSQL"
    echo "Result: PASS"

    return 0
}

backup_configuration() {

    echo "Dummy action: backup PostgreSQL configuration"
    echo "Result: PASS"

    return 0
}

copy_or_link_binaries() {

    echo "Dummy action: copy/link PostgreSQL binaries"
    echo "Upgrade mode: $UPGRADE_MODE"
    echo "Result: PASS"

    return 0
}

run_pg_upgrade() {

    echo "Dummy action: pg_upgrade"
    echo "Result: PASS"

    return 0
}

start_new_postgres() {

    echo "Dummy action: start new PostgreSQL"
    echo "Result: PASS"

    return 0
}

post_upgrade_checks() {

    echo "Dummy action: post-upgrade checks"
    echo "Result: PASS"

    return 0
}

###############################################################################
# UPGRADE workflow
###############################################################################

run_upgrade() {

    local dir
    local prechecks_dir
    local upgrade_dir

    dir="$(run_dir)"

    prechecks_dir="$dir/prechecks"
    upgrade_dir="$dir/upgrade"

    ###########################################################################
    # Upgrade is allowed only after complete successful prechecks.
    ###########################################################################

    if [[ ! -f "$prechecks_dir/PRECHECKS_OK" ]]; then

        die "PRECHECKS_OK not found. Run successful prechecks before upgrade."

    fi

    ###########################################################################
    # Upgrade steps
    ###########################################################################

    run_step \
        "001_stop_postgres" \
        "$upgrade_dir" \
        stop_postgres ||
        return 1

    run_step \
        "002_backup_configuration" \
        "$upgrade_dir" \
        backup_configuration ||
        return 1

    run_step \
        "003_copy_or_link_binaries" \
        "$upgrade_dir" \
        copy_or_link_binaries ||
        return 1

    run_step \
        "004_run_pg_upgrade" \
        "$upgrade_dir" \
        run_pg_upgrade ||
        return 1

    run_step \
        "005_start_new_postgres" \
        "$upgrade_dir" \
        start_new_postgres ||
        return 1

    run_step \
        "006_post_upgrade_checks" \
        "$upgrade_dir" \
        post_upgrade_checks ||
        return 1

    log "UPGRADE COMPLETED SUCCESSFULLY."

    return 0
}

###############################################################################
# Argument parsing
###############################################################################

COMMAND=""
RUN_ID=""
RUN_ID_VALUE=""
UPGRADE_MODE=""

for arg in "$@"; do

    case "$arg" in

        prechecks)
            COMMAND="prechecks"
            ;;

        upgrade)
            COMMAND="upgrade"
            ;;

        --runid=*)
            RUN_ID_VALUE="${arg#*=}"
            ;;

        --mode=*)
            UPGRADE_MODE="${arg#*=}"
            ;;

        --help|-h)
            usage
            exit 0
            ;;

        *)
            die "Unknown argument: $arg"
            ;;

    esac

done

###############################################################################
# Validate command
###############################################################################

[[ -n "$COMMAND" ]] ||
    die "Command is required."

[[ -n "$RUN_ID_VALUE" ]] ||
    die "--runid is required."

###############################################################################
# Handle RUN ID
###############################################################################

if [[ "$RUN_ID_VALUE" == "new" ]]; then

    [[ "$COMMAND" == "prechecks" ]] ||
        die "--runid=new is allowed only for prechecks."

    create_new_run

else

    RUN_ID="$RUN_ID_VALUE"

    validate_existing_run

fi

###############################################################################
# Validate upgrade mode
###############################################################################

if [[ "$COMMAND" == "upgrade" ]]; then

    [[ -n "$UPGRADE_MODE" ]] ||
        die "--mode=copy or --mode=link is required."

    case "$UPGRADE_MODE" in

        copy|link)
            ;;

        *)
            die "Invalid upgrade mode: $UPGRADE_MODE. Use copy or link."

    esac

fi

###############################################################################
# Load configuration
###############################################################################

if [[ ! -f "$CONFIG" ]]; then
    die "Configuration file not found: $CONFIG"
fi

# shellcheck source=/dev/null
source "$CONFIG"

###############################################################################
# Execute requested command
###############################################################################

case "$COMMAND" in

    prechecks)

        progress "Running PostgreSQL prechecks"

        if run_prechecks; then
            echo
            log "PRECHECKS PASS"
        else
            echo
            log "PRECHECKS FAILED"
            exit 1
        fi

        ;;

    upgrade)

        progress "Running PostgreSQL upgrade"

        if run_upgrade; then
            echo
            log "UPGRADE PASS"
        else
            echo
            log "UPGRADE FAILED"
            exit 1
        fi

        ;;

    *)

        die "Unsupported command: $COMMAND"

        ;;

esac

exit 0
