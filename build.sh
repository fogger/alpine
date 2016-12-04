#!/bin/bash
set -e

VERSIONS=("edge" "v3.5")

# supported architectures map 
# "APK_ARCH; QEMU_ARCH; TAG_ARCH"
ARCHS=("x86;i386;386" "x86_64;x86_64;amd64" "armhf;arm;arm" "aarch64;aarch64;arm64")

IMAGE="fogger/alpine"
MIRROR=${MIRROR:-http://dl-cdn.alpinelinux.org/alpine}

BUILD=.build

for VERSION in "${VERSIONS[@]}"; do
  (
    
    for i in "${ARCHS[@]}"; do
      (
        a=(${i//;/ })

        ARCH_APK=${a[0]}
        ARCH_QEMU=${a[1]}
        ARCH_TAG=${a[2]}

        REPO=$MIRROR/$VERSION/main
        
        LOCAL=$BUILD/$VERSION-$ARCH_APK
        TMP=$LOCAL/tmp
        ROOTFS=$LOCAL/rootfs
        QEMU=$BUILD/qemu

        mkdir -p $TMP $ROOTFS/usr/bin 

        # download apk.static
        if [ ! -f $TMP/sbin/apk.static ]; then
            apkv=$(curl -sSL $REPO/$ARCH_APK/APKINDEX.tar.gz | tar -Oxz | strings |
          grep '^P:apk-tools-static$' -A1 | tail -n1 | cut -d: -f2)
            curl -sSL $REPO/$ARCH_APK/apk-tools-static-${apkv}.apk | tar -xz -C $TMP sbin/apk.static
        fi

        # install qemu-user-static
        if [ -n "${ARCH_QEMU}" ]; then
          if [ ! -f $QEMU/x86_64_qemu-${ARCH_QEMU}-static.tar.gz ]; then
            wget -P $QEMU -N https://github.com/multiarch/qemu-user-static/releases/download/v2.6.0/x86_64_qemu-${ARCH_QEMU}-static.tar.gz
          fi
          tar -xzvf $QEMU/x86_64_qemu-${ARCH_QEMU}-static.tar.gz -C $ROOTFS/usr/bin/
        fi

        # create rootfs
        $TMP/sbin/apk.static -X $REPO -U --allow-untrusted -p $ROOTFS --initdb add alpine-base

        # alter rootfs
        printf '%s\n' $REPO > $ROOTFS/etc/apk/repositories

        # create tarball of rootfs
        if [ ! -f $LOCAL/rootfs.tar.gz ]; then
          tar --numeric-owner -C $ROOTFS -c . | gzip > $LOCAL/rootfs.tar.gz
        fi

        # clean rootfs
        rm -f $ROOTFS/usr/bin/qemu-*-static

        # create Dockerfile
        cat > $LOCAL/Dockerfile <<EOF
FROM scratch
ADD rootfs.tar.gz /

EOF
#ENV ARCH=${ARCH} ALPINE_REL=${REL} DOCKER_REPO=${repo} ALPINE_MIRROR=${MIRROR}

        # add qemu-user-static binary
        if [ -n "${QEMU_ARCH}" ]; then
          cat >> Dockerfile <<EOF

# Add qemu-user-static binary for amd64 builders
ADD x86_64_qemu-${QEMU_ARCH}-static.tar.gz /usr/bin
EOF
  fi

          # build
          docker build -t "${IMAGE}:${VERSION}-${ARCH_TAG}" $LOCAL
          docker run --rm "${IMAGE}:${VERSION}-${ARCH_TAG}" /bin/sh -ec "echo Hello from Alpine !; set -x; uname -a; cat /etc/alpine-release"
      )
    done

  )
done