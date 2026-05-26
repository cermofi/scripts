#!/bin/bash

# LogMan.io pre-install checks.
# Site-specific values are kept in this first section on purpose.

set -euo pipefail

# Configuration

# Deployment profile

DEPLOYMENT_USER="tladmin"
REQUIRED_ADMIN_GROUPS=("sudo" "wheel")
REQUIRED_DOCKER_GROUP="docker"
SUDO_COMMAND="sudo"

INSTALL_MODE="single"
NODE_ROLE="core"
SUPPORTED_INSTALL_MODES=("single" "cluster-first" "cluster-additional")
SUPPORTED_NODE_ROLES=("core" "collector" "arbiter")

SUPPORTED_OS_NAME="Ubuntu"
SUPPORTED_OS_VERSIONS=("22.04" "24.04")
COMPATIBLE_OS_VERSION_WARN=""
OS_RELEASE_FILE="/etc/os-release"

REQUIRED_TIMEZONE="UTC"
ALLOWED_TIMEZONES=("UTC" "Etc/UTC")
TIMEZONE_FILE="/etc/timezone"
LOCALTIME_FILE="/etc/localtime"
ZONEINFO_PREFIX="/usr/share/zoneinfo/"
TIME_SYNC_SERVICES=("chronyd" "chrony" "systemd-timesyncd" "ntp" "ntpd")

# Fill this only when cluster hostnames are already known.
EXPECTED_CLUSTER_HOSTNAMES=()

# Netplan / cloud-init networking

NETPLAN_COMMAND="netplan"
NETPLAN_DIR="/etc/netplan"
NETPLAN_CONFIG_GLOB="*.yaml"
DISALLOWED_NETPLAN_CONFIGS=(
    "/etc/netplan/50-cloud-init.yaml"
)

# Hardware sizing

MIN_CPU_CORES=32
RECOMMENDED_CPU_CORES=32

MIN_RAM_GB=256
RECOMMENDED_RAM_GB=256

# System storage

ROOT_MOUNT="/"
VAR_LOG_MOUNT="/var/log"
EXPECTED_DOCKER_ROOT_DIR="/var/lib/docker"

MIN_ROOT_GB=50
RECOMMENDED_ROOT_GB=200

MIN_VAR_LOG_GB=50
RECOMMENDED_VAR_LOG_GB=50

MIN_DOCKER_ROOT_GB=100
RECOMMENDED_DOCKER_ROOT_GB=100

# Data storage

SLOW_DATA_MOUNT="/data/hdd"
FAST_DATA_MOUNT="/data/ssd"
DATA_MOUNT_POINTS=("$SLOW_DATA_MOUNT" "$FAST_DATA_MOUNT")

MIN_FAST_DATA_GB=0
RECOMMENDED_FAST_DATA_MIN_GB=2048
RECOMMENDED_FAST_DATA_MAX_GB=4096

MIN_SLOW_DATA_GB=40960
RECOMMENDED_SLOW_DATA_DRIVES=3
RECOMMENDED_SLOW_DATA_DRIVE_GB=20000
RECOMMENDED_SLOW_DATA_USABLE_GB=40000

RECOMMENDED_DATA_FS_TYPE="ext4"
RECOMMENDED_DATA_MOUNT_OPTION="noatime"
IGNORED_CLEAN_DIR_NAME="lost+found"

# RAID and fstab

MDADM_COMMAND="mdadm"
MDSTAT_FILE="/proc/mdstat"
FSTAB_FILE="/etc/fstab"
EXPECTED_FAST_RAID_LEVELS=("raid1")
EXPECTED_SLOW_RAID_LEVELS=("raid5" "raid6")

# Installation paths

INSTALL_SITE_DIR="/opt/site"

# Swap

MIN_SWAP_PER_DEVICE_GB=64
RECOMMENDED_SWAP_DEVICES=2
MIN_SWAP_TOTAL_GB=$(( MIN_SWAP_PER_DEVICE_GB * RECOMMENDED_SWAP_DEVICES ))
SWAP_SIZE_TOLERANCE_MB=1

# Docker

DOCKER_VERSION_WARN_FLOOR=""
DOCKER_SERVICE_NAME="docker"
CONTAINERD_SERVICE_NAME="containerd"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
EXPECTED_DOCKER_BRIDGE="none"
DOCKER_DEFAULT_BRIDGE_INTERFACE="docker0"
DPKG_COMMAND="dpkg"
APT_CACHE_COMMAND="apt-cache"
DOCKER_APT_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_APT_SOURCE_FILE="/etc/apt/sources.list.d/docker.list"
DOCKER_APT_SOURCE_DOMAIN="download.docker.com"
REQUIRED_DOCKER_PACKAGES=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-compose-plugin"
)

# WireGuard

ENABLE_WIREGUARD_CHECKS="auto" # auto|true|false
WIREGUARD_COMMAND="wg"
WIREGUARD_QUICK_COMMAND="wg-quick"
WIREGUARD_INTERFACE="wg0"
WIREGUARD_CONFIG_FILE="/etc/wireguard/wg0.conf"
WIREGUARD_SERVICE_NAME="wg-quick@wg0.service"
WIREGUARD_LISTEN_PORT=41194
WIREGUARD_MTU=1412
WIREGUARD_PERSISTENT_KEEPALIVE=60

# SSH / user permissions

SSH_DIR_NAME=".ssh"
AUTHORIZED_KEYS_FILE="authorized_keys"
REQUIRED_SSH_DIR_MODE="700"
REQUIRED_AUTHORIZED_KEYS_MODE="600"
NON_LOGIN_SHELL_REGEX='/(false|nologin)$'

# SSH daemon hardening

SSHD_COMMAND="sshd"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
SSH_HOST_KEY_GLOB="/etc/ssh/ssh_host_*_key"
DISALLOWED_SSHD_DROPINS=(
    "/etc/ssh/sshd_config.d/50-cloud-init.conf"
)
REQUIRED_SSHD_SETTINGS=(
    "permitrootlogin=no"
    "pubkeyauthentication=yes"
    "passwordauthentication=no"
)

# LogMan.io sysctl configuration

SYSCTL_CONF_FILE="/etc/sysctl.d/01-logman-io.conf"
REQUIRED_VM_MAX_MAP_COUNT=262144
REQUIRED_UNPRIVILEGED_PORT_START=80
REQUIRED_INOTIFY_MAX_USER_INSTANCES=1024
REQUIRED_INOTIFY_MAX_USER_WATCHES=1048576
REQUIRED_INOTIFY_MAX_QUEUED_EVENTS=16384

# Network checks

CONNECTIVITY_TEST_URL="https://download.docker.com"
HTTP_PORT=80
HTTPS_PORT=443
CURL_CONNECT_TIMEOUT_SECONDS=5
CURL_MAX_TIME_SECONDS=15

REQUIRED_HTTPS_DOMAINS=(
    "docker.teskalabs.com"
    "pcr.teskalabs.com"
    "rcr.teskalabs.com"
    "registry-1.docker.io"
    "auth.docker.io"
    "docker-images-prod.6aa30f8b08e16409b46e0173d6de2f56.r2.cloudflarestorage.com"
    "production.cloudflare.docker.com"
    "asabwebui.z16.web.core.windows.net"
    "webappsreg.z6.web.core.windows.net"
    "webappsreg-secondary.z6.web.core.windows.net"
    "download.docker.com"
    "libsreg.z6.web.core.windows.net"
    "libsreg-secondary.z6.web.core.windows.net"
    "lmio.blob.core.windows.net"
)

OS_UPDATE_DOMAINS=(
    "archive.ubuntu.com"
    "security.ubuntu.com"
    "cz.archive.ubuntu.com"
)

DNS_TEST_DOMAINS=(
    "docker.teskalabs.com"
    "lmio.blob.core.windows.net"
    "download.docker.com"
    "archive.ubuntu.com"
)

RESOLV_CONF_FILE="/etc/resolv.conf"
RESOLVECTL_COMMAND="resolvectl"
CHRONYC_COMMAND="chronyc"
NTPQ_COMMAND="ntpq"

INSTALL_SCRIPT_URLS=(
    "https://lmio.blob.core.windows.net/library/lmio/install-ubuntu2204.sh"
)

SECONDARY_BOOTSTRAP_IMAGE="pcr.teskalabs.com/asab/asab-governator:stable"

# Ports which should be free before the LogMan.io containers are started.
PORT_CONFLICT_TCP_PORTS=(
    80 443
    3080 3081 3443
    8890 8891 8892 8893 8894 8895 8896 8897 8898
    8900 8910 8920
    8950 8951 8952 8953 8954 8955 8956 8957 8958 8959
    8960 8961 8962 8963 8964 8965 8966
    8999
    8790 8810
    9092 9000 2181 9001 8086 8888 5601 3000 27017
)

# Output

TABLE_MESSAGE_WIDTH=120
TABLE_RULE_WIDTH=122

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'
OK="${GREEN}OK${RESET}"
WARN="${YELLOW}WARN${RESET}"
FAIL="${RED}FAIL${RESET}"

print_result() {
    local status="$1"
    local message="$2"
    printf "| %-${TABLE_MESSAGE_WIDTH}s | %b\n" "$message" "$status"
}

print_section_header() {
    local section_name="$1"
    printf "\n${BLUE}%s${RESET}\n" "$section_name"
    printf "%-${TABLE_RULE_WIDTH}s | Status\n" "--------------------------------------------------------------------------------------------------------------------------"
}

