#!/bin/bash
# One-shot installer: Synology Active Backup for Business agent on Ubuntu 20.04.
# Fixes the "linux-headers-$(uname -r) has no installation candidate" failure
# by falling back to the canonical focal kernel when the running kernel is
# third-party (mainline/HWE/whatever the repos do not ship headers for).
set -u

REPO_RAW="https://raw.githubusercontent.com/dealenx/agent-synology-ubuntu-20/main"
INSTALLER="install.run"

log() { echo "[abb-install] $*"; }
die() { echo "[abb-install] ERROR: $*" >&2; exit 1; }

# 1. root
if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@" 2>/dev/null || die "run as root: sudo bash $0"
fi

# 2. Ubuntu 20.04
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "20.04" ] \
    || die "Ubuntu 20.04 required, found ${ID:-?} ${VERSION_ID:-?}"

# capture the script's directory before cd (works when invoked as ./install-abb.sh)
SCRIPT_DIR=""
[ -f "$0" ] && SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

export DEBIAN_FRONTEND=noninteractive
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# 3. fetch installer: a copy next to this script wins (works offline/in CI),
# otherwise download — required for the `curl | bash` flow
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$INSTALLER" ]; then
    cp "$SCRIPT_DIR/$INSTALLER" .
else
    command -v curl >/dev/null || die "curl is required to download $INSTALLER"
    log "downloading $INSTALLER..."
    curl -fsSL -o "$INSTALLER" "$REPO_RAW/$INSTALLER" || die "download failed"
fi
chmod +x "$INSTALLER"

apt-get update -qq || die "apt-get update failed (network?)"

# 4. dependency pre-flight: the installer demands linux-headers-$(uname -r)
if ! apt-get install -y -qq "linux-headers-$(uname -r)" >/dev/null 2>&1; then
    log "headers for running kernel $(uname -r) are not in the repos (third-party kernel)."
    log "installing canonical Ubuntu 20.04 kernel (linux-generic)..."
    apt-get install -y -qq linux-generic >/dev/null || die "cannot install linux-generic"

    # NOT "newest in /lib/modules" — that could still be the third-party kernel.
    # Pick a kernel whose headers package dpkg actually reports as installed.
    K=""
    for cand in $(dpkg-query -W -f='${Package}\n' 'linux-headers-*' 2>/dev/null \
                    | sed 's/^linux-headers-//' | sort -ru); do
        if [ -e "/lib/modules/$cand" ] && [ -e "/lib/modules/$cand/build" ]; then
            K=$cand
            break
        fi
    done
    [ -n "$K" ] || die "linux-generic installed but no kernel with headers found in dpkg"
    log "installer will use headers for kernel $K; reboot into it after install to load the driver."

    # shim: report the focal kernel for 'uname -r' inside the installer only
    mkdir -p "$WORK/bin"
    printf '#!/bin/sh\n[ "$1" = "-r" ] && echo %s && exit 0\nexec /bin/uname "$@"\n' "$K" > "$WORK/bin/uname"
    chmod +x "$WORK/bin/uname"
    export PATH="$WORK/bin:$PATH"
fi

apt-get install -y -qq dkms make libglib2.0-0 mokutil >/dev/null || die "cannot install dkms/make/libglib2.0-0/mokutil"

# 5. run the vendor installer
rc=0
./"$INSTALLER" || rc=$?
if [ "$rc" -eq 0 ]; then
    if [ -n "${K:-}" ]; then
        log "driver was built for kernel $K — reboot into it, then 'modprobe synosnap'."
    fi
else
    die "installer exited with $rc (see output above)"
fi

# 6. verify the snapshot driver (Synology KB: error 0xfffffffffffffffe means
# synosnap is missing or failed to initialize)
TARGET_K="${K:-$(uname -r)}"

if ! dkms status -m synosnap -k "$TARGET_K" 2>/dev/null | grep -q installed; then
    log "driver not registered in dkms for $TARGET_K — purge and reinstall agent (KB step)"
    dpkg --purge synosnap synology-active-backup-business-linux-service >/dev/null 2>&1 || true
    ./install.run >/tmp/abb-reinstall.log 2>&1 || { tail -20 /tmp/abb-reinstall.log; die "driver reinstall failed"; }
    dkms status -m synosnap -k "$TARGET_K" 2>/dev/null | grep -q installed \
        || die "driver still missing in dkms for $TARGET_K — kernel may be unsupported (KB 0xfffffffffffffffe)"
fi
log "driver registered in dkms for $TARGET_K"

if lsmod | grep -q synosnap && cat /proc/synosnap-info >/dev/null 2>&1; then
    log "synosnap loaded, /proc/synosnap-info OK"
else
    log "driver not loaded yet — after reboot into $TARGET_K run: modprobe synosnap && cat /proc/synosnap-info"
fi

if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    log "Secure Boot is ON — after reboot: sudo mokutil --import /opt/synosnap/MOK.der (KB 0xfffffffffffffffe)"
fi

log "install complete. Next: run 'abb-cli -c' to connect to your NAS."
