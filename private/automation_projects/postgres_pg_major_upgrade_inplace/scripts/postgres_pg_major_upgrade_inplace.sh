#!/usr/bin/env bash

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

    log "RUN $step_name"

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

check_old_bin_installed() {

    echo "Dummy check: old PostgreSQL binaries"
    echo "Result: PASS"

    return 0
}

check_new_bin_installed() {

    echo "Dummy check: new PostgreSQL binaries"
    echo "Result: PASS"

    return 0
}

check_old_pg_config() {

    echo "Dummy check: old PostgreSQL configuration"
    echo "Result: PASS"

    return 0
}

check_new_pg_config() {

    echo "Dummy check: new PostgreSQL configuration"
    echo "Result: PASS"

    return 0
}

check_old_version() {

    echo "Dummy check: old PostgreSQL version"
    echo "Result: PASS"

    return 0
}

check_new_version() {

    echo "Dummy check: new PostgreSQL version"
    echo "Result: PASS"

    return 0
}

check_cluster_status() {

    echo "Dummy check: PostgreSQL cluster status"
    echo "Result: PASS"

    return 0
}

check_extensions() {

    echo "Dummy check: PostgreSQL extensions"
    echo "Result: PASS"

    return 0
}

check_disk_space() {

    echo "Dummy check: disk space"
    echo "Result: PASS"

    return 0
}

check_pg_upgrade_compatibility() {

    echo "Dummy check: pg_upgrade compatibility"
    echo "Result: PASS"

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
        "001_check_old_bin_installed" \
        "$prechecks_dir" \
        check_old_bin_installed ||
        return 1

    run_step \
        "002_check_new_bin_installed" \
        "$prechecks_dir" \
        check_new_bin_installed ||
        return 1

    run_step \
        "003_check_old_pg_config" \
        "$prechecks_dir" \
        check_old_pg_config ||
        return 1

    run_step \
        "004_check_new_pg_config" \
        "$prechecks_dir" \
        check_new_pg_config ||
        return 1

    run_step \
        "005_check_old_version" \
        "$prechecks_dir" \
        check_old_version ||
        return 1

    run_step \
        "006_check_new_version" \
        "$prechecks_dir" \
        check_new_version ||
        return 1

    run_step \
        "007_check_cluster_status" \
        "$prechecks_dir" \
        check_cluster_status ||
        return 1

    run_step \
        "008_check_extensions" \
        "$prechecks_dir" \
        check_extensions ||
        return 1

    run_step \
        "009_check_disk_space" \
        "$prechecks_dir" \
        check_disk_space ||
        return 1

    run_step \
        "010_check_pg_upgrade_compatibility" \
        "$prechecks_dir" \
        check_pg_upgrade_compatibility ||
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