prompt_install_mode() {
    normalize_install_mode

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        printf "${YELLOW}Non-interactive run detected; using %s from configuration.${RESET}\n" "$(install_mode_label)"
        return
    fi

    local answer=""

    if command_exists whiptail; then
        if answer=$(whiptail \
            --title "LogMan.io prerequisite check" \
            --menu "Select deployment mode" \
            14 76 3 \
            "single" "Single node" \
            "cluster-first" "Cluster (first node)" \
            "cluster-additional" "Cluster (second / third node)" \
            3>&1 1>&2 2>&3); then
            INSTALL_MODE="$answer"
        else
            printf "${YELLOW}Deployment mode selection cancelled. Exiting.${RESET}\n"
            exit 130
        fi
        normalize_install_mode
        printf "${GREEN}Using %s${RESET}\n" "$(install_mode_label)"
        return
    fi

    if command_exists dialog; then
        if answer=$(dialog \
            --stdout \
            --title "LogMan.io prerequisite check" \
            --menu "Select deployment mode" \
            14 76 3 \
            "single" "Single node" \
            "cluster-first" "Cluster (first node)" \
            "cluster-additional" "Cluster (second / third node)"); then
            INSTALL_MODE="$answer"
        else
            printf "${YELLOW}Deployment mode selection cancelled. Exiting.${RESET}\n"
            exit 130
        fi
        normalize_install_mode
        printf "${GREEN}Using %s${RESET}\n" "$(install_mode_label)"
        return
    fi

    while true; do
        printf "\n${BLUE}Select LogMan.io deployment mode${RESET}\n"
        printf "Type deployment mode [single/cluster-first/cluster-additional, default: %s]: " "$INSTALL_MODE"
        read -r answer

        case "${answer:-$INSTALL_MODE}" in
            single|single-node|single_node)
                INSTALL_MODE="single"
                break
                ;;
            cluster|cluster-first|cluster_first|first|first-node|first_node)
                INSTALL_MODE="cluster-first"
                break
                ;;
            cluster-additional|cluster_additional|additional|second|third|second-third|second_third)
                INSTALL_MODE="cluster-additional"
                break
                ;;
            *)
                printf "${YELLOW}Please type single, cluster-first, or cluster-additional.${RESET}\n"
                ;;
        esac
    done

    normalize_install_mode
    printf "${GREEN}Using %s${RESET}\n" "$(install_mode_label)"
}

# Generic helpers

command_exists() {
    command -v "$1" &> /dev/null
}

normalize_install_mode() {
    case "$INSTALL_MODE" in
        single|single-node|single_node)
            INSTALL_MODE="single"
            ;;
        cluster|cluster-first|cluster_first|first|first-node|first_node)
            INSTALL_MODE="cluster-first"
            ;;
        cluster-additional|cluster_additional|additional|second|third|second-third|second_third)
            INSTALL_MODE="cluster-additional"
            ;;
    esac
}

install_mode_label() {
    case "$INSTALL_MODE" in
        single)
            printf "Single node"
            ;;
        cluster-first)
            printf "Cluster (first node)"
            ;;
        cluster-additional)
            printf "Cluster (second / third node)"
            ;;
        *)
            printf "INSTALL_MODE=%s" "$INSTALL_MODE"
            ;;
    esac
}

is_cluster_mode() {
    case "$INSTALL_MODE" in
        cluster-first|cluster-additional)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_cluster_additional_mode() {
    [ "$INSTALL_MODE" = "cluster-additional" ]
}

# Read one field from passwd data. getent is preferred because it respects NSS.
get_passwd_field() {
    local user="$1"
    local field="$2"

    if command_exists getent; then
        getent passwd "$user" | awk -F: -v field="$field" '{print $field}' || true
    else
        awk -F: -v user="$user" -v field="$field" '$1 == user {print $field}' /etc/passwd 2>/dev/null || true
    fi
}

# Return numeric file permissions in a Linux/macOS compatible way.
get_file_mode() {
    local path="$1"

    if stat -c "%a" "$path" >/dev/null 2>&1; then
        stat -c "%a" "$path"
    elif stat -f "%Lp" "$path" >/dev/null 2>&1; then
        stat -f "%Lp" "$path"
    fi
    return 0
}

get_sysctl_value() {
    local key="$1"
    sysctl -n "$key" 2>/dev/null || true
}

is_positive_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

user_groups_contain_any() {
    local groups="$1"
    shift
    local group

    for group in "$@"; do
        if echo " $groups " | grep -qw "$group"; then
            return 0
        fi
    done

    return 1
}

run_privileged_command() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command_exists "$SUDO_COMMAND"; then
        "$SUDO_COMMAND" -n "$@"
    else
        "$@"
    fi
}

gb_to_kb() {
    local gb="$1"
    echo $(( gb * 1024 * 1024 ))
}

