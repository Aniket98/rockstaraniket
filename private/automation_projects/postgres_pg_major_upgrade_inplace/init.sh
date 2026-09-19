#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DELAY="${DELAY:-0.25}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[FAIL]${NC} $*"; }

progress() {
    local message="$1"
    local dots
    for dots in "." ".." "..." "...."; do
        printf "\r[%-4s] %s" "$dots" "$message"
        sleep "$DELAY"
    done
    printf "\r\033[K"
}

print_status() {
    local name="$1"
    local status="$2"
    case "$status" in
        PASS)    printf "%-18s : ${GREEN}PASS${NC}\n" "$name" ;;
        FAIL)    printf "%-18s : ${RED}FAIL${NC}\n" "$name" ;;
        SKIPPED) printf "%-18s : ${YELLOW}SKIPPED${NC}\n" "$name" ;;
        *)       printf "%-18s : %s\n" "$name" "$status" ;;
    esac
}

create_directory() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        success "Directory exists: $dir"
    else
        mkdir -p "$dir"
        success "Directory created: $dir"
    fi
}

create_config() {
    local config="$ROOT/config/pgupgrade.conf"
    if [[ -f "$config" ]]; then
        success "Configuration exists: $config"
        return
    fi

    cat > "$config" <<'CFG'
# PostgreSQL major upgrade configuration

OLD_PG_CONFIG=""
NEW_PG_CONFIG=""

OLD_DATA_DIR=""
NEW_DATA_DIR=""

PG_SERVICE_NAME="postgresql"
PG_OS_USER="postgres"
CFG

    success "Configuration created: $config"
}

bootstrap() {
    echo
    echo "============================================================"
    echo " PostgreSQL In-Place Major Upgrade Framework"
    echo " Bootstrap / Initialization"
    echo "============================================================"
    echo

    info "Project root: $ROOT"
    echo

    progress "Creating required directories"
    create_directory "$ROOT/scripts"
    create_directory "$ROOT/config"
    create_directory "$ROOT/runs"

    echo
    progress "Creating configuration"
    create_config

    echo
    echo "============================================================"
    echo " Bootstrap completed"
    echo "============================================================"
    echo

    warning "The following scripts must be copied manually:"
    echo
    echo "  1. Main workflow script:"
    echo "     scripts/postgres_pg_major_upgrade_inplace.sh"
    echo
    echo "  2. Destroy utility:"
    echo "     scripts/destroy.sh"
    echo
    warning "Copy these scripts into the paths shown above."
    echo
    echo "Once the scripts have been copied, run:"
    echo
    echo "    ./init.sh validate"
    echo
    echo "The validate command will perform all initialization checks."
    echo
}

validate_file() {
    local file="$1"
    [[ -f "$file" ]]
}

validate_executable() {
    local file="$1"
    [[ -x "$file" ]]
}

validate_config() {
    local config="$ROOT/config/pgupgrade.conf"
    [[ -f "$config" ]] || return 1

    # shellcheck disable=SC1090
    source "$config"

    local required_variables=(
        OLD_PG_CONFIG
        NEW_PG_CONFIG
        OLD_DATA_DIR
        NEW_DATA_DIR
        PG_SERVICE_NAME
        PG_OS_USER
    )

    local variable
    for variable in "${required_variables[@]}"; do
        declare -p "$variable" &>/dev/null || return 1
    done
}

