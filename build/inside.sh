#!/bin/sh
# Runs inside an aarch64 alpine:${ALPINE_VERSION} container.
# Bootstraps the official Alpine miniroot tarball, installs the package set,
# strips caches/dynamic mountpoints, and emits a clean rootfs tarball.
set -eu

: "${ALPINE_BRANCH:?}"
: "${ALPINE_VERSION:?}"
: "${ARCH:?}"
: "${OUT_NAME:?}"

TARGET=/tmp/rootfs
WORK=/tmp/work
mkdir -p "$TARGET" "$WORK"

apk add --no-cache curl tar >/dev/null

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

# Drop install-time DNS; iSH/consumers manage this at runtime.
rm -f "$TARGET/etc/resolv.conf"

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

echo ">> Packing $OUT_NAME"
cd "$TARGET"
tar --numeric-owner --owner=0 --group=0 -czf "/out/$OUT_NAME" .

ls -lah "/out/$OUT_NAME"