# Read a sysctl value from a persistent config file.
# Supports both "key = value" and "key value" syntax and ignores comments.
get_sysctl_conf_value() {
    local key="$1"
    local file="${2:-$SYSCTL_CONF_FILE}"

    awk -v key="$key" '
        /^[[:space:]]*#/ { next }
        {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "") {
                next
            }

            if (index(line, "=") > 0) {
                split(line, parts, "=")
                k = parts[1]
                v = substr(line, index(line, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                if (k == key) {
                    value = v
                }
            } else {
                split(line, parts, /[[:space:]]+/)
                if (parts[1] == key && parts[2] != "") {
                    value = parts[2]
                }
            }
        }
        END {
            if (value != "") {
                print value
            }
        }
    ' "$file" 2>/dev/null
}

# Check that a persistent sysctl value exists and is at least the given value.
check_sysctl_conf_min() {
    local key="$1"
    local min_value="$2"
    local value

    value=$(get_sysctl_conf_value "$key")
    if [ -z "$value" ]; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE is missing $key"
    elif ! is_positive_integer "$value"; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE: $key must be numeric. Configured: $value"
    elif [ "$value" -lt "$min_value" ]; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE: $key must be at least $min_value. Configured: $value"
    else
        print_result "$OK" "$SYSCTL_CONF_FILE: $key=$value"
    fi
}

# Check that a persistent sysctl value exists and is not above the given value.
check_sysctl_conf_max() {
    local key="$1"
    local max_value="$2"
    local value

    value=$(get_sysctl_conf_value "$key")
    if [ -z "$value" ]; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE is missing $key"
    elif ! is_positive_integer "$value"; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE: $key must be numeric. Configured: $value"
    elif [ "$value" -gt "$max_value" ]; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE: $key must be $max_value or lower. Configured: $value"
    else
        print_result "$OK" "$SYSCTL_CONF_FILE: $key=$value"
    fi
}

# A deployment directory is considered clean when it is empty or only contains
# the usual lost+found directory created by some filesystems.
directory_is_clean() {
    local path="$1"
    [ -d "$path" ] && [ -z "$(find "$path" -mindepth 1 -maxdepth 1 ! -name "$IGNORED_CLEAN_DIR_NAME" -print -quit 2>/dev/null)" ]
}

get_fstab_field() {
    local mount_point="$1"
    local field="$2"

    awk -v mount_point="$mount_point" -v field="$field" '
        /^[[:space:]]*#/ { next }
        NF >= 4 && $2 == mount_point { value = $field }
        END { if (value != "") print value }
    ' "$FSTAB_FILE" 2>/dev/null
}

get_mount_source() {
    local mount_point="$1"
    findmnt -no SOURCE --target "$mount_point" 2>/dev/null || true
}

get_wireguard_config_value() {
    local section="$1"
    local key="$2"
    local file="${3:-$WIREGUARD_CONFIG_FILE}"

    awk -F= -v section="$section" -v key="$key" '
        /^[[:space:]]*#/ { next }
        /^\[/ {
            current = $0
            gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", current)
            next
        }
        current == section {
            k = $1
            v = substr($0, index($0, "=") + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (k == key) {
                print v
                exit
            }
        }
    ' "$file" 2>/dev/null
}

wireguard_peer_count() {
    local file="${1:-$WIREGUARD_CONFIG_FILE}"
    grep -Ec '^[[:space:]]*\[Peer\][[:space:]]*$' "$file" 2>/dev/null || true
}

normalize_ss_output() {
    sed 's/[[:space:]]\+/ /g' | cut -c 1-115
}

ssh_host_keys_available() {
    compgen -G "$SSH_HOST_KEY_GLOB" >/dev/null
}

# Header

print_header() {
    cat << "EOF"

  _                 __  __               _
 | |               |  \/  |             (_)
 | |     ___   __ _| \  / | __ _ _ __    _  ___
 | |    / _ \ / _` | |\/| |/ _` | '_ \  | |/ _ \
 | |___| (_) | (_| | |  | | (_| | | | |_| | (_) |
 |______\___/ \__, |_|  |_|\__,_|_| |_(_)_|\___/
               __/ |
              |___/
                                        TeskaLabs
EOF
}

# Checks

check_cpu_cores() {
    local cpu_cores
    cpu_cores=$(nproc)

    if [ "$MIN_CPU_CORES" -gt 0 ] && [ "$cpu_cores" -lt "$MIN_CPU_CORES" ]; then
        print_result "$FAIL" "Minimum CPU core count is ${MIN_CPU_CORES}. Detected: $cpu_cores"
    elif [ "$cpu_cores" -lt "$RECOMMENDED_CPU_CORES" ]; then
        print_result "$WARN" "CPU core count is below LogMan.io hardware specification (${RECOMMENDED_CPU_CORES} cores). Detected: $cpu_cores"
    else
        print_result "$OK" "CPU core count: $cpu_cores (meets LogMan.io hardware specification)"
    fi
}

check_ram() {
    local ram_gb
    ram_gb=$(awk '/^MemTotal:/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || true)

    if [ -z "$ram_gb" ]; then
        print_result "$WARN" "Unable to determine RAM size."
    elif [ "$MIN_RAM_GB" -gt 0 ] && [ "$ram_gb" -lt "$MIN_RAM_GB" ]; then
        print_result "$FAIL" "Minimum RAM is ${MIN_RAM_GB} GB. Detected: $ram_gb GB"
    elif [ "$ram_gb" -lt "$RECOMMENDED_RAM_GB" ]; then
        print_result "$WARN" "RAM is below LogMan.io hardware specification (${RECOMMENDED_RAM_GB} GB). Detected: $ram_gb GB"
    else
        print_result "$OK" "RAM: $ram_gb GB (meets LogMan.io hardware specification)"
    fi
}

# Verify basic outbound connectivity before more specific domain checks.
check_network() {
    if command_exists wget && wget --spider -q "$CONNECTIVITY_TEST_URL" &> /dev/null; then
        print_result "$OK" "Network connectivity is available"
    else
        print_result "$WARN" "Generic internet connectivity check failed. Review the specific LogMan.io endpoint checks below."
    fi
}

# LogMan.io hosts should run in UTC to keep log timestamps consistent.
check_timezone() {
    local timezone=""

    if command_exists timedatectl; then
        timezone=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    fi

    if [ -z "$timezone" ] && [ -f "$TIMEZONE_FILE" ]; then
        timezone=$(head -n 1 "$TIMEZONE_FILE" 2>/dev/null)
    fi

    if [ -z "$timezone" ] && [ -L "$LOCALTIME_FILE" ] && command_exists readlink; then
        local localtime_target
        localtime_target=$(readlink -f "$LOCALTIME_FILE" 2>/dev/null || true)
        timezone=${localtime_target#"$ZONEINFO_PREFIX"}
    fi

    if array_contains "$timezone" "${ALLOWED_TIMEZONES[@]}"; then
        print_result "$OK" "System timezone: $timezone"
    elif [ -n "$timezone" ]; then
        print_result "$FAIL" "System timezone must be $REQUIRED_TIMEZONE for LogMan.io. Detected: $timezone"
    else
        print_result "$WARN" "Unable to determine system timezone. Expected: $REQUIRED_TIMEZONE"
    fi
}

# Confirm that the host clock is synchronized via timedatectl or a known NTP service.
check_time_synchronization() {
    local ntp_synchronized=""
    local ntp_enabled=""
    local active_services=()
    local service

    if command_exists timedatectl; then
        ntp_synchronized=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
        ntp_enabled=$(timedatectl show -p NTP --value 2>/dev/null || true)
    fi

    if command_exists systemctl; then
        for service in "${TIME_SYNC_SERVICES[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                active_services+=("$service")
            fi
        done
    fi

    if [ "$ntp_synchronized" = "yes" ]; then
        print_result "$OK" "Clock synchronization: NTPSynchronized=yes"
    elif [ "${#active_services[@]}" -gt 0 ]; then
        print_result "$WARN" "Time sync service is active (${active_services[*]}), but timedatectl does not report synchronized time."
    elif [ "$ntp_enabled" = "yes" ]; then
        print_result "$WARN" "NTP is enabled, but timedatectl does not report synchronized time."
    elif command_exists timedatectl; then
        print_result "$WARN" "Clock synchronization is not confirmed. Enable NTP/chrony before LogMan.io deployment."
    else
        print_result "$WARN" "Unable to verify time synchronization (timedatectl not found)."
    fi
}

check_dns_ntp_health() {
    if [ -s "$RESOLV_CONF_FILE" ] && grep -Eq '^[[:space:]]*nameserver[[:space:]]+' "$RESOLV_CONF_FILE"; then
        print_result "$OK" "$RESOLV_CONF_FILE contains DNS nameserver entries."
    elif command_exists "$RESOLVECTL_COMMAND" && "$RESOLVECTL_COMMAND" dns >/dev/null 2>&1; then
        print_result "$OK" "$RESOLVECTL_COMMAND reports configured DNS servers."
    else
        print_result "$FAIL" "No DNS resolver configuration detected in $RESOLV_CONF_FILE or via $RESOLVECTL_COMMAND."
    fi

    local domain
    for domain in "${DNS_TEST_DOMAINS[@]}"; do
        if getent hosts "$domain" >/dev/null 2>&1; then
            print_result "$OK" "DNS resolution works for $domain."
        else
            print_result "$FAIL" "DNS resolution failed for $domain."
        fi
    done

    if command_exists timedatectl; then
        local ntp_sync
        ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
        if [ "$ntp_sync" = "yes" ]; then
            print_result "$OK" "NTP synchronization is confirmed by timedatectl."
        else
            print_result "$WARN" "timedatectl does not confirm NTP synchronization."
        fi

        if timedatectl timesync-status >/dev/null 2>&1; then
            print_result "$OK" "timedatectl timesync-status is available."
        else
            print_result "$WARN" "timedatectl timesync-status is unavailable; chrony/ntpd may be used instead."
        fi
    fi

    if command_exists "$CHRONYC_COMMAND"; then
        if "$CHRONYC_COMMAND" tracking >/dev/null 2>&1; then
            print_result "$OK" "$CHRONYC_COMMAND tracking works."
        else
            print_result "$WARN" "$CHRONYC_COMMAND is installed but tracking check failed."
        fi
    elif command_exists "$NTPQ_COMMAND"; then
        if "$NTPQ_COMMAND" -pn >/dev/null 2>&1; then
            print_result "$OK" "$NTPQ_COMMAND peer check works."
        else
            print_result "$WARN" "$NTPQ_COMMAND is installed but peer check failed."
        fi
    else
        print_result "$WARN" "No chronyc/ntpq command found for detailed NTP health checks."
    fi
}

check_netplan_configuration() {
    if [ -d "$NETPLAN_DIR" ]; then
        print_result "$OK" "Netplan directory exists: $NETPLAN_DIR"
    else
        print_result "$FAIL" "Netplan directory is missing: $NETPLAN_DIR"
        return
    fi

    local disallowed_config
    for disallowed_config in "${DISALLOWED_NETPLAN_CONFIGS[@]}"; do
        if [ -e "$disallowed_config" ]; then
            print_result "$FAIL" "Cloud-init Netplan config still exists: $disallowed_config"
        else
            print_result "$OK" "Cloud-init Netplan config is absent: $disallowed_config"
        fi
    done

    local custom_config=""
    local file
    for file in "$NETPLAN_DIR"/$NETPLAN_CONFIG_GLOB; do
        [ -e "$file" ] || continue

        local skip=false
        local disallowed
        for disallowed in "${DISALLOWED_NETPLAN_CONFIGS[@]}"; do
            if [ "$file" = "$disallowed" ]; then
                skip=true
                break
            fi
        done

        if [ "$skip" = false ]; then
            custom_config="$file"
            break
        fi
    done

    if [ -n "$custom_config" ]; then
        print_result "$OK" "Custom Netplan config detected: $custom_config"
    else
        print_result "$FAIL" "No custom Netplan YAML config found in $NETPLAN_DIR."
    fi

    if ! command_exists "$NETPLAN_COMMAND"; then
        print_result "$FAIL" "$NETPLAN_COMMAND command not found."
        return
    fi

    if "$NETPLAN_COMMAND" get >/dev/null 2>&1; then
        print_result "$OK" "$NETPLAN_COMMAND get works."
    else
        print_result "$WARN" "$NETPLAN_COMMAND get failed; review Netplan configuration."
    fi

    if run_privileged_command "$NETPLAN_COMMAND" generate >/dev/null 2>&1; then
        print_result "$OK" "$NETPLAN_COMMAND generate completed successfully."
    else
        print_result "$WARN" "$NETPLAN_COMMAND generate failed or requires interactive sudo."
    fi
}

check_hostname_resolvability() {
    local short_hostname
    local fqdn

    short_hostname=$(hostname -s 2>/dev/null || true)
    fqdn=$(hostname -f 2>/dev/null || true)

    if [ -n "$short_hostname" ]; then
        print_result "$OK" "Short hostname / node id: $short_hostname"
        if getent hosts "$short_hostname" >/dev/null 2>&1; then
            print_result "$OK" "Hostname resolves: $short_hostname"
        else
            print_result "$FAIL" "Hostname must be resolvable before LogMan.io install: $short_hostname"
        fi
    else
        print_result "$FAIL" "Unable to determine short hostname."
    fi

    if [ -n "$fqdn" ]; then
        print_result "$OK" "FQDN: $fqdn"
    else
        print_result "$WARN" "hostname -f did not return an FQDN."
    fi

    if is_cluster_mode; then
        if [ "${#EXPECTED_CLUSTER_HOSTNAMES[@]}" -eq 0 ]; then
            print_result "$WARN" "$(install_mode_label) selected, but EXPECTED_CLUSTER_HOSTNAMES is empty."
        else
            local node
            for node in "${EXPECTED_CLUSTER_HOSTNAMES[@]}"; do
                if getent hosts "$node" >/dev/null 2>&1; then
                    print_result "$OK" "Cluster hostname resolves: $node"
                else
                    print_result "$FAIL" "Cluster hostname does not resolve: $node"
                fi
            done
        fi
    fi
}

check_root_partition() {
    local size_h size_kb
    size_h=$(df -h "$ROOT_MOUNT" | awk 'NR==2 {print $2}')
    size_kb=$(df "$ROOT_MOUNT" --output=size | tail -1)

    if [ "$size_kb" -lt "$(gb_to_kb "$MIN_ROOT_GB")" ]; then
        print_result "$FAIL" "$ROOT_MOUNT partition must be at least ${MIN_ROOT_GB}GB per LogMan.io system storage layout. Detected: $size_h"
    elif [ "$size_kb" -lt "$(gb_to_kb "$RECOMMENDED_ROOT_GB")" ]; then
        print_result "$WARN" "$ROOT_MOUNT partition is below recommended ${RECOMMENDED_ROOT_GB}GB from the bare-metal walkthrough. Detected: $size_h"
    else
        print_result "$OK" "$ROOT_MOUNT partition has sufficient capacity: $size_h"
    fi
}

check_var_log_partition() {
    local size_h size_kb
    size_h=$(df -h "$VAR_LOG_MOUNT" | awk 'NR==2 {print $2}')
    size_kb=$(df "$VAR_LOG_MOUNT" --output=size | tail -1)

    if [ "$size_kb" -lt "$(gb_to_kb "$MIN_VAR_LOG_GB")" ]; then
        print_result "$FAIL" "$VAR_LOG_MOUNT partition must be at least ${MIN_VAR_LOG_GB}GB per LogMan.io system storage layout. Detected: $size_h"
    elif [ "$size_kb" -lt "$(gb_to_kb "$RECOMMENDED_VAR_LOG_GB")" ]; then
        print_result "$WARN" "$VAR_LOG_MOUNT partition is below recommended ${RECOMMENDED_VAR_LOG_GB}GB. Detected: $size_h"
    else
        print_result "$OK" "$VAR_LOG_MOUNT partition has sufficient capacity: $size_h"
    fi
}

check_slow_data_storage() {
    if mountpoint -q "$SLOW_DATA_MOUNT"; then
        local size_h size_kb
        size_h=$(df -h "$SLOW_DATA_MOUNT" | awk 'NR==2 {print $2}')
        size_kb=$(df "$SLOW_DATA_MOUNT" --output=size | tail -1)

        if [ "$MIN_SLOW_DATA_GB" -gt 0 ] && [ "$size_kb" -lt "$(gb_to_kb "$MIN_SLOW_DATA_GB")" ]; then
            print_result "$FAIL" "Slow data storage must be at least ${MIN_SLOW_DATA_GB}GB. Detected: $size_h"
        elif [ "$size_kb" -lt "$(gb_to_kb "$RECOMMENDED_SLOW_DATA_USABLE_GB")" ]; then
            print_result "$WARN" "Slow data storage is below recommended usable capacity (~${RECOMMENDED_SLOW_DATA_USABLE_GB}GB from ${RECOMMENDED_SLOW_DATA_DRIVES} x ${RECOMMENDED_SLOW_DATA_DRIVE_GB}GB RAID5). Detected: $size_h"
        else
            print_result "$OK" "Slow data storage is mounted at $SLOW_DATA_MOUNT with recommended capacity: $size_h"
        fi
    else
        print_result "$FAIL" "Slow data storage is not mounted at $SLOW_DATA_MOUNT."
    fi
}

check_fast_data_storage() {
    if mountpoint -q "$FAST_DATA_MOUNT"; then
        local size_h size_kb
        size_h=$(df -h "$FAST_DATA_MOUNT" | awk 'NR==2 {print $2}')
        size_kb=$(df "$FAST_DATA_MOUNT" --output=size | tail -1)

        if [ "$MIN_FAST_DATA_GB" -gt 0 ] && [ "$size_kb" -lt "$(gb_to_kb "$MIN_FAST_DATA_GB")" ]; then
            print_result "$FAIL" "Fast data storage must be at least ${MIN_FAST_DATA_GB}GB. Detected: $size_h"
        elif [ "$size_kb" -lt "$(gb_to_kb "$RECOMMENDED_FAST_DATA_MIN_GB")" ]; then
            print_result "$WARN" "Fast data storage is below LogMan.io recommended size (${RECOMMENDED_FAST_DATA_MIN_GB}-${RECOMMENDED_FAST_DATA_MAX_GB}GB). Detected: $size_h"
        else
            print_result "$OK" "Fast data storage is mounted at $FAST_DATA_MOUNT with recommended capacity: $size_h"
        fi
    else
        print_result "$FAIL" "Fast data storage is not mounted at $FAST_DATA_MOUNT."
    fi
}

# Validate that the expected pre-install directories are clean and real mounts.
check_installation_directories() {
    if [ ! -e "$INSTALL_SITE_DIR" ]; then
        print_result "$OK" "$INSTALL_SITE_DIR does not exist yet (clean pre-install state)."
    elif [ ! -d "$INSTALL_SITE_DIR" ]; then
        print_result "$FAIL" "$INSTALL_SITE_DIR exists but is not a directory."
    elif directory_is_clean "$INSTALL_SITE_DIR"; then
        print_result "$OK" "$INSTALL_SITE_DIR exists and is empty."
    else
        print_result "$FAIL" "$INSTALL_SITE_DIR is not empty. Pre-install LogMan.io site directory should be clean."
    fi

    local data_dir
    for data_dir in "${DATA_MOUNT_POINTS[@]}"; do
        if [ ! -d "$data_dir" ]; then
            print_result "$FAIL" "$data_dir does not exist."
            continue
        fi

        if mountpoint -q "$data_dir"; then
            print_result "$OK" "$data_dir is a mount point."
        else
            print_result "$FAIL" "$data_dir is not a mount point; it may be only a directory on the root filesystem."
        fi

        if directory_is_clean "$data_dir"; then
            print_result "$OK" "$data_dir is clean (empty or only $IGNORED_CLEAN_DIR_NAME)."
        else
            print_result "$FAIL" "$data_dir contains files/directories other than $IGNORED_CLEAN_DIR_NAME. Verify this is not a stale LogMan.io installation."
        fi
    done
}

check_data_storage_filesystem_settings() {
    local data_dir

    if ! command_exists findmnt; then
        print_result "$WARN" "findmnt not found; cannot verify data storage filesystem type or mount options."
        return
    fi

    for data_dir in "${DATA_MOUNT_POINTS[@]}"; do
        if ! mountpoint -q "$data_dir"; then
            continue
        fi

        local fs_type
        local mount_options
        fs_type=$(findmnt -no FSTYPE --target "$data_dir" 2>/dev/null || true)
        mount_options=$(findmnt -no OPTIONS --target "$data_dir" 2>/dev/null || true)

        if [ "$fs_type" = "$RECOMMENDED_DATA_FS_TYPE" ]; then
            print_result "$OK" "$data_dir filesystem type: $fs_type"
        else
            print_result "$WARN" "$data_dir filesystem type should be $RECOMMENDED_DATA_FS_TYPE per LogMan.io data storage docs. Detected: ${fs_type:-unknown}"
        fi

        if echo ",$mount_options," | grep -q ",$RECOMMENDED_DATA_MOUNT_OPTION,"; then
            print_result "$OK" "$data_dir mount option includes $RECOMMENDED_DATA_MOUNT_OPTION."
        else
            print_result "$WARN" "$data_dir mount option should include $RECOMMENDED_DATA_MOUNT_OPTION for optimal performance. Detected: ${mount_options:-unknown}"
        fi
    done
}

check_mdadm_raid_status() {
    if ! command_exists findmnt; then
        print_result "$WARN" "findmnt not found; cannot map data mount points to block devices for RAID checks."
        return
    fi

    if [ -f "$MDSTAT_FILE" ]; then
        if grep -Eq '\[[U_]*_[U_]*\]' "$MDSTAT_FILE"; then
            print_result "$FAIL" "$MDSTAT_FILE indicates a degraded mdadm array."
        elif grep -qE '^md[0-9]+' "$MDSTAT_FILE"; then
            print_result "$OK" "$MDSTAT_FILE lists mdadm arrays and no degraded member marker was detected."
        else
            print_result "$WARN" "$MDSTAT_FILE exists but no mdadm arrays were detected."
        fi
    else
        print_result "$WARN" "$MDSTAT_FILE not found; cannot inspect mdadm runtime state."
    fi

    if ! command_exists "$MDADM_COMMAND"; then
        print_result "$WARN" "$MDADM_COMMAND not found; cannot inspect RAID levels/details."
        return
    fi

    local data_dir
    for data_dir in "${DATA_MOUNT_POINTS[@]}"; do
        if ! mountpoint -q "$data_dir"; then
            continue
        fi

        local source
        source=$(get_mount_source "$data_dir" || true)
        if [ -z "$source" ]; then
            print_result "$WARN" "Unable to determine block device backing $data_dir."
            continue
        fi

        if [[ "$source" != /dev/md* ]]; then
            print_result "$FAIL" "$data_dir is backed by $source, not an mdadm device (/dev/md*)."
            continue
        fi

        local detail
        detail=$("$MDADM_COMMAND" --detail "$source" 2>/dev/null || true)
        if [ -z "$detail" ]; then
            print_result "$FAIL" "Unable to read mdadm detail for $source backing $data_dir."
            continue
        fi

        local raid_level
        local raid_state
        raid_level=$(echo "$detail" | awk -F: '/Raid Level/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
        raid_state=$(echo "$detail" | awk -F: '/^[[:space:]]*State/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')

        if [ "$data_dir" = "$FAST_DATA_MOUNT" ]; then
            if array_contains "$raid_level" "${EXPECTED_FAST_RAID_LEVELS[@]}"; then
                print_result "$OK" "$data_dir uses expected mdadm RAID level: $raid_level ($source)."
            else
                print_result "$FAIL" "$data_dir should use RAID level ${EXPECTED_FAST_RAID_LEVELS[*]}. Detected: ${raid_level:-unknown} ($source)."
            fi
        elif [ "$data_dir" = "$SLOW_DATA_MOUNT" ]; then
            if array_contains "$raid_level" "${EXPECTED_SLOW_RAID_LEVELS[@]}"; then
                print_result "$OK" "$data_dir uses expected mdadm RAID level: $raid_level ($source)."
            else
                print_result "$FAIL" "$data_dir should use RAID level ${EXPECTED_SLOW_RAID_LEVELS[*]}. Detected: ${raid_level:-unknown} ($source)."
            fi
        fi

        if echo "$raid_state" | grep -Eiq 'degraded|faulty|inactive|failed'; then
            print_result "$FAIL" "$source state is problematic: ${raid_state:-unknown}"
        else
            print_result "$OK" "$source state: ${raid_state:-unknown}"
        fi
    done
}

check_fstab_mount_entry() {
    local mount_point="$1"
    local expected_fs="$2"
    local required_option="$3"

    if [ ! -f "$FSTAB_FILE" ]; then
        print_result "$FAIL" "$FSTAB_FILE is missing."
        return
    fi

    local fs_type
    local options
    fs_type=$(get_fstab_field "$mount_point" 3)
    options=$(get_fstab_field "$mount_point" 4)

    if [ -z "$fs_type" ]; then
        print_result "$FAIL" "$FSTAB_FILE does not contain a persistent entry for $mount_point."
        return
    fi

    if [ "$fs_type" = "$expected_fs" ]; then
        print_result "$OK" "$FSTAB_FILE entry for $mount_point uses filesystem $fs_type."
    else
        print_result "$FAIL" "$FSTAB_FILE entry for $mount_point should use $expected_fs. Detected: $fs_type."
    fi

    if [ -n "$required_option" ]; then
        if echo ",$options," | grep -q ",$required_option,"; then
            print_result "$OK" "$FSTAB_FILE entry for $mount_point includes $required_option."
        else
            print_result "$FAIL" "$FSTAB_FILE entry for $mount_point should include $required_option. Detected options: ${options:-unknown}"
        fi
    fi
}

check_fstab_persistence() {
    check_fstab_mount_entry "$ROOT_MOUNT" "$RECOMMENDED_DATA_FS_TYPE" ""
    check_fstab_mount_entry "$VAR_LOG_MOUNT" "$RECOMMENDED_DATA_FS_TYPE" ""
    check_fstab_mount_entry "$EXPECTED_DOCKER_ROOT_DIR" "$RECOMMENDED_DATA_FS_TYPE" "$RECOMMENDED_DATA_MOUNT_OPTION"
    check_fstab_mount_entry "$FAST_DATA_MOUNT" "$RECOMMENDED_DATA_FS_TYPE" "$RECOMMENDED_DATA_MOUNT_OPTION"
    check_fstab_mount_entry "$SLOW_DATA_MOUNT" "$RECOMMENDED_DATA_FS_TYPE" "$RECOMMENDED_DATA_MOUNT_OPTION"

    if command_exists findmnt; then
        if findmnt --verify --tab-file "$FSTAB_FILE" >/dev/null 2>&1; then
            print_result "$OK" "$FSTAB_FILE passes findmnt verification."
        else
            print_result "$WARN" "$FSTAB_FILE did not pass findmnt verification. Review syntax manually."
        fi
    else
        print_result "$WARN" "findmnt not found; cannot verify $FSTAB_FILE syntax."
    fi
}

check_swap() {
    local total_bytes
    total_bytes=$(awk '/^SwapTotal:/ {print $2 * 1024}' /proc/meminfo 2>/dev/null)
    local threshold_total_bytes=$(( MIN_SWAP_TOTAL_GB * 1024 * 1024 * 1024 ))
    local tolerance_bytes=$(( SWAP_SIZE_TOLERANCE_MB * 1024 * 1024 ))

    if [ -z "$total_bytes" ] || [ "$total_bytes" -le 0 ]; then
        print_result "$FAIL" "No swap configured. Required: at least ${MIN_SWAP_TOTAL_GB} GB total (recommended as two ${MIN_SWAP_PER_DEVICE_GB} GB partitions)."
    elif [ $((total_bytes + tolerance_bytes)) -lt "$threshold_total_bytes" ]; then
        local total_gb
        total_gb=$(awk -v b="$total_bytes" 'BEGIN{printf "%.1f", b/1024/1024/1024}')
        print_result "$FAIL" "Total swap is below required ${MIN_SWAP_TOTAL_GB} GB. Detected: ${total_gb} GB"
    else
        local total_gb
        total_gb=$(awk -v b="$total_bytes" 'BEGIN{printf "%.1f", b/1024/1024/1024}')
        print_result "$OK" "Total swap: ${total_gb} GB (meets >= ${MIN_SWAP_TOTAL_GB} GB requirement)"
    fi

    if command_exists swapon; then
        mapfile -t SWAPS < <(swapon --show --bytes 2>/dev/null | tail -n +2)
        local count=${#SWAPS[@]}

        if [ "$count" -lt "$RECOMMENDED_SWAP_DEVICES" ]; then
            print_result "$FAIL" "Recommended at least ${RECOMMENDED_SWAP_DEVICES} swap partitions (2 x ${MIN_SWAP_PER_DEVICE_GB} GB). Active swap areas: $count"
        else
            local threshold_per_bytes=$(( MIN_SWAP_PER_DEVICE_GB * 1024 * 1024 * 1024 ))
            local per_ok=true

            for entry in "${SWAPS[@]}"; do
                local dev size
                dev=$(echo "$entry" | awk '{print $1}')
                size=$(echo "$entry" | awk '{print $3}')
                if [ $((size + tolerance_bytes)) -lt "$threshold_per_bytes" ]; then
                    local size_gb
                    size_gb=$(awk -v b="$size" 'BEGIN{printf "%.1f", b/1024/1024/1024}')
                    print_result "$FAIL" "Swap device $dev is below ${MIN_SWAP_PER_DEVICE_GB} GB. Detected: ${size_gb} GB"
                    per_ok=false
                fi
            done

            if [ "$per_ok" = true ]; then
                print_result "$OK" "Detected $count swap devices; each is >= ${MIN_SWAP_PER_DEVICE_GB} GB (recommended configuration)."
            fi
        fi
    else
        print_result "$FAIL" "Cannot inspect swap devices (swapon not found)."
    fi
}

check_os() {
    local os_name os_version

    if command_exists lsb_release; then
        os_name=$(lsb_release -si 2>/dev/null || true)
        os_version=$(lsb_release -sr 2>/dev/null || true)
    elif [ -f "$OS_RELEASE_FILE" ]; then
        os_name=$(awk -F= '/^ID=/{gsub(/"/,""); print toupper(substr($2,1,1)) tolower(substr($2,2))}' "$OS_RELEASE_FILE")
        os_version=$(awk -F= '/^VERSION_ID=/{gsub(/"/,""); print $2}' "$OS_RELEASE_FILE")
    else
        os_name="Unknown"
        os_version="Unknown"
    fi

    if [ "$os_name" != "$SUPPORTED_OS_NAME" ]; then
        print_result "$FAIL" "Unsupported Operating System: $os_name. The documented LogMan.io installation path targets $SUPPORTED_OS_NAME Server."
    elif array_contains "$os_version" "${SUPPORTED_OS_VERSIONS[@]}"; then
        print_result "$OK" "Operating System: $os_name $os_version (supported)"
    elif [ -n "$COMPATIBLE_OS_VERSION_WARN" ] && [ "$os_version" = "$COMPATIBLE_OS_VERSION_WARN" ]; then
        print_result "$WARN" "Operating System: $os_name $os_version. Hardware docs mention compatibility, but the public installer path is $SUPPORTED_OS_NAME ${SUPPORTED_OS_VERSIONS[*]}."
    else
        print_result "$FAIL" "Unsupported $SUPPORTED_OS_NAME version: $os_version. Supported versions: ${SUPPORTED_OS_VERSIONS[*]}."
    fi
}

check_install_profile() {
    normalize_install_mode

    if array_contains "$INSTALL_MODE" "${SUPPORTED_INSTALL_MODES[@]}"; then
        print_result "$OK" "Install profile: $(install_mode_label) ($INSTALL_MODE)"
    else
        print_result "$FAIL" "Unsupported INSTALL_MODE=$INSTALL_MODE. Supported values: ${SUPPORTED_INSTALL_MODES[*]}"
    fi

    if array_contains "$NODE_ROLE" "${SUPPORTED_NODE_ROLES[@]}"; then
        print_result "$OK" "Node role: $NODE_ROLE"
    else
        print_result "$FAIL" "Unsupported NODE_ROLE=$NODE_ROLE. Supported values: ${SUPPORTED_NODE_ROLES[*]}"
    fi

    case "$INSTALL_MODE" in
        single)
            print_result "$WARN" "Single-node profile: cluster-only checks are skipped unless explicitly enabled."
            ;;
        cluster-first)
            print_result "$OK" "First cluster node profile: using first-node installer and enforcing cluster network prerequisites."
            ;;
        cluster-additional)
            print_result "$OK" "Second/third cluster node profile: using Governator bootstrap image and enforcing generic cluster prerequisites."
            print_result "$WARN" "Verify first cluster node reachability from the implementation plan before bootstrap."
            ;;
    esac

    if [ "$NODE_ROLE" = "arbiter" ]; then
        print_result "$WARN" "Arbiter role is adjusted after bootstrap in Zookeeper per docs; pre-install checks still validate host prerequisites."
    fi
}

check_docker() {
    if command_exists docker; then
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
        if [ -z "$docker_version" ]; then
            print_result "$FAIL" "Docker is installed but server version could not be determined."
            return
        fi
        if [ -n "$DOCKER_VERSION_WARN_FLOOR" ] && [[ $(printf '%s\n' "$DOCKER_VERSION_WARN_FLOOR" "$docker_version" | sort -V | head -n1) != "$DOCKER_VERSION_WARN_FLOOR" ]]; then
            print_result "$WARN" "Docker version is older than local compatibility baseline $DOCKER_VERSION_WARN_FLOOR. Detected: $docker_version"
        else
            print_result "$OK" "Docker version: $docker_version"
        fi
    else
        print_result "$FAIL" "Docker is not installed."
    fi
}

check_docker_compose() {
    if command_exists docker; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || true)
        if [ -n "$compose_version" ]; then
            print_result "$OK" "Docker Compose plugin version: $compose_version"
        else
            print_result "$FAIL" "Docker Compose plugin is not available. Install docker-compose-plugin from the Docker repository."
        fi
    else
        print_result "$FAIL" "Docker is not installed."
    fi
}

# Verify that Docker is running, enabled after reboot, and reachable.
check_docker_service() {
    if ! command_exists docker; then
        print_result "$FAIL" "Docker is not installed."
        return
    fi

    if command_exists systemctl; then
        if systemctl is-active --quiet "$DOCKER_SERVICE_NAME" 2>/dev/null; then
            print_result "$OK" "$DOCKER_SERVICE_NAME.service is active."
        else
            print_result "$FAIL" "$DOCKER_SERVICE_NAME.service is not active."
        fi

        if systemctl is-enabled --quiet "$DOCKER_SERVICE_NAME" 2>/dev/null; then
            print_result "$OK" "$DOCKER_SERVICE_NAME.service is enabled."
        else
            print_result "$FAIL" "$DOCKER_SERVICE_NAME.service is not enabled."
        fi

        if systemctl is-active --quiet "$CONTAINERD_SERVICE_NAME" 2>/dev/null; then
            print_result "$OK" "$CONTAINERD_SERVICE_NAME.service is active."
        else
            print_result "$WARN" "$CONTAINERD_SERVICE_NAME.service is not reported as active. Verify Docker runtime state."
        fi
    else
        print_result "$WARN" "systemctl not found; cannot verify Docker service enablement."
    fi

    if docker info >/dev/null 2>&1; then
        print_result "$OK" "Docker daemon is reachable by the current user."
    else
        print_result "$FAIL" "Docker daemon is not reachable by the current user."
    fi
}

# Docker data should live under /var/lib/docker on a sufficiently large filesystem.
check_docker_root_dir() {
    if ! command_exists docker; then
        print_result "$FAIL" "Docker is not installed."
        return
    fi

    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
    if [ -z "$docker_root" ]; then
        print_result "$FAIL" "Unable to determine Docker root directory."
        return
    fi

    if [ "$docker_root" = "$EXPECTED_DOCKER_ROOT_DIR" ]; then
        print_result "$OK" "Docker root directory: $docker_root"
    else
        print_result "$FAIL" "Docker root directory should be $EXPECTED_DOCKER_ROOT_DIR. Detected: $docker_root"
    fi

    if [ -d "$docker_root" ]; then
        local docker_root_size_kb
        local docker_root_size_h
        docker_root_size_kb=$(df "$docker_root" --output=size 2>/dev/null | tail -n 1)
        docker_root_size_h=$(df -h "$docker_root" 2>/dev/null | awk 'NR==2 {print $2}')
        if [ -n "$docker_root_size_kb" ] && [ "$docker_root_size_kb" -lt "$(gb_to_kb "$MIN_DOCKER_ROOT_GB")" ]; then
            print_result "$FAIL" "Docker root filesystem must be at least ${MIN_DOCKER_ROOT_GB}GB per LogMan.io system storage layout. Detected: $docker_root_size_h"
        elif [ -n "$docker_root_size_kb" ] && [ "$docker_root_size_kb" -lt "$(gb_to_kb "$RECOMMENDED_DOCKER_ROOT_GB")" ]; then
            print_result "$WARN" "Docker root filesystem is below recommended ${RECOMMENDED_DOCKER_ROOT_GB}GB. Detected: $docker_root_size_h"
        else
            print_result "$OK" "Docker root filesystem capacity: $docker_root_size_h"
        fi

        if mountpoint -q "$docker_root"; then
            print_result "$OK" "$docker_root is a dedicated mount point."
        else
            print_result "$WARN" "$docker_root is not a dedicated mount point. LogMan.io documentation recommends a dedicated Docker partition."
        fi
    else
        print_result "$FAIL" "Docker root directory does not exist: $docker_root"
    fi
}

# LogMan.io expects the default Docker bridge to be disabled in daemon.json.
check_docker_bridge_disabled() {
    local daemon_json="$DOCKER_DAEMON_JSON"
    local bridge_value=""

    if [ ! -f "$daemon_json" ]; then
        print_result "$FAIL" "$daemon_json is missing. LogMan.io expects Docker bridge disabled with \"bridge\": \"$EXPECTED_DOCKER_BRIDGE\"."
    else
        if command_exists jq; then
            bridge_value=$(jq -r '.bridge // empty' "$daemon_json" 2>/dev/null || true)
        elif command_exists python3; then
            bridge_value=$(python3 - "$daemon_json" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

print(data.get("bridge", ""))
PY
)
        elif grep -Eq "\"bridge\"[[:space:]]*:[[:space:]]*\"$EXPECTED_DOCKER_BRIDGE\"" "$daemon_json"; then
            bridge_value="$EXPECTED_DOCKER_BRIDGE"
        fi

        if [ "$bridge_value" = "$EXPECTED_DOCKER_BRIDGE" ]; then
            print_result "$OK" "$daemon_json disables Docker bridge networking (bridge=$EXPECTED_DOCKER_BRIDGE)."
        elif [ -n "$bridge_value" ]; then
            print_result "$FAIL" "$daemon_json should set bridge=$EXPECTED_DOCKER_BRIDGE. Detected bridge=$bridge_value"
        else
            print_result "$FAIL" "$daemon_json does not set Docker bridge to none, or the file could not be parsed."
        fi
    fi

    if command_exists ip; then
        if ip link show "$DOCKER_DEFAULT_BRIDGE_INTERFACE" >/dev/null 2>&1; then
            print_result "$FAIL" "$DOCKER_DEFAULT_BRIDGE_INTERFACE network interface exists. Restart Docker after disabling the default bridge."
        else
            print_result "$OK" "$DOCKER_DEFAULT_BRIDGE_INTERFACE network interface is not present."
        fi
    else
        print_result "$WARN" "ip command not found; cannot verify whether $DOCKER_DEFAULT_BRIDGE_INTERFACE exists."
    fi
}

check_docker_apt_repository() {
    if [ -f "$DOCKER_APT_KEYRING" ]; then
        print_result "$OK" "Docker apt keyring exists: $DOCKER_APT_KEYRING"
    else
        print_result "$FAIL" "Docker apt keyring is missing: $DOCKER_APT_KEYRING"
    fi

    if [ -f "$DOCKER_APT_SOURCE_FILE" ]; then
        if grep -q "$DOCKER_APT_SOURCE_DOMAIN" "$DOCKER_APT_SOURCE_FILE"; then
            print_result "$OK" "Docker apt source points to $DOCKER_APT_SOURCE_DOMAIN."
        else
            print_result "$FAIL" "Docker apt source does not reference $DOCKER_APT_SOURCE_DOMAIN: $DOCKER_APT_SOURCE_FILE"
        fi
    else
        print_result "$FAIL" "Docker apt source file is missing: $DOCKER_APT_SOURCE_FILE"
    fi

    if command_exists "$APT_CACHE_COMMAND"; then
        local candidate
        candidate=$("$APT_CACHE_COMMAND" policy docker-ce 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)
        if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
            print_result "$OK" "docker-ce apt candidate is available: $candidate"
        else
            print_result "$WARN" "docker-ce apt candidate is not available. Run apt update or review Docker apt source."
        fi
    else
        print_result "$WARN" "$APT_CACHE_COMMAND not found; cannot verify Docker apt candidates."
    fi
}

check_docker_packages() {
    if ! command_exists "$DPKG_COMMAND"; then
        print_result "$WARN" "$DPKG_COMMAND not found; cannot verify Docker package installation."
        return
    fi

    local package
    for package in "${REQUIRED_DOCKER_PACKAGES[@]}"; do
        if "$DPKG_COMMAND" -s "$package" >/dev/null 2>&1; then
            local version
            version=$("$DPKG_COMMAND" -s "$package" 2>/dev/null | awk -F': ' '/^Version:/ {print $2; exit}' || true)
            print_result "$OK" "Docker package installed: $package ${version:-unknown-version}"
        else
            print_result "$FAIL" "Required Docker package is not installed: $package"
        fi
    done
}

wireguard_checks_enabled() {
    case "$ENABLE_WIREGUARD_CHECKS" in
        true|yes|1)
            return 0
            ;;
        false|no|0)
            return 1
            ;;
        auto|"")
            is_cluster_mode
            return
            ;;
        *)
            is_cluster_mode
            return
            ;;
    esac
}

