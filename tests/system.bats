#!/usr/bin/env bats

load test_helper

# makepkg, sudo and chezmoi log their arguments; pacman -Q answers from $installed
setup() {
  setup_isolated_home
  SYSTEM="$PROJECT_ROOT/scripts/unix/setup-system.sh"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  calls="$BATS_TEST_TMPDIR/calls"
  installed="$BATS_TEST_TMPDIR/installed"
  mkdir -p "$mock_bin"
  : >"$installed"
  for tool in makepkg sudo chezmoi; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >>%q\n' "$tool" "$calls" >"$mock_bin/$tool"
  done
  cat >"$mock_bin/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>'$calls'
[[ "\$1" == '-Q' ]] || exit 0
grep -m1 "^\$2 " '$installed' || exit 1
EOF
  chmod +x "$mock_bin"/*
  unset CI
}

theme_version() {
  (
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/pkgbuilds/boot-themes/PKGBUILD"
    # shellcheck disable=SC2154
    printf '%s-%s\n' "$pkgver" "$pkgrel"
  )
}

@test "system step refuses to change / non-interactively or in CI" {
  run env PATH="$mock_bin:$PATH" NON_INTERACTIVE=1 "$SYSTEM"
  [ "$status" -ne 0 ]
  [[ "$output" == *'never runs non-interactively'* ]]

  run env PATH="$mock_bin:$PATH" CI=true "$SYSTEM"
  [ "$status" -ne 0 ]
  [[ "$output" == *'never runs in CI'* ]]

  [ ! -e "$calls" ]
}

@test "system dry-run lists missing theme packages and previews root/ without sudo" {
  before="$(find "$HOME" -mindepth 1 -print | sort)"

  run env PATH="$mock_bin:$PATH" CI=true "$SYSTEM" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"grub-theme-blackice: <not installed> -> $(theme_version)"* ]]
  [[ "$output" == *'+ makepkg --nodeps'* ]]
  [[ "$output" == *'+ sudo pacman -U --needed --overwrite '* ]]
  [[ "$output" == *'--overwrite /usr/share/grub/themes/blackice/\*'* ]]
  grep -q '^chezmoi .*--source=.*/root --destination=/ --persistent-state=.* diff --no-pager' "$calls"
  run grep -E '^(sudo|makepkg) |^pacman -U' "$calls"
  [ "$status" -eq 1 ]
  [ "$before" = "$(find "$HOME" -mindepth 1 -print | sort)" ]
}

@test "system dry-run reports theme packages that are up to date" {
  version="$(theme_version)"
  for name in grub-theme-astronaut grub-theme-astronaut-orange grub-theme-blackice \
    grub-theme-catppuccin-frappe grub-theme-catppuccin-latte grub-theme-catppuccin-macchiato \
    grub-theme-catppuccin-mocha plymouth-theme-arch-mac-style; do
    printf '%s %s\n' "$name" "$version" >>"$installed"
  done

  run env PATH="$mock_bin:$PATH" "$SYSTEM" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Boot theme packages are up to date ($version)"* ]]
  [[ "$output" != *'makepkg'* ]]
}

@test "dots skips system in a non-interactive bootstrap and refuses dots system" {
  run env PATH="$mock_bin:$PATH" "$PROJECT_ROOT/scripts/unix/dots" bootstrap --non-interactive \
    --skip packages --skip git --skip accounts --skip fonts --skip shell --skip apply \
    --skip desktop --skip wallpaper --skip sync
  [ "$status" -eq 0 ]
  [[ "$output" == *'Skipping system'* ]]

  run env PATH="$mock_bin:$PATH" NON_INTERACTIVE=1 "$PROJECT_ROOT/scripts/unix/dots" system
  [ "$status" -ne 0 ]
  [[ "$output" == *'never runs non-interactively'* ]]
  run grep -E '^(sudo|makepkg) |^pacman -U|^chezmoi .*/root' "$calls"
  [ "$status" -eq 1 ]
}

@test "root/ writes nothing under /usr; boot themes are packages" {
  [ ! -e "$PROJECT_ROOT/root/usr" ]
  [ -f "$PROJECT_ROOT/pkgbuilds/boot-themes/PKGBUILD" ]
  # Every theme the GRUB data can name is packaged
  theme="$(grep -E '^\s+theme: ' "$PROJECT_ROOT/root/.chezmoidata/boot.yaml" | head -1 | awk '{print $2}')"
  [ -f "$PROJECT_ROOT/pkgbuilds/boot-themes/grub/$theme/theme.txt" ]
}

@test "pacman.conf gets the dots.conf include and loses the options dots.conf owns" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  sample="$BATS_TEST_TMPDIR/pacman.conf"
  cat >"$sample" <<'EOF'
[options]
HoldPkg     = pacman glibc
#Color
Color
ParallelDownloads = 5
IgnorePkg   =   -nvidia-open
SigLevel    = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist
EOF
  template="$(cat "$PROJECT_ROOT/root/etc/modify_pacman.conf")"

  run chezmoi --source "$PROJECT_ROOT/root" execute-template --with-stdin "$template" <"$sample"

  [ "$status" -eq 0 ]
  expected='[options]
Include = /etc/pacman.d/dots.conf
HoldPkg     = pacman glibc
#Color
SigLevel    = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist'
  [ "$output" = "$expected" ]

  printf '%s\n' "$output" >"$sample"
  run chezmoi --source "$PROJECT_ROOT/root" execute-template --with-stdin "$template" <"$sample"
  [ "$output" = "$expected" ]
}

@test "GRUB and SDDM templates render the boot data" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT/root" execute-template <"$PROJECT_ROOT/root/etc/default/grub.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRUB_THEME='/usr/share/grub/themes/blackice/theme.txt'"* ]]
  [[ "$output" == *"GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog nvme_load=YES splash loglevel=3'"* ]]
  [[ "$output" == *'GRUB_DISTRIBUTOR='* ]]

  run chezmoi --source "$PROJECT_ROOT/root" execute-template <"$PROJECT_ROOT/root/etc/sddm.conf.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Current=silent'* ]]
}

@test "boot hooks and plymouthd.conf render with content hashes" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT/root" execute-template \
    <"$PROJECT_ROOT/root/.chezmoiscripts/run_onchange_after_10-grub-mkconfig.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ etc/default/grub:\ [0-9a-f]{64} ]]
  [[ "$output" == *'grub-mkconfig -o /boot/grub/grub.cfg'* ]]

  run chezmoi --source "$PROJECT_ROOT/root" execute-template \
    <"$PROJECT_ROOT/root/.chezmoiscripts/run_onchange_after_20-initramfs.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ plymouthd.conf:\ [0-9a-f]{64} ]]

  run chezmoi --source "$PROJECT_ROOT/root" execute-template <"$PROJECT_ROOT/root/etc/plymouth/plymouthd.conf.tmpl"
  [[ "$output" == *'Theme=cuts'* ]]
}
