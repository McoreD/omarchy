echo "Keep the EFI framebuffer on 2020 5K iMacs with AMD Navi 14"

if ! omarchy-hw-imac20-navi14; then
  exit 0
fi

limine_conf="${OMARCHY_IMAC20_DISPLAY_CONF:-/etc/limine-entry-tool.d/imac20-display.conf}"
repair_marker="${OMARCHY_IMAC20_REPAIR_MARKER:-/var/lib/omarchy/migrations/1789574960}"
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
  sudo install -Dm644 /dev/null "$repair_marker"
fi