check_wireguard_preinstall() {
    if ! wireguard_checks_enabled; then
        print_result "$WARN" "WireGuard checks skipped for $(install_mode_label); cluster networking is not enforced for this profile."
        print_result "$WARN" "Set INSTALL_MODE=cluster-first, INSTALL_MODE=cluster-additional, or ENABLE_WIREGUARD_CHECKS=true to enforce WireGuard checks."
        return
    fi

    if command_exists "$WIREGUARD_COMMAND"; then
        print_result "$OK" "$WIREGUARD_COMMAND command is installed."
    else
        print_result "$FAIL" "$WIREGUARD_COMMAND command is missing."
    fi

    if command_exists "$WIREGUARD_QUICK_COMMAND"; then
        print_result "$OK" "$WIREGUARD_QUICK_COMMAND command is installed."
    else
        print_result "$FAIL" "$WIREGUARD_QUICK_COMMAND command is missing."
    fi

    if [ -f "$WIREGUARD_CONFIG_FILE" ]; then
        print_result "$OK" "WireGuard config exists: $WIREGUARD_CONFIG_FILE"
    else
        print_result "$FAIL" "WireGuard config is missing: $WIREGUARD_CONFIG_FILE"
        return
    fi

    if command_exists ip; then
        if ip link show "$WIREGUARD_INTERFACE" >/dev/null 2>&1; then
            print_result "$OK" "WireGuard interface exists: $WIREGUARD_INTERFACE"
        else
            print_result "$FAIL" "WireGuard interface is missing: $WIREGUARD_INTERFACE"
        fi
    else
        print_result "$WARN" "ip command not found; cannot verify WireGuard interface."
    fi

    if command_exists systemctl; then
        if systemctl is-enabled --quiet "$WIREGUARD_SERVICE_NAME" 2>/dev/null; then
            print_result "$OK" "$WIREGUARD_SERVICE_NAME is enabled."
        else
            print_result "$FAIL" "$WIREGUARD_SERVICE_NAME is not enabled."
        fi
    else
        print_result "$WARN" "systemctl not found; cannot verify $WIREGUARD_SERVICE_NAME."
    fi

    local listen_port
    local mtu
    local address
    local peer_count

    listen_port=$(get_wireguard_config_value "Interface" "ListenPort")
    mtu=$(get_wireguard_config_value "Interface" "MTU")
    address=$(get_wireguard_config_value "Interface" "Address")
    peer_count=$(wireguard_peer_count)

    if [ "$listen_port" = "$WIREGUARD_LISTEN_PORT" ]; then
        print_result "$OK" "WireGuard ListenPort: $listen_port"
    else
        print_result "$FAIL" "WireGuard ListenPort should be $WIREGUARD_LISTEN_PORT. Detected: ${listen_port:-missing}"
    fi

    if [ "$mtu" = "$WIREGUARD_MTU" ]; then
        print_result "$OK" "WireGuard MTU: $mtu"
    else
        print_result "$FAIL" "WireGuard MTU should be $WIREGUARD_MTU. Detected: ${mtu:-missing}"
    fi

    if [ -n "$address" ]; then
        print_result "$OK" "WireGuard Address is configured: $address"
    else
        print_result "$FAIL" "WireGuard Address is missing in the Interface section."
    fi

    if [ "$peer_count" -gt 0 ]; then
        print_result "$OK" "WireGuard peer entries are present: $peer_count"
    else
        print_result "$FAIL" "WireGuard config does not contain any [Peer] entries."
    fi

    if is_cluster_mode && [ "$peer_count" -lt 2 ]; then
        print_result "$WARN" "Cluster WireGuard config usually lists all cluster peers; detected only $peer_count [Peer] section(s)."
    fi

    if grep -Eq '^[[:space:]]*AllowedIPs[[:space:]]*=' "$WIREGUARD_CONFIG_FILE"; then
        print_result "$OK" "WireGuard peer AllowedIPs entries are present."
    else
        print_result "$FAIL" "WireGuard config does not contain any peer AllowedIPs entries."
    fi

    if grep -Eq "^[[:space:]]*Endpoint[[:space:]]*=.*:${WIREGUARD_LISTEN_PORT}[[:space:]]*$" "$WIREGUARD_CONFIG_FILE"; then
        print_result "$OK" "WireGuard peer endpoint uses port $WIREGUARD_LISTEN_PORT."
    else
        print_result "$WARN" "No WireGuard peer Endpoint with port $WIREGUARD_LISTEN_PORT was detected."
    fi

    if grep -Eq "^[[:space:]]*PersistentKeepalive[[:space:]]*=[[:space:]]*${WIREGUARD_PERSISTENT_KEEPALIVE}[[:space:]]*$" "$WIREGUARD_CONFIG_FILE"; then
        print_result "$OK" "WireGuard PersistentKeepalive is $WIREGUARD_PERSISTENT_KEEPALIVE."
    else
        print_result "$WARN" "WireGuard PersistentKeepalive should be $WIREGUARD_PERSISTENT_KEEPALIVE for NAT traversal."
    fi
}

