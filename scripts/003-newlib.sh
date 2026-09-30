#!/bin/bash
# 003-newlib.sh by ps2dev developers

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
TARGET_CFLAGS="-O2 -gdwarf-2 -gz"
OSVER=$(uname)

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
    --prefix="$PS2DEV/$TARGET_ALIAS" \
    --target="$TARGET" \
    --with-sysroot="$PS2DEV/$TARGET_ALIAS/$TARGET" \
    --enable-newlib-retargetable-locking \
    --enable-newlib-multithread \
    --enable-newlib-io-c99-formats \
    $TARG_XTRA_OPTS

  ## Compile and install.
  make --quiet -j "$PROC_NR" all
  make --quiet -j "$PROC_NR" install-strip
  make --quiet -j "$PROC_NR" clean

  ## Exit the build directory.
  cd ..

  ## End target.
done
