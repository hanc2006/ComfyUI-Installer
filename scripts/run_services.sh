#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

STATE_DIR="$INSTALL_DIR/.run_services"
COMFY_EXEC="$VENV_DIR/bin/comfy"
FILEBROWSER_DATA_HOME="${XDG_DATA_HOME:-${HOME:?HOME must be set}/.local/share}"
FILEBROWSER_DIR="$FILEBROWSER_DATA_HOME/filebrowser"
FILEBROWSER_EXEC="$FILEBROWSER_DIR/filebrowser"
FILEBROWSER_DB="$FILEBROWSER_DIR/filebrowser.db"

usage() {
    printf 'Usage: %s [comfyui|filebrowser]\n' "${0##*/}" >&2
    exit 2
}

if [ "$#" -gt 1 ]; then
    usage
fi

if [ "$#" -eq 1 ]; then
    case "$1" in
        comfyui|filebrowser) ;;
        *) usage ;;
    esac
fi

umask 077
mkdir -p "$STATE_DIR"
for command in flock setsid; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf '[!] %s is required.\n' "$command" >&2
        exit 1
    fi
done
exec 9>"$STATE_DIR/lock"
flock 9

command_line_contains() {
    local pid="$1"
    local executable="$2"
    local argument

    [ -r "/proc/$pid/cmdline" ] || return 1
    while IFS= read -r -d '' argument; do
        if [ "$argument" = "$executable" ]; then
            return 0
        fi
    done < "/proc/$pid/cmdline"
    return 1
}

find_service_pids() {
    local executable="$1"
    local cmdline pid

    for cmdline in /proc/[0-9]*/cmdline; do
        [ -r "$cmdline" ] || continue
        pid="${cmdline#/proc/}"
        pid="${pid%/cmdline}"
        if command_line_contains "$pid" "$executable"; then
            printf '%s\n' "$pid"
        fi
    done
}

get_executable() {
    case "$1" in
        comfyui) printf '%s\n' "$COMFY_EXEC" ;;
        filebrowser) printf '%s\n' "$FILEBROWSER_EXEC" ;;
    esac
}

service_log() {
    printf '%s/%s.log\n' "$STATE_DIR" "$1"
}

start_comfyui() {
    local log pid

    if [ ! -x "$COMFY_EXEC" ]; then
        printf '[!] ComfyUI is not installed. Run %s/install.sh first.\n' "$INSTALL_DIR" >&2
        return 1
    fi
    if [ ! -d "$COMFYUI_DIR" ]; then
        printf '[!] ComfyUI workspace not found at %s. Run %s/install.sh first.\n' "$COMFYUI_DIR" "$INSTALL_DIR" >&2
        return 1
    fi

    local launch_args=(--listen 127.0.0.1 --port "$COMFYUI_PORT" --preview-method auto)
    case "$SAGE_ATTENTION" in
        true) launch_args+=(--use-sage-attention) ;;
        false) ;;
        *)
            printf '[!] SAGE_ATTENTION must be true or false (got: %s).\n' "$SAGE_ATTENTION" >&2
            return 1
            ;;
    esac

    log="$(service_log comfyui)"
    (
        cd "$COMFYUI_DIR"
        nohup setsid "$COMFY_EXEC" --workspace="$COMFYUI_DIR" launch -- "${launch_args[@]}" \
            9>&- >>"$log" 2>&1 </dev/null &
        printf '%s\n' "$!" > "$STATE_DIR/comfyui.pid"
    )
    pid="$(<"$STATE_DIR/comfyui.pid")"
    sleep 1
    if ! command_line_contains "$pid" "$COMFY_EXEC"; then
        printf '[!] ComfyUI exited while starting. Check %s.\n' "$log" >&2
        return 1
    fi
    printf '[+] ComfyUI started (pid %s).\n' "$pid"
}