check_git() {
    if command_exists git; then
        print_result "$OK" "Git is installed"
    else
        print_result "$FAIL" "Git is not installed. Please install Git."
    fi
}

# Check live kernel values currently applied to the running host.
check_kernel_params() {
    vm_max_map_count=$(get_sysctl_value vm.max_map_count)
    net_unprivileged_port=$(get_sysctl_value net.ipv4.ip_unprivileged_port_start)
    inotify_max_user_instances=$(get_sysctl_value fs.inotify.max_user_instances)
    inotify_max_user_watches=$(get_sysctl_value fs.inotify.max_user_watches)
    inotify_max_queued_events=$(get_sysctl_value fs.inotify.max_queued_events)

    if [ -z "$vm_max_map_count" ]; then
        print_result "$FAIL" "Unable to read vm.max_map_count"
    elif [ "$vm_max_map_count" -lt "$REQUIRED_VM_MAX_MAP_COUNT" ]; then
        print_result "$FAIL" "vm.max_map_count must be at least $REQUIRED_VM_MAX_MAP_COUNT. Detected: $vm_max_map_count"
    else
        print_result "$OK" "vm.max_map_count: $vm_max_map_count"
    fi

    if [ -z "$net_unprivileged_port" ]; then
        print_result "$FAIL" "Unable to read net.ipv4.ip_unprivileged_port_start"
    elif [ "$net_unprivileged_port" -gt "$REQUIRED_UNPRIVILEGED_PORT_START" ]; then
        print_result "$FAIL" "net.ipv4.ip_unprivileged_port_start must be $REQUIRED_UNPRIVILEGED_PORT_START or lower. Detected: $net_unprivileged_port"
    else
        print_result "$OK" "net.ipv4.ip_unprivileged_port_start: $net_unprivileged_port"
    fi

    if [ -z "$inotify_max_user_instances" ]; then
        print_result "$FAIL" "Unable to read fs.inotify.max_user_instances"
    elif [ "$inotify_max_user_instances" -lt "$REQUIRED_INOTIFY_MAX_USER_INSTANCES" ]; then
        print_result "$FAIL" "fs.inotify.max_user_instances must be at least $REQUIRED_INOTIFY_MAX_USER_INSTANCES. Detected: $inotify_max_user_instances"
    else
        print_result "$OK" "fs.inotify.max_user_instances: $inotify_max_user_instances"
    fi

    if [ -z "$inotify_max_user_watches" ]; then
        print_result "$FAIL" "Unable to read fs.inotify.max_user_watches"
    elif [ "$inotify_max_user_watches" -lt "$REQUIRED_INOTIFY_MAX_USER_WATCHES" ]; then
        print_result "$FAIL" "fs.inotify.max_user_watches must be at least $REQUIRED_INOTIFY_MAX_USER_WATCHES. Detected: $inotify_max_user_watches"
    else
        print_result "$OK" "fs.inotify.max_user_watches: $inotify_max_user_watches"
    fi

    if [ -z "$inotify_max_queued_events" ]; then
        print_result "$FAIL" "Unable to read fs.inotify.max_queued_events"
    elif [ "$inotify_max_queued_events" -lt "$REQUIRED_INOTIFY_MAX_QUEUED_EVENTS" ]; then
        print_result "$FAIL" "fs.inotify.max_queued_events must be at least $REQUIRED_INOTIFY_MAX_QUEUED_EVENTS. Detected: $inotify_max_queued_events"
    else
        print_result "$OK" "fs.inotify.max_queued_events: $inotify_max_queued_events"
    fi
}

