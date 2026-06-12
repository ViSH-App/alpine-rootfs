#!/bin/sh
# Runs inside an aarch64 alpine:${ALPINE_VERSION} container.
# Bootstraps the official Alpine miniroot tarball, installs the package set,
# strips caches/dynamic mountpoints, and emits a clean rootfs tarball.
set -eu

: "${ALPINE_BRANCH:?}"
: "${ALPINE_VERSION:?}"
: "${ARCH:?}"
: "${OUT_NAME:?}"
: "${OUT_NAME_ZSTD:?}"

TARGET=/tmp/rootfs
WORK=/tmp/work
mkdir -p "$TARGET" "$WORK"

# build-base stays in the build container only — the target rootfs gets the
# resulting static binary, never the toolchain.
apk add --no-cache curl tar zstd build-base >/dev/null

MIRROR="https://dl-cdn.alpinelinux.org/alpine"
MIN_TARBALL="alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
MIN_URL="$MIRROR/$ALPINE_BRANCH/releases/$ARCH/$MIN_TARBALL"

echo ">> Fetching $MIN_URL"
curl -fsSL -o "$WORK/$MIN_TARBALL" "$MIN_URL"

echo ">> Extracting miniroot"
tar -xzf "$WORK/$MIN_TARBALL" -C "$TARGET"

# Configure repos for the target itself (so consumers can apk add later).
mkdir -p "$TARGET/etc/apk"
cat > "$TARGET/etc/apk/repositories" <<EOF
$MIRROR/$ALPINE_BRANCH/main
$MIRROR/$ALPINE_BRANCH/community
EOF

# Provide DNS to the chroot during install only.
cp /etc/resolv.conf "$TARGET/etc/resolv.conf"

PACKAGES=$(grep -vE '^[[:space:]]*(#|$)' /build/packages.txt | tr '\n' ' ')

echo ">> Installing packages:"
echo "   $PACKAGES"
chroot "$TARGET" /sbin/apk update
chroot "$TARGET" /sbin/apk add --no-cache $PACKAGES

# Ship default DNS so consumers have working resolution out of the box.
cat > "$TARGET/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Blank the MOTD shipped by the miniroot.
: > "$TARGET/etc/motd"

# Default environment. Every value here is a guarded fallback — whatever the
# spawner passes in wins. Installed twice: /etc/profile.d for login shells
# (iSH sessions run /bin/login -f root), /etc/bash for interactive non-login
# bash (sourced by Alpine's /etc/bash/bashrc).
mkdir -p "$TARGET/etc/profile.d" "$TARGET/etc/bash"
for f in "$TARGET/etc/profile.d/10-default-env.sh" "$TARGET/etc/bash/10-default-env.sh"; do
  cat > "$f" <<'EOF'
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
# bash self-initializes TERM=dumb when the spawner leaves it unset, so treat
# dumb as "not provided" too. xterm-direct has no terminfo entry in
# ncurses-terminfo-base; truecolor is signaled via COLORTERM, not TERM.
if [ -z "${TERM:-}" ] || [ "$TERM" = dumb ]; then
  export TERM=xterm-256color
fi
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  export HOME=/root
fi
# iSH passes these dirs in PATH via execve, but login(1) strips that PATH and
# /etc/profile resets it to the standard six; re-prepend to match the app.
# Unconditional: installers (pip, uv, bun) create these dirs mid-session, and
# a not-yet-existing PATH entry is harmless.
for _d in "$HOME/.bun/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) PATH="$_d:$PATH" ;;
  esac
done
unset _d
export PATH
EOF
  chmod 0644 "$f"
done

# Make bash the login shell for root: iSH sessions run /bin/login -f root,
# which starts the shell listed in /etc/passwd. The grep makes the build fail
# loudly if upstream ever changes the passwd layout and the sed stops matching.
sed -i 's#^\(root:.*\):/bin/sh$#\1:/bin/bash#' "$TARGET/etc/passwd"
grep -q '^root:.*:/bin/bash$' "$TARGET/etc/passwd"

# Interactive bash defaults: history behavior and a couple of aliases.
# Lives only in /etc/bash so ash never sources the bash-only shopt.
# No grep/ls color aliases on purpose: busybox grep has no --color, and
# busybox ls is compiled with color-by-default.
cat > "$TARGET/etc/bash/20-interactive.sh" <<'EOF'
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend

alias ll='ls -alh'
alias la='ls -A'
EOF
chmod 0644 "$TARGET/etc/bash/20-interactive.sh"

# Enable the colored prompt shipped (disabled) by alpine-baselayout:
# red for root, green for everyone else.
ln -sf color_prompt.sh.disabled "$TARGET/etc/profile.d/color_prompt.sh"

# ssh-agent-bridge: pumps bytes between /tmp/ssh-agent.sock and iSH's
# /dev/ish-ssh-agent device (SSH key management, see docs/ssh-key-management.md
# in the ish repo). Static musl binary; exits 0 silently when the device is
# absent (bridge disabled in app Settings, or app predates the feature).
gcc -static -O2 -Wall -Wextra -Werror -s \
    -o "$TARGET/usr/sbin/ssh-agent-bridge" /build/ssh-agent-bridge.c
chmod 0755 "$TARGET/usr/sbin/ssh-agent-bridge"

# Agent socket for login shells. The daemon does its own singleton/staleness
# probing (connect succeeds → already running → exit), so repeated logins are
# harmless; it daemonizes only after bind+listen, so the socket is usable the
# moment this line returns — no polling. Users with their own agent re-export
# SSH_AUTH_SOCK in ~/.profile, which runs after profile.d and naturally wins.
cat > "$TARGET/etc/profile.d/ssh-agent.sh" <<'EOF'
export SSH_AUTH_SOCK=/tmp/ssh-agent.sock

[ -x /usr/sbin/ssh-agent-bridge ] && /usr/sbin/ssh-agent-bridge >/dev/null 2>&1
EOF
chmod 0644 "$TARGET/etc/profile.d/ssh-agent.sh"

# Bake the RootfsPatch overlay (patch/ in the repo) into the image and record
# its version, so freshly imported roots skip iSH's FsApplyOverlay() on first
# boot. Applied last: hotfixes win over anything this script set up above.
PATCH_VERSION=$(tr -cd '0-9' < /patch/VERSION)
[ -n "$PATCH_VERSION" ]
if [ -d /patch/files ]; then
  tar -C /patch/files --exclude='.gitkeep' --exclude='.DS_Store' -cf - . \
    | tar -C "$TARGET" -xf -
fi
mkdir -p "$TARGET/ish"
printf '%s\n' "$PATCH_VERSION" > "$TARGET/ish/overlay-version"

# Defensive cleanup — keep the archive small and reproducible.
rm -rf \
  "$TARGET/var/cache/apk/"* \
  "$TARGET/tmp/"* \
  "$TARGET/root/.ash_history" \
  "$TARGET/root/.bash_history" \
  "$TARGET/root/.wget-hsts" 2>/dev/null || true

# Empty the dynamic mountpoints but keep the directories.
for d in proc sys dev; do
  rm -rf "${TARGET:?}/$d"
  mkdir -p "$TARGET/$d"
done

echo ">> Packing $OUT_NAME and $OUT_NAME_ZSTD"
cd "$TARGET"
TAR_TMP="$WORK/rootfs.tar"
tar --numeric-owner --owner=0 --group=0 -cf "$TAR_TMP" .
gzip -9 -c "$TAR_TMP" > "/out/$OUT_NAME"
zstd -19 --long -T0 -q -o "/out/$OUT_NAME_ZSTD" "$TAR_TMP"
rm -f "$TAR_TMP"

ls -lah "/out/$OUT_NAME" "/out/$OUT_NAME_ZSTD"
