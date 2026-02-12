#!/usr/bin/env bash
set -e

kvantummanager --set Gruvbox
gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Material-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

schema="org.virt-manager.virt-manager.new-vm"

if gsettings list-schemas | grep -qx "$schema"; then
  gsettings set $schema firmware 'uefi'
  gsettings set $schema cpu-default 'host-passthrough'
  gsettings set $schema graphics-type 'spice'
  gsettings set $schema machine-type 'q35'
fi

gh auth login
echo -n "/home/$USER/Documents/projects/default/dotfiles/ublock.txt" | wl-copy
dir=$(echo ~/.mozilla/firefox/*.default-esr)
ln -sf ~/Documents/projects/default/dotfiles/user.js "$dir/user.js"
cp -f ~/Documents/projects/default/dotfiles/book* "$dir/bookmarkbackups/"

flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark