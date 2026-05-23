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

# System-wide SSL certificate bundle for tools that honor SSL_CERT_FILE.
mkdir -p "$TARGET/etc/profile.d"
cat > "$TARGET/etc/profile.d/ssl-cert.sh" <<'EOF'
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
EOF
chmod 0644 "$TARGET/etc/profile.d/ssl-cert.sh"

# Defensive cleanup — keep the archive small and reproducible.
rm -rf \
  "$TARGET/var/cache/apk/"* \
  "$TARGET/tmp/"* \
  "$TARGET/root/.ash_history" \
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