# Check persistent sysctl config so required values survive reboot.
check_persistent_kernel_params() {
    if [ ! -f "$SYSCTL_CONF_FILE" ]; then
        print_result "$FAIL" "$SYSCTL_CONF_FILE is missing. Live sysctl values may not survive reboot."
        return
    fi

    check_sysctl_conf_min vm.max_map_count "$REQUIRED_VM_MAX_MAP_COUNT"
    check_sysctl_conf_max net.ipv4.ip_unprivileged_port_start "$REQUIRED_UNPRIVILEGED_PORT_START"
    check_sysctl_conf_min fs.inotify.max_user_instances "$REQUIRED_INOTIFY_MAX_USER_INSTANCES"
    check_sysctl_conf_min fs.inotify.max_user_watches "$REQUIRED_INOTIFY_MAX_USER_WATCHES"
    check_sysctl_conf_min fs.inotify.max_queued_events "$REQUIRED_INOTIFY_MAX_QUEUED_EVENTS"
}

# Validate the deployment/admin user expected by the LogMan.io procedure.
check_deployment_user() {
    if id "$DEPLOYMENT_USER" &>/dev/null; then
        print_result "$OK" "User '$DEPLOYMENT_USER' exists"
    else
        print_result "$FAIL" "User '$DEPLOYMENT_USER' does not exist. Please create the '$DEPLOYMENT_USER' user."
        return
    fi

    local groups
    groups=$(id -nG "$DEPLOYMENT_USER" 2>/dev/null || true)
    if echo " $groups " | grep -qw "$REQUIRED_DOCKER_GROUP"; then
        print_result "$OK" "User '$DEPLOYMENT_USER' is a member of the $REQUIRED_DOCKER_GROUP group."
    else
        print_result "$FAIL" "User '$DEPLOYMENT_USER' must be a member of the $REQUIRED_DOCKER_GROUP group."
    fi

    if user_groups_contain_any "$groups" "${REQUIRED_ADMIN_GROUPS[@]}"; then
        print_result "$OK" "User '$DEPLOYMENT_USER' is a member of an admin group (${REQUIRED_ADMIN_GROUPS[*]})."
    else
        print_result "$FAIL" "User '$DEPLOYMENT_USER' should be a member of one admin group: ${REQUIRED_ADMIN_GROUPS[*]}"
    fi

    local home_dir
    local login_shell
    home_dir=$(get_passwd_field "$DEPLOYMENT_USER" 6)
    login_shell=$(get_passwd_field "$DEPLOYMENT_USER" 7)

    if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
        print_result "$OK" "User '$DEPLOYMENT_USER' home directory exists: $home_dir"
    else
        print_result "$FAIL" "User '$DEPLOYMENT_USER' home directory is missing or not a directory: ${home_dir:-unknown}"
    fi

    if echo "$login_shell" | grep -Eq "$NON_LOGIN_SHELL_REGEX"; then
        print_result "$FAIL" "User '$DEPLOYMENT_USER' has a non-login shell: $login_shell"
    elif [ -n "$login_shell" ]; then
        print_result "$OK" "User '$DEPLOYMENT_USER' login shell: $login_shell"
    else
        print_result "$FAIL" "Unable to determine login shell for user '$DEPLOYMENT_USER'."
    fi

    local ssh_dir="$home_dir/$SSH_DIR_NAME"
    local authorized_keys="$ssh_dir/$AUTHORIZED_KEYS_FILE"

    if [ -n "$home_dir" ] && [ -d "$ssh_dir" ]; then
        local ssh_mode
        ssh_mode=$(get_file_mode "$ssh_dir")
        if [ "$ssh_mode" = "$REQUIRED_SSH_DIR_MODE" ]; then
            print_result "$OK" "$ssh_dir permissions: $ssh_mode"
        else
            print_result "$FAIL" "$ssh_dir permissions should be $REQUIRED_SSH_DIR_MODE. Detected: ${ssh_mode:-unknown}"
        fi
    else
        print_result "$FAIL" "SSH directory for '$DEPLOYMENT_USER' is missing: ${ssh_dir:-unknown}"
    fi

    if [ -n "$home_dir" ] && [ -s "$authorized_keys" ]; then
        local authorized_keys_mode
        authorized_keys_mode=$(get_file_mode "$authorized_keys")
        if [ "$authorized_keys_mode" = "$REQUIRED_AUTHORIZED_KEYS_MODE" ]; then
            print_result "$OK" "$authorized_keys exists and permissions are $REQUIRED_AUTHORIZED_KEYS_MODE."
        else
            print_result "$FAIL" "$authorized_keys permissions should be $REQUIRED_AUTHORIZED_KEYS_MODE. Detected: ${authorized_keys_mode:-unknown}"
        fi
    else
        print_result "$FAIL" "SSH $AUTHORIZED_KEYS_FILE for '$DEPLOYMENT_USER' is missing or empty."
    fi
}

# Docker group membership alone is not enough; verify daemon access when possible.
check_deployment_user_docker_access() {
    if ! id "$DEPLOYMENT_USER" &>/dev/null; then
        print_result "$FAIL" "Cannot verify Docker access for '$DEPLOYMENT_USER' because the user does not exist."
        return
    fi

    if ! command_exists docker; then
        print_result "$FAIL" "Cannot verify Docker access for '$DEPLOYMENT_USER' because Docker is not installed."
        return
    fi

    if [ "$(id -un 2>/dev/null)" = "$DEPLOYMENT_USER" ]; then
        if docker info >/dev/null 2>&1; then
            print_result "$OK" "User '$DEPLOYMENT_USER' can access the Docker daemon."
        else
            print_result "$FAIL" "User '$DEPLOYMENT_USER' cannot access the Docker daemon."
        fi
    elif [ "$(id -u)" -eq 0 ] && command_exists "$SUDO_COMMAND"; then
        if "$SUDO_COMMAND" -n -u "$DEPLOYMENT_USER" docker info >/dev/null 2>&1; then
            print_result "$OK" "User '$DEPLOYMENT_USER' can access the Docker daemon."
        else
            print_result "$FAIL" "User '$DEPLOYMENT_USER' cannot access the Docker daemon."
        fi
    else
        print_result "$WARN" "Run as root or $DEPLOYMENT_USER to verify $DEPLOYMENT_USER Docker daemon access directly."
    fi
}

check_ssh_hardening() {
    if [ -f "$SSHD_CONFIG_FILE" ]; then
        print_result "$OK" "SSH daemon config exists: $SSHD_CONFIG_FILE"
    else
        print_result "$FAIL" "SSH daemon config is missing: $SSHD_CONFIG_FILE"
    fi

    local dropin
    for dropin in "${DISALLOWED_SSHD_DROPINS[@]}"; do
        if [ -e "$dropin" ]; then
            print_result "$FAIL" "Disallowed SSH drop-in still exists: $dropin"
        else
            print_result "$OK" "Disallowed SSH drop-in is absent: $dropin"
        fi
    done

    if ssh_host_keys_available; then
        print_result "$OK" "SSH host keys are available ($SSH_HOST_KEY_GLOB)."
    else
        print_result "$FAIL" "SSH host keys are missing ($SSH_HOST_KEY_GLOB). Generate them with: sudo ssh-keygen -A"
    fi

    if ! command_exists "$SSHD_COMMAND"; then
        print_result "$WARN" "$SSHD_COMMAND not found; cannot inspect effective SSH daemon settings."
        return
    fi

    local sshd_test_output
    if sshd_test_output=$(run_privileged_command "$SSHD_COMMAND" -t -f "$SSHD_CONFIG_FILE" 2>&1); then
        print_result "$OK" "SSH daemon configuration syntax is valid."
    elif echo "$sshd_test_output" | grep -qi "no hostkeys available"; then
        print_result "$FAIL" "SSH daemon syntax/effective config check cannot access host keys. Run as root/sudo, or generate keys with: sudo ssh-keygen -A"
    else
        print_result "$FAIL" "SSH daemon configuration syntax check failed: $(echo "$sshd_test_output" | head -n 1)"
    fi

    local effective_config
    local effective_config_output
    local effective_config_error
    if effective_config_output=$(run_privileged_command "$SSHD_COMMAND" -T -f "$SSHD_CONFIG_FILE" 2>&1); then
        effective_config="$effective_config_output"
        effective_config_error=""
    else
        effective_config=""
        effective_config_error="$effective_config_output"
    fi
    if [ -z "$effective_config" ]; then
        if echo "$effective_config_error" | grep -qi "no hostkeys available"; then
            print_result "$WARN" "Unable to read effective SSH daemon settings via $SSHD_COMMAND -T because host keys are missing or not readable by this user."
        else
            print_result "$WARN" "Unable to read effective SSH daemon settings via $SSHD_COMMAND -T: ${effective_config_error:-unknown error}"
        fi
        return
    fi

    local setting
    for setting in "${REQUIRED_SSHD_SETTINGS[@]}"; do
        local key expected actual
        key=${setting%%=*}
        expected=${setting#*=}
        actual=$(echo "$effective_config" | awk -v key="$key" '$1 == key {print $2; exit}')

        if [ "$actual" = "$expected" ]; then
            print_result "$OK" "SSH setting $key=$actual"
        else
            print_result "$FAIL" "SSH setting $key should be $expected. Detected: ${actual:-unknown}"
        fi
    done
}

check_general_internet() {
    if command_exists curl; then
        code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" "$CONNECTIVITY_TEST_URL" || echo "000")
        if [ "$code" != "000" ]; then
            print_result "$OK" "Outbound HTTPS connectivity is available ($CONNECTIVITY_TEST_URL)."
        else
            print_result "$WARN" "Generic outbound HTTPS check failed. Review the specific LogMan.io endpoint checks below."
        fi
    else
        print_result "$FAIL" "curl not found; Docker installation steps require curl."
    fi
}

# Verify DNS and TCP/HTTP(S) access to registries/repositories needed during deploy.
check_domain_endpoint() {
    local domain="$1"
    local port="$2"
    local scheme="$3"

    echo "--------------------------------------"
    echo "Checking endpoint: $domain:$port"

    if ! getent hosts "$domain" > /dev/null; then
        print_result "$FAIL" "DNS resolution failed for $domain"
        return
    fi

    if ! (echo > "/dev/tcp/$domain/$port") 2>/dev/null; then
        print_result "$FAIL" "TCP connection to $domain:$port failed. Check firewall/DNS."
        return
    fi

    if command_exists curl && [ -n "$scheme" ]; then
        local status_code
        status_code=$(curl -sS -L --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" -o /dev/null -w "%{http_code}" "${scheme}://${domain}" || echo "000")
        if [[ "$status_code" == "000" ]]; then
            print_result "$FAIL" "${scheme^^} access to $domain:$port is unreachable (no valid HTTP response)."
        else
            print_result "$OK" "${scheme^^} access to $domain:$port is reachable."
        fi
    else
        print_result "$OK" "TCP access to $domain:$port is reachable."
    fi
}

check_specific_domains() {
    local domain
    for domain in "${REQUIRED_HTTPS_DOMAINS[@]}"; do
        check_domain_endpoint "$domain" "$HTTPS_PORT" "https"
    done

    for domain in "${OS_UPDATE_DOMAINS[@]}"; do
        check_domain_endpoint "$domain" "$HTTPS_PORT" "https"
        check_domain_endpoint "$domain" "$HTTP_PORT" "http"
    done

    echo "--------------------------------------"
}

check_port_conflicts() {
    if ! command_exists ss; then
        print_result "$WARN" "ss command not found; cannot inspect listening TCP ports."
        return
    fi

    local port
    for port in "${PORT_CONFLICT_TCP_PORTS[@]}"; do
        local listeners
        listeners=$(ss -H -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ ":" port "$" {print}' || true)
        if [ -n "$listeners" ]; then
            local first_listener
            first_listener=$(echo "$listeners" | head -n 1 | normalize_ss_output)
            print_result "$FAIL" "TCP port $port is already listening; potential LogMan.io pre-install conflict: $first_listener"
        else
            print_result "$OK" "TCP port $port is free."
        fi
    done
}

check_secondary_bootstrap_image_availability() {
    if ! command_exists docker; then
        print_result "$FAIL" "docker not found; second/third cluster node bootstrap requires Docker."
        return
    fi

    if docker manifest inspect "$SECONDARY_BOOTSTRAP_IMAGE" >/dev/null 2>&1; then
        print_result "$OK" "Secondary cluster bootstrap image is reachable: $SECONDARY_BOOTSTRAP_IMAGE"
    else
        print_result "$WARN" "Unable to verify bootstrap image $SECONDARY_BOOTSTRAP_IMAGE; registry credentials or network access may be required."
    fi
}

check_install_script_availability() {
    if is_cluster_additional_mode; then
        check_secondary_bootstrap_image_availability
        return
    fi

    if ! command_exists curl; then
        print_result "$FAIL" "curl not found; cannot verify LogMan.io installation script availability."
        return
    fi

    local url
    for url in "${INSTALL_SCRIPT_URLS[@]}"; do
        local status_code
        status_code=$(curl -sS -L --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" -o /dev/null -w "%{http_code}" "$url" || echo "000")

        if [[ "$status_code" =~ ^[23] ]]; then
            print_result "$OK" "Install script is reachable: $url (HTTP $status_code)"
        else
            print_result "$FAIL" "Install script is not reachable: $url (HTTP ${status_code:-000})"
        fi
    done
}

# Execution plan
#
# Keep this section declarative: each block prints one visible table section and
# then calls the checks that belong to that operational area.

prompt_install_mode
print_header

# Host sizing and base partitions.
print_section_header "Hardware Checks"
check_cpu_cores
check_ram
check_root_partition
check_var_log_partition

# LogMan.io data mount points and clean pre-install directories.
print_section_header "Storage and Install Path Checks"
check_slow_data_storage
check_fast_data_storage
check_installation_directories
check_data_storage_filesystem_settings

# mdadm state and persistent mount configuration.
print_section_header "RAID and Fstab Checks"
check_mdadm_raid_status
check_fstab_persistence

# OS, time settings, and basic connectivity.
print_section_header "Install Profile Checks"
check_install_profile

# OS, time settings, Netplan, hostname, and DNS/NTP readiness.
print_section_header "System Checks"
check_os
check_timezone
check_time_synchronization
check_network
check_netplan_configuration
check_hostname_resolvability
check_dns_ntp_health

# External endpoints required to fetch images, packages, and web assets.
print_section_header "Network Checks"
check_general_internet
check_specific_domains
check_install_script_availability

# Pre-install conflict detection for ports used by LogMan.io services.
print_section_header "Port Conflict Checks"
check_port_conflicts

# Swap layout recommended by the LogMan.io deployment guide.
print_section_header "Swap Checks"
check_swap

# Docker runtime, Compose plugin, storage location, and bridge setting.
print_section_header "Docker Checks"
check_docker
check_docker_compose
check_docker_service
check_docker_root_dir
check_docker_bridge_disabled
check_docker_apt_repository
check_docker_packages

# WireGuard is pre-install cluster networking; exact peer addressing comes from the implementation plan.
print_section_header "Cluster Network Checks"
check_wireguard_preinstall

# External tools required during installation and troubleshooting.
print_section_header "Required Tool Checks"
check_git

# Live and persistent kernel tuning required by LogMan.io components.
print_section_header "Kernel Parameter Checks"
check_kernel_params
check_persistent_kernel_params

# Deployment user, SSH readiness, admin/docker group membership, and Docker access.
print_section_header "Deployment User Checks"
check_deployment_user
check_deployment_user_docker_access

# SSH daemon hardening required by the OS-to-Docker guide.
print_section_header "SSH Configuration Checks"
check_ssh_hardening

# Final message
printf "\n${BLUE}Check completed. Review the above results for any issues that need addressing.${RESET}\n"