start_filebrowser() {
    local log pid

    if [ ! -x "$FILEBROWSER_EXEC" ]; then
        printf '[!] File Browser is not installed. Run %s/scripts/install_filebrowser.sh first.\n' "$INSTALL_DIR" >&2
        return 1
    fi
    if [ ! -f "$FILEBROWSER_DB" ]; then
        printf '[!] File Browser database not found at %s. Run %s/scripts/install_filebrowser.sh first.\n' "$FILEBROWSER_DB" "$INSTALL_DIR" >&2
        return 1
    fi

    log="$(service_log filebrowser)"
    nohup setsid "$FILEBROWSER_EXEC" -d "$FILEBROWSER_DB" 9>&- >>"$log" 2>&1 </dev/null &
    printf '%s\n' "$!" > "$STATE_DIR/filebrowser.pid"
    pid="$(<"$STATE_DIR/filebrowser.pid")"
    sleep 1
    if ! command_line_contains "$pid" "$FILEBROWSER_EXEC"; then
        printf '[!] File Browser exited while starting. Check %s.\n' "$log" >&2
        return 1
    fi
    printf '[+] File Browser started (pid %s).\n' "$pid"
}

start_service() {
    case "$1" in
        comfyui) start_comfyui ;;
        filebrowser) start_filebrowser ;;
    esac
}

stop_service() {
    local service="$1"
    local executable pid remaining attempt tracked_pid=""
    local -a pids=()

    executable="$(get_executable "$service")"
    mapfile -t pids < <(find_service_pids "$executable")
    if [ "${#pids[@]}" -eq 0 ]; then
        printf '[*] %s is not running.\n' "$service"
        return 0
    fi

    if [ -r "$STATE_DIR/$service.pid" ]; then
        if ! read -r tracked_pid < "$STATE_DIR/$service.pid" \
            || [[ ! "$tracked_pid" =~ ^[0-9]+$ ]] \
            || ! command_line_contains "$tracked_pid" "$executable"; then
            tracked_pid=""
        fi
    fi
    if [ -n "$tracked_pid" ]; then
        kill -- "-$tracked_pid" 2>/dev/null || true
    fi
    for pid in "${pids[@]}"; do
        [ "$pid" = "$tracked_pid" ] && continue
        kill "$pid" 2>/dev/null || true
    done
    for ((attempt = 0; attempt < 10; attempt++)); do
        remaining=0
        for pid in "${pids[@]}"; do
            if command_line_contains "$pid" "$executable"; then
                remaining=1
                break
            fi
        done
        [ "$remaining" -eq 0 ] && break
        sleep 1
    done
    if [ "$remaining" -ne 0 ]; then
        if [ -n "$tracked_pid" ] && command_line_contains "$tracked_pid" "$executable"; then
            kill -KILL -- "-$tracked_pid" 2>/dev/null || true
        fi
        for pid in "${pids[@]}"; do
            if [ "$pid" != "$tracked_pid" ] && command_line_contains "$pid" "$executable"; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    rm -f -- "$STATE_DIR/$service.pid"
    printf '[*] Stopped %s.\n' "$service"
}

service_status() {
    local service="$1"
    local executable
    local -a pids=()

    executable="$(get_executable "$service")"
    mapfile -t pids < <(find_service_pids "$executable")
    if [ "${#pids[@]}" -gt 0 ]; then
        printf '[*] %s: in process (pid %s).\n' "$service" "${pids[0]}"
        return 0
    fi
    printf '[*] %s: not running (died or not started).\n' "$service"
    return 1
}

if [ "$#" -eq 1 ]; then
    service_status "$1" || true
    stop_service "$1"
    start_service "$1"
    exit
fi

comfyui_running=0
filebrowser_running=0
service_status comfyui || comfyui_running=1
service_status filebrowser || filebrowser_running=1

start_failed=0
if [ "$comfyui_running" -eq 1 ]; then
    start_comfyui || start_failed=1
fi
if [ "$filebrowser_running" -eq 1 ]; then
    start_filebrowser || start_failed=1
fi
exit "$start_failed"
