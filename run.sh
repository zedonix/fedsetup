#!/usr/bin/env bash
set -e

kvantummanager --set Gruvbox
gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Material-Dark'
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
declare -A gsettings_keys=(
  ["org.virt-manager.virt-manager.new-vm firmware"]="uefi"
  ["org.virt-manager.virt-manager.new-vm cpu-default"]="host-passthrough"
  ["org.virt-manager.virt-manager.new-vm graphics-type"]="spice"
  ["org.virt-manager.virt-manager.new-vm machine-type "]="q35"
)

for key in "${!gsettings_keys[@]}"; do
  schema="${key% *}"
  subkey="${key#* }"
  value="${gsettings_keys[$key]}"

  if gsettings describe "$schema" "$subkey" >/dev/null; then
    gsettings set "$schema" "$subkey" "$value"
  fi
done

echo -n "/home/$USER/Documents/projects/default/dotfiles/ublock.txt" | wl-copy
gh auth login
dir=$(echo ~/.mozilla/firefox/*.default-esr)
ln -sf ~/Documents/projects/default/dotfiles/user.js "$dir/user.js"
cp -f ~/Documents/projects/default/dotfiles/book* "$dir/bookmarkbackups/"

flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark