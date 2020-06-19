#!/bin/bash
# com.khronos.go | make.sh

set -e
set -u

PROJECTROOT="$(cd $(dirname $0)&&pwd)"
readonly PROJECTROOT
cd "${PROJECTROOT}"

ARCH="${ARCH-$(arch)}"
if [ "${ARCH}" = arm ]; then
  ARCH=armv7
fi

VERSION="1.14.4"
PATCHVERSION="1"

export CC=clang
export CXX=clang++
export AR=llvm-ar

export GOOS=darwin
export GOARCH
export GOROOT
export CGO_ENABLED=1

download() {
  if [ ! -r "${PROJECTROOT}/go${VERSION}.src.tar.gz" ]; then
    curl -o "${PROJECTROOT}/go${VERSION}.src.tar.gz" "https://dl.google.com/go/go${VERSION}.src.tar.gz"
  fi
  tar xvf "${PROJECTROOT}/go${VERSION}.src.tar.gz" -C "${BUILDROOT}"
}

init() {
  ARCH="$1"
  BUILDROOT="${PROJECTROOT}/${ARCH}"
  BUILDGOROOT="${BUILDROOT}/go"
  if [ -e "${BUILDROOT}" ]; then
    rm -rf "${BUILDROOT}"
  fi
  mkdir -p "${BUILDROOT}"
}

applyPatch() {
  for p in $(find "${PROJECTROOT}/patches" -name "*.patch"); do
    patch -u -p0 -d "${BUILDROOT}" -i "$p"
  done
}

build() {
  GOROOT="${BUILDROOT}/go"
  cd "${GOROOT}/src"

  if [ "${ARCH}" = armv7 ]; then
    GOARCH=arm
  else
    GOARCH="${ARCH}"
  fi

  bash make.bash -v  ||
  go install -v -i cmd/asm cmd/cgo cmd/compile cmd/link
  rm -rf "${GOROOT}/pkg/tool"
  bash make.bash -v --no-clean
  cd "${PROJECTROOT}"
}

bundle() {
  local destdir="${BUILDROOT}/build"
  rm -rf "${destdir}"
  mkdir -p "${destdir}"

  local sharedir="${destdir}/usr/share"
  local bindir="${destdir}/usr/bin"
  # local configdir="${destdir}/etc/go"
  local libdir="${destdir}/usr/lib/go"
  local docdir="${sharedir}/doc/go"
  local licensedir="${sharedir}/licenses/go"

  cd "${BUILDGOROOT}"

  mkdir -p "${bindir}"
  ln -s /usr/lib/go/bin/go "${bindir}/go"
  ln -s /usr/lib/go/bin/gofmt "${bindir}/gofmt"

  # mkdir -p "${configdir}"
  # cp -R config/. "${configdir}"

  mkdir -p "${libdir}"
  cp -R VERSION api bin lib misc pkg  src test "${libdir}"
  ln -s /usr/share/doc/go "${libdir}/doc"

  mkdir -p "${docdir}"
  cp -R doc/. "${docdir}"

  mkdir -p "${licensedir}"
  cp -R LICENSE "${licensedir}"

  cd "${PROJECTROOT}"
}

merge() {
  mkdir -p "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/arm64/build/." "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/armv7/build/." "${PROJECTROOT}/fat/build"

  cd "${PROJECTROOT}"

  find "fat/build" -type f |
  while read x; do
    if lipo -info "$x" >/dev/null 2>&1; then
      rm "$x"
      lipo -create "${x/fat/arm64}" "${x/fat/armv7}" -output "$x"
      if test -x "$x"; then
        ldid -S/usr/share/SDKs/entitlements.xml "$x"
      fi
    fi
  done
}

pack() {
  local ARCHS
  if [ "$1" = fat ]; then
    ARCHS="ARM64/ARMv7"
  elif [ "$1" = arm64 ]; then
    ARCHS=ARM64
  elif [ "$1" = armv7 ]; then
    ARCHS=ARMv7
  else
    echo "Unknown architecture." >&2
    exit 1
  fi
  BUILDROOT="${PROJECTROOT}/$1"
  cp -R "${PROJECTROOT}/deb/." "${BUILDROOT}/build"
  sed -e "/^Version:/s/%%VERSION%%/${VERSION}-${PATCHVERSION}/" \
      -e "/^Description:/s_%%ARCHS%%_${ARCHS}_" \
      -i -- "${BUILDROOT}/build/DEBIAN/control"
  if dpkg --compare-versions "$(dpkg-query -f '${Version}' -W dpkg)" ge 1.19.0; then
    dpkg-deb -Zxz --root-owner-group --build "${BUILDROOT}/build" "${BUILDROOT}"
  else
    su <<<"chown -R 0:0 \"${BUILDROOT}/build\""
    dpkg-deb -Zxz --build "${BUILDROOT}/build" "${BUILDROOT}"
  fi
}

init "${ARCH}"
download
applyPatch
build
bundle

# merge

pack "${ARCH}"
