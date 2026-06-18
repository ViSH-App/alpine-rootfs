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

apk add --no-cache curl tar zstd >/dev/null

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
# TERM/HOME are NOT set here: the app injects them via execve envp and login(1)
# preserves TERM / sets HOME from /etc/passwd, so a rootfs fallback would only
# duplicate them. PATH stays because login resets it (see below).
mkdir -p "$TARGET/etc/profile.d" "$TARGET/etc/bash"
for f in "$TARGET/etc/profile.d/10-default-env.sh" "$TARGET/etc/bash/10-default-env.sh"; do
  cat > "$f" <<'EOF'
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
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
# iSH sessions are SIGKILLed on app switch/close, so bash never reaches the
# normal-exit hook that flushes history to disk. Append after every command.
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a"

alias ll='ls -alh'
alias la='ls -A'
EOF
chmod 0644 "$TARGET/etc/bash/20-interactive.sh"

# Enable the colored prompt shipped (disabled) by alpine-baselayout:
# red for root, green for everyone else.
ln -sf color_prompt.sh.disabled "$TARGET/etc/profile.d/color_prompt.sh"

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
