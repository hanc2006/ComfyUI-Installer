#!/usr/bin/env bash
set -Eeuo pipefail

workspace="/workspace"
state_dir="$workspace/.filebrowser"
credentials="$workspace/filebrowser-credentials.txt"
binary="$state_dir/filebrowser"
database="$state_dir/filebrowser.db"
version="2.63.23"

for command in curl tar sha256sum python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf '[!] %s is required.\n' "$command" >&2
        exit 1
    fi
done

case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
        printf '[!] Unsupported architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

umask 077
if ! command -v flock >/dev/null 2>&1; then
    printf '[!] flock is required.\n' >&2
    exit 1
fi
mkdir -p "$state_dir"
exec 9>"$state_dir/setup.lock"
flock 9
chmod 700 "$state_dir"

if [ -e "$database" ] || [ -L "$database" ] || [ -e "$credentials" ] || [ -L "$credentials" ] \
    || [ -e "$binary" ] || [ -L "$binary" ]; then
    printf '[!] File Browser files already exist. Refusing to replace them.\n' >&2
    printf '[!] Existing database: %s; credentials: %s\n' "$database" "$credentials" >&2
    exit 1
fi

temp_dir="$(mktemp -d "$state_dir/setup.XXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT

archive="linux-$arch-filebrowser.tar.gz"
checksums="filebrowser_${version}_checksums.txt"
release_url="https://github.com/filebrowser/filebrowser/releases/download/v${version}"
curl -fsSL "$release_url/$archive" -o "$temp_dir/$archive"
curl -fsSL "$release_url/$checksums" -o "$temp_dir/$checksums"
if ! (
    cd "$temp_dir"
    grep -F "  $archive" "$checksums" | sha256sum --check --status
); then
    printf '[!] File Browser archive checksum verification failed.\n' >&2
    exit 1
fi
tar -xzf "$temp_dir/$archive" -C "$temp_dir" filebrowser
chmod 700 "$temp_dir/filebrowser"

password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
"$temp_dir/filebrowser" -d "$temp_dir/filebrowser.db" config init \
    --root "$workspace" --address 127.0.0.1 --port 8080 --disableExec
"$temp_dir/filebrowser" -d "$temp_dir/filebrowser.db" users add admin "$password" --perm.admin
printf 'admin:%s\n' "$password" > "$temp_dir/credentials"

mv -- "$temp_dir/filebrowser" "$binary"
mv -- "$temp_dir/filebrowser.db" "$database"
mv -- "$temp_dir/credentials" "$credentials"
chmod 600 "$database" "$credentials"

printf '\nFile Browser credentials (also saved in %s):\n' "$credentials"
cat "$credentials"
printf 'Start File Browser: %s -d %s\n' "$binary" "$database"
printf 'File Browser listens on 127.0.0.1:8080 and serves %s.\n' "$workspace"
printf 'Do not expose it directly to the internet; use an authenticated TLS proxy.\n'
