#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-install-imac20-amdgpu-hwaccel"
all_hardware="$ROOT/install/hardware/all.sh"
manual="$ROOT/manual/44-mac-support.md"

test -x "$command" || fail "opt-in command is executable"
! grep -Fq 'imac20-amdgpu-hwaccel' "$all_hardware" ||
  fail "hardware acceleration stays opt-in, not part of install"
grep -Fq 'omarchy-install-imac20-amdgpu-hwaccel' "$manual" ||
  fail "Mac support manual mentions the opt-in command"
! grep -Eq 'git clone|amdgpu\.ko' "$command" ||
  fail "opt-in uses the linux-t2 package amdgpu, no module build"
pass "iMac20 hardware acceleration is an opt-in command"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
stubs="$tmp_dir/bin"
mkdir -p "$stubs" "$tmp_dir/uki" "$tmp_dir/devices/0000:03:00.0" "$tmp_dir/modules/6.18.1-arch1-Watanare-T2-1-t2"

echo "iMac20,1" >"$tmp_dir/product_name"
echo 0x1002 >"$tmp_dir/devices/0000:03:00.0/vendor"
echo 0x7340 >"$tmp_dir/devices/0000:03:00.0/device"
echo 0x030000 >"$tmp_dir/devices/0000:03:00.0/class"
echo linux-t2 >"$tmp_dir/modules/6.18.1-arch1-Watanare-T2-1-t2/pkgbase"
: >"$tmp_dir/modules/6.18.1-arch1-Watanare-T2-1-t2/vmlinuz"

cat >"$stubs/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stubs/limine-mkinitcpio" <<'SH'
#!/bin/bash
echo "limine-mkinitcpio" >>"$TEST_LOG"
exit 1
SH

# Build a UKI whose .cmdline is the --cmdline file.
cat >"$stubs/mkinitcpio" <<'SH'
#!/bin/bash
echo "mkinitcpio $*" >>"$TEST_LOG"
[[ -n ${FAIL_MKINITCPIO:-} ]] && exit 1
while (( $# )); do
  case $1 in
    -k) kernel=$2; shift ;;
    -U) uki=$2; shift ;;
    --cmdline) cmdline=$2; shift ;;
  esac
  shift
done
[[ -f $kernel ]] || exit 1
cat "$cmdline" >"$uki"
SH

cat >"$stubs/objcopy" <<'SH'
#!/bin/bash
cat "$4"
SH

