#!/bin/bash
# 004-newlib-nano.sh by ps2dev developers

## This script is needed to generate a separate and nano libc. This is usefull for such programs that requires to have tiny binaries.
## I have tried to use --program-suffix during configure, but it looks that newlib is not using the flag properly.
## For this reason it requires to use a custom instalation script

## Exit with code 1 when any command executed returns a non-zero exit code.
onerr()
{
  exit 1;
}
trap onerr ERR

## Read information from the configuration file.
source "$(dirname "$0")/../config/ps2toolchain-ee-config.sh"

## ---- Android build: this script builds TARGET libraries only ---------------
## It must run with the native (x86_64) cross tools built earlier (STEP A of
## EE 001/002), never with the Android host toolchain that the workflow exports
## (CC=aarch64-linux-android21-clang ...). Otherwise configure tries to run
## Android binaries: "configure: error: cannot run C compiled programs".
unset CC CXX AR LD RANLIB NM STRIP CONFIGURE_HOST CPPFLAGS CFLAGS CXXFLAGS LDFLAGS
if [ -n "$NATIVE_PS2DEV" ]; then
  export PATH="$NATIVE_PS2DEV/ee/bin:$NATIVE_PS2DEV/iop/bin:$PATH"
fi
echo "Target compiler in use: $(command -v mips64r5900el-ps2-elf-gcc)"
mips64r5900el-ps2-elf-gcc --version | head -n 1

## Download the source code.
REPO_URL="$PS2TOOLCHAIN_EE_NEWLIB_REPO_URL"
REPO_REF="$PS2TOOLCHAIN_EE_NEWLIB_DEFAULT_REPO_REF"
REPO_FOLDER="$(s="$REPO_URL"; s=${s##*/}; printf "%s" "${s%.*}")"

# Checking if a specific Git reference has been passed in parameter $1
if test -n "$1"; then
  REPO_REF="$1"
  printf 'Using specified repo reference %s\n' "$REPO_REF"
fi

if test ! -d "$REPO_FOLDER"; then
  git clone --depth 1 -b "$REPO_REF" "$REPO_URL" "$REPO_FOLDER"
else
  git -C "$REPO_FOLDER" remote set-url origin "$REPO_URL"
  git -C "$REPO_FOLDER" fetch origin "$REPO_REF" --depth=1
  git -C "$REPO_FOLDER" checkout -f FETCH_HEAD
fi

cd "$REPO_FOLDER"

TARGET_ALIAS="ee"
TARG_XTRA_OPTS=""
TARGET_CFLAGS="-DPREFER_SIZE_OVER_SPEED=1 -Os -gdwarf-2 -gz"
OSVER=$(uname)

PS2DEV_TMP="$PWD/ps2dev-tmp"

## Create ps2dev-tmp folder
rm -rf "$PS2DEV_TMP"
mkdir "$PS2DEV_TMP"

## Determine the maximum number of processes that Make can work with.
PROC_NR=$(getconf _NPROCESSORS_ONLN)

## For each target...
for TARGET in "mips64r5900el-ps2-elf"; do
  ## Create and enter the toolchain/build directory
  rm -rf "build-$TARGET"
  mkdir "build-$TARGET"
  cd "build-$TARGET"

  ## Configure the build.
  CFLAGS_FOR_TARGET="$TARGET_CFLAGS" \
  ../configure \
    --prefix="$PS2DEV_TMP/$TARGET_ALIAS" \
    --target="$TARGET" \
    --with-sysroot="$PS2DEV/$TARGET_ALIAS/$TARGET" \
    --disable-newlib-supplied-syscalls \
    --enable-newlib-reent-small \
    --disable-newlib-fvwrite-in-streamio \
    --disable-newlib-fseek-optimization \
    --disable-newlib-wide-orient \
    --enable-newlib-nano-malloc \
    --disable-newlib-unbuf-stream-opt \
    --enable-lite-exit \
    --enable-newlib-global-atexit \
    --enable-newlib-nano-formatted-io \
    --enable-newlib-retargetable-locking \
    --enable-newlib-multithread \
    --disable-nls \
    $TARG_XTRA_OPTS


  ## Compile and install.
  make --quiet -j "$PROC_NR" all
  make --quiet -j "$PROC_NR" install-strip
  make --quiet -j "$PROC_NR" clean

  ## Copy & rename manually libc, libg and libm to libc-nano, libg-nano and libm-nano
  mv "$PS2DEV_TMP/$TARGET_ALIAS/$TARGET/lib/libc.a" "$PS2DEV/$TARGET_ALIAS/$TARGET/lib/libc_nano.a"
  mv "$PS2DEV_TMP/$TARGET_ALIAS/$TARGET/lib/libg.a" "$PS2DEV/$TARGET_ALIAS/$TARGET/lib/libg_nano.a"
  mv "$PS2DEV_TMP/$TARGET_ALIAS/$TARGET/lib/libm.a" "$PS2DEV/$TARGET_ALIAS/$TARGET/lib/libm_nano.a"

  ## Exit the build directory.
  cd ..

  ## End target.
done

## ---- Android build: mirror target headers/libs into the native tree ---------
## Newlib etc. are installed under $PS2DEV/ee (the Android package tree), but the
## native x86_64 cross compiler that keeps building later stages only searches
## $NATIVE_PS2DEV/ee/<target>/{include,lib}. Without this copy, later steps fail
## with e.g. "fatal error: errno.h: No such file or directory".
SYNC_TARGET="mips64r5900el-ps2-elf"
if [ -n "$NATIVE_PS2DEV" ]; then
  for d in include lib; do
    if [ -d "$PS2DEV/ee/$SYNC_TARGET/$d" ]; then
      mkdir -p "$NATIVE_PS2DEV/ee/$SYNC_TARGET/$d"
      cp -a "$PS2DEV/ee/$SYNC_TARGET/$d/." "$NATIVE_PS2DEV/ee/$SYNC_TARGET/$d/"
    fi
  done
  echo "Synced $SYNC_TARGET include/lib into $NATIVE_PS2DEV/ee"
  ls "$NATIVE_PS2DEV/ee/$SYNC_TARGET/include/errno.h"
fi