validate() {
    local failed=0
    local directories_status="PASS"
    local configuration_status="PASS"
    local main_script_status="PASS"
    local destroy_script_status="PASS"
    local executability_status="PASS"
    local bash_syntax_status="PASS"

    echo
    echo "============================================================"
    echo " PostgreSQL In-Place Major Upgrade Framework"
    echo " Validation"
    echo "============================================================"
    echo

    info "Project root: $ROOT"
    echo

    progress "Checking required directories"
    for dir in "$ROOT/scripts" "$ROOT/config" "$ROOT/runs"; do
        if [[ -d "$dir" ]]; then
            success "Directory exists: $dir"
        else
            error "Directory missing: $dir"
            directories_status="FAIL"
            failed=1
        fi
    done

    echo
    progress "Checking configuration file"
    if validate_file "$ROOT/config/pgupgrade.conf"; then
        success "File exists: $ROOT/config/pgupgrade.conf"
    else
        error "Missing file: $ROOT/config/pgupgrade.conf"
        configuration_status="FAIL"
        failed=1
    fi

    echo
    progress "Checking main workflow script"
    if validate_file "$ROOT/scripts/postgres_pg_major_upgrade_inplace.sh"; then
        success "File exists: $ROOT/scripts/postgres_pg_major_upgrade_inplace.sh"
    else
        error "Missing file: $ROOT/scripts/postgres_pg_major_upgrade_inplace.sh"
        main_script_status="FAIL"
        failed=1
    fi

    progress "Checking destroy utility"
    if validate_file "$ROOT/scripts/destroy.sh"; then
        success "File exists: $ROOT/scripts/destroy.sh"
    else
        error "Missing file: $ROOT/scripts/destroy.sh"
        destroy_script_status="FAIL"
        failed=1
    fi

    echo
    progress "Checking executable permissions"
    local executable_checks=0
    if [[ -f "$ROOT/scripts/postgres_pg_major_upgrade_inplace.sh" ]]; then
        executable_checks=1
        if validate_executable "$ROOT/scripts/postgres_pg_major_upgrade_inplace.sh"; then
            success "Executable: postgres_pg_major_upgrade_inplace.sh"
        else
            error "Not executable: postgres_pg_major_upgrade_inplace.sh"
            executability_status="FAIL"
            failed=1
        fi
    else
        warning "SKIP: main workflow script is missing"
    fi

    if [[ -f "$ROOT/scripts/destroy.sh" ]]; then
        executable_checks=1
        if validate_executable "$ROOT/scripts/destroy.sh"; then
            success "Executable: destroy.sh"
        else
            error "Not executable: destroy.sh"
            executability_status="FAIL"
            failed=1
        fi
    else
        warning "SKIP: destroy.sh is missing"
    fi

    if [[ "$executable_checks" -eq 0 ]]; then
        executability_status="SKIPPED"
    fi

    echo
    progress "Checking Bash syntax"
    local syntax_checks=0
    if [[ -f "$ROOT/scripts/postgres_pg_major_upgrade_inplace.sh" ]]; then
        syntax_checks=1
        if bash -n "$ROOT/scripts/postgres_pg_major_upgrade_inplace.sh"; then
            success "Syntax OK: postgres_pg_major_upgrade_inplace.sh"
        else
            error "Syntax check failed: postgres_pg_major_upgrade_inplace.sh"
            bash_syntax_status="FAIL"
            failed=1
        fi
    else
        warning "SKIP: main workflow script is missing"
    fi

    if [[ -f "$ROOT/scripts/destroy.sh" ]]; then
        syntax_checks=1
        if bash -n "$ROOT/scripts/destroy.sh"; then
            success "Syntax OK: destroy.sh"
        else
            error "Syntax check failed: destroy.sh"
            bash_syntax_status="FAIL"
            failed=1
        fi
    else
        warning "SKIP: destroy.sh is missing"
    fi

    if [[ "$syntax_checks" -eq 0 ]]; then
        bash_syntax_status="SKIPPED"
    fi

    echo
    progress "Checking configuration variables"
    if validate_config; then
        success "All required configuration variables are present"
    else
        error "Configuration validation failed"
        configuration_status="FAIL"
        failed=1
    fi

    echo
    echo "============================================================"
    echo " Validation Summary"
    echo "============================================================"
    echo

    print_status "Directories" "$directories_status"
    print_status "Configuration" "$configuration_status"
    print_status "Main script" "$main_script_status"
    print_status "Destroy script" "$destroy_script_status"
    print_status "Executability" "$executability_status"
    print_status "Bash syntax" "$bash_syntax_status"

    echo

    if [[ "$failed" -ne 0 ]]; then
        echo "============================================================"
        error "INIT VALIDATION FAILED"
        echo "============================================================"
        echo
        echo "Review the failed checks above."
        echo "Fix the issue(s), then run:"
        echo
        echo "    ./init.sh validate"
        echo
        return 1
    fi

    echo "============================================================"
    echo -e " ${GREEN}INIT SUCCESS${NC}"
    echo "============================================================"
    echo
    echo "All framework initialization checks passed."
    echo
    echo  -e "${GREEN} ========>> You may start performing upgrade activities now!${NC}"
    echo
}

case "${1:-}" in
    "")
        bootstrap
        ;;
    validate)
        validate
        ;;
    *)
        error "Unknown command: $1"
        echo
        echo "Usage:"
        echo
        echo "    ./init.sh"
        echo "    ./init.sh validate"
        echo
        exit 1
        ;;
esac