cat >"$stubs/limine-entry-tool" <<'SH'
#!/bin/bash
echo "limine-entry-tool $*" >>"$TEST_LOG"
[[ $1 == --remove-efi-path ]] && rm -f "$2"
exit 0
SH
chmod +x "$stubs"/*

run() {
  OMARCHY_DMI_PRODUCT_NAME="$tmp_dir/product_name" \
    OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" \
    OMARCHY_IMAC20_DISPLAY_CONF="$tmp_dir/imac20-display.conf" \
    OMARCHY_LIMINE_CONF="$tmp_dir/limine.conf" \
    OMARCHY_UKI_DIR="$tmp_dir/uki" \
    OMARCHY_MODULES_DIR="$tmp_dir/modules" \
    OMARCHY_IMAC20_HWACCEL_SAVED_DEFAULT="$tmp_dir/saved-default" \
    OMARCHY_IMAC20_HWACCEL_HOOK="$tmp_dir/hwaccel.hook" \
    TEST_LOG="$tmp_dir/calls.log" \
    PATH="$stubs:$ROOT/bin:$PATH" \
    "$command" "$@" </dev/null >"$tmp_dir/out.log" 2>&1
}

cat >"$tmp_dir/imac20-display.conf" <<'EOF'
KERNEL_CMDLINE[default]+=" plymouth.enable=0 nomodeset"
EOF
safe_cmdline="cryptdevice=PARTUUID=abc:root root=/dev/mapper/root rw plymouth.enable=0 nomodeset"
echo "$safe_cmdline" >"$tmp_dir/uki/omarchy_linux-t2.efi"
printf '%s\n' '#timeout: 3' 'default_entry: 2' 'interface_branding: Omarchy Bootloader' >"$tmp_dir/limine.conf"
cp "$tmp_dir/limine.conf" "$tmp_dir/limine.conf.orig"
cp "$tmp_dir/imac20-display.conf" "$tmp_dir/imac20-display.conf.orig"

safe_untouched() {
  [[ $(cat "$tmp_dir/uki/omarchy_linux-t2.efi") == "$safe_cmdline" ]] ||
    fail "$1: safe UKI is untouched"
  cmp -s "$tmp_dir/imac20-display.conf" "$tmp_dir/imac20-display.conf.orig" ||
    fail "$1: display drop-in is untouched"
  ! grep -Fq 'limine-mkinitcpio' "$tmp_dir/calls.log" ||
    fail "$1: default UKIs are not rebuilt"
}

run || fail "opt-in succeeds" "$(cat "$tmp_dir/out.log")"
[[ $(cat "$tmp_dir/uki/omarchy_linux-t2-hwaccel.efi") == \
  "cryptdevice=PARTUUID=abc:root root=/dev/mapper/root rw plymouth.enable=0 amdgpu.modeset=1 video=efifb:off" ]] ||
  fail "hardware-acceleration UKI keeps the safe cmdline with nomodeset swapped for amdgpu" \
    "$(cat "$tmp_dir/uki/omarchy_linux-t2-hwaccel.efi")"
grep -Fq 'mkinitcpio -k '"$tmp_dir"'/modules/6.18.1-arch1-Watanare-T2-1-t2/vmlinuz -U' "$tmp_dir/calls.log" ||
  fail "hardware-acceleration UKI is built from the linux-t2 kernel"
safe_untouched "opt-in"
grep -Fq 'limine-entry-tool --add-efi imac20-hwaccel' "$tmp_dir/calls.log" ||
  fail "hardware-acceleration Limine entry is added"
cmp -s "$tmp_dir/limine.conf" "$tmp_dir/limine.conf.orig" ||
  fail "safe entry stays the default without --default"
grep -Fq 'Target = linux-t2' "$tmp_dir/hwaccel.hook" &&
  grep -Fq 'Target = usr/lib/firmware/*' "$tmp_dir/hwaccel.hook" &&
  grep -Fq 'omarchy-install-imac20-amdgpu-hwaccel --rebuild' "$tmp_dir/hwaccel.hook" ||
  fail "pacman hook rebuilds the entry on linux-t2 upgrades"
pass "opt-in adds a hardware-acceleration entry next to the safe default"

run --default || fail "--default succeeds" "$(cat "$tmp_dir/out.log")"
grep -Fxq 'default_entry: imac20-hwaccel' "$tmp_dir/limine.conf" ||
  fail "--default boots the hardware-acceleration entry"
[[ $(grep -c 'default_entry:' "$tmp_dir/limine.conf") == 1 ]] ||
  fail "--default replaces the default_entry line"
[[ $(tail -n1 "$tmp_dir/calls.log") == "limine-entry-tool --add-efi imac20-hwaccel"* ]] ||
  fail "limine-entry-tool writes limine.conf after the default_entry edit"
run --default || fail "--default twice succeeds"
pass "--default makes the hardware-acceleration entry the default"

: >"$tmp_dir/calls.log"
FAIL_MKINITCPIO=1 run --rebuild || fail "--rebuild never fails the pacman transaction"
[[ ! -e $tmp_dir/uki/omarchy_linux-t2-hwaccel.efi ]] ||
  fail "failed rebuild removes the stale hardware-acceleration UKI"
cmp -s "$tmp_dir/limine.conf" "$tmp_dir/limine.conf.orig" ||
  fail "failed rebuild restores Omarchy's default entry" "$(cat "$tmp_dir/limine.conf")"
safe_untouched "failed rebuild"
pass "failed rebuild falls back to the safe entry"

: >"$tmp_dir/calls.log"
FAIL_MKINITCPIO=1 run && fail "failed opt-in exits non-zero"
[[ ! -e $tmp_dir/uki/omarchy_linux-t2-hwaccel.efi ]] || fail "failed opt-in adds no UKI"
cmp -s "$tmp_dir/limine.conf" "$tmp_dir/limine.conf.orig" || fail "failed opt-in leaves limine.conf alone"
safe_untouched "failed opt-in"
pass "failed opt-in leaves the safe boot path alone"

run --default || fail "--default succeeds again"
run --remove || fail "--remove succeeds"
cmp -s "$tmp_dir/limine.conf" "$tmp_dir/limine.conf.orig" ||
  fail "--remove after --default restores Omarchy's default entry" "$(cat "$tmp_dir/limine.conf")"
[[ ! -e $tmp_dir/uki/omarchy_linux-t2-hwaccel.efi && ! -e $tmp_dir/hwaccel.hook ]] ||
  fail "--remove drops the entry and the hook"
pass "--remove drops the entry and the hook"

echo "MacBookPro16,1" >"$tmp_dir/product_name"
: >"$tmp_dir/calls.log"
run || fail "exits 0 on other hardware"
[[ ! -s $tmp_dir/calls.log ]] || fail "other hardware is left alone" "$(cat "$tmp_dir/calls.log")"
pass "other hardware is left alone"
