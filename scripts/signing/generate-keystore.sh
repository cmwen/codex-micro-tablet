#!/usr/bin/env bash
# Generate a private key interactively; never export passwords or upload credentials.
set -euo pipefail
umask 077

if ! command -v keytool >/dev/null 2>&1; then
    echo 'Java keytool is required (install JDK 17).' >&2
    exit 1
fi
if [[ ! -t 0 ]]; then
    echo 'Run interactively in a private terminal; keytool will prompt for passwords.' >&2
    exit 1
fi

read -r -p 'Absolute keystore path outside this repository: ' signing_path
if [[ "$signing_path" != /* ]]; then
    echo 'An absolute path is required.' >&2
    exit 1
fi
signing_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# Canonicalize the parent to reject paths and symlinks leading into the checkout.
signing_parent="$(cd "$(dirname "$signing_path")" && pwd -P)"
signing_path="$signing_parent/$(basename "$signing_path")"
if [[ "$signing_path" == "$signing_root"/* || -e "$signing_path" || -L "$signing_path" ]]; then
    echo 'Choose a new path outside the repository. Existing files are never overwritten.' >&2
    exit 1
fi
read -r -p 'Key alias [release]: ' signing_alias
signing_alias="${signing_alias:-release}"
# keytool reads passwords from the terminal, keeping them out of argv and logs.
# JKS supports separate key and store passwords as required by Android signing.
keytool -genkeypair -keystore "$signing_path" -storetype JKS \
    -alias "$signing_alias" -keyalg RSA -keysize 3072 -validity 10000
chmod 600 "$signing_path"
printf '%s\n' 'Private keystore created. Back it up in encrypted storage and keep its passwords in a password manager.'
printf '%s\n' 'See SIGNING.md to configure local release builds and repository secrets separately.'
