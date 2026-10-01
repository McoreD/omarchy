echo "Keep the EFI framebuffer on 2020 5K iMacs with AMD Navi 14"

if ! omarchy-hw-imac20-navi14; then
  exit 0
fi

limine_conf="${OMARCHY_IMAC20_DISPLAY_CONF:-/etc/limine-entry-tool.d/imac20-display.conf}"
repair_marker="${OMARCHY_IMAC20_REPAIR_MARKER:-/var/lib/omarchy/migrations/1789574960}"
boot_conf="${OMARCHY_IMAC20_BOOT_CONF:-/boot/limine.conf}"
needs_limine_rebuild=0

if [[ ! -f $limine_conf ]] ||
  ! grep -Fq 'plymouth.enable=0' "$limine_conf" ||
  ! grep -Fq 'nomodeset' "$limine_conf"; then
  sudo mkdir -p "$(dirname "$limine_conf")"
  sudo tee "$limine_conf" >/dev/null <<'EOF'
# 2020 27" 5K iMac (iMac20,1 / iMac20,2) with Radeon Pro 5300/5500 (Navi 14).
# amdgpu SMU init fails under KMS and blanks the panel before LUKS.
KERNEL_CMDLINE[default]+=" plymouth.enable=0 nomodeset"
EOF
  needs_limine_rebuild=1
fi

# The marker records a completed machine-wide rebuild, so another user's
# migration does not repeat it before reboot. Rebuild whenever it is missing,
# even if the running cmdline already has the flags: those may have been typed
# into the Limine editor, and the next boot would be black again.
if [[ ! -e $repair_marker ]]; then
  needs_limine_rebuild=1
fi

if (( needs_limine_rebuild )); then
  sudo limine-mkinitcpio

  # limine-mkinitcpio exits 0 even when it skips a kernel whose build failed,
  # and only writes an entry after a successful build. Record the repair once
  # the linux-t2 entry actually boots with the flags.
  entry_cmdline=$(sudo grep -A1 -E '^[[:space:]]*path:[[:space:]]*boot\(\):/EFI/Linux/[^/]*linux-t2\.efi' "$boot_conf" |
    grep -E '^[[:space:]]*cmdline:' || true)
  if ! grep -Eq '(^| )plymouth\.enable=0( |$)' <<<"$entry_cmdline" ||
    ! grep -Eq '(^| )nomodeset( |$)' <<<"$entry_cmdline"; then
    echo "The linux-t2 boot entry in $boot_conf is missing plymouth.enable=0 nomodeset; run 'sudo limine-mkinitcpio' and check its output" >&2
    exit 1
  fi

  sudo install -Dm644 /dev/null "$repair_marker"
fi
