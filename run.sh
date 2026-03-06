#!/usr/bin/env bash
set -e

kvantummanager --set Gruvbox
flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark

gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Material-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

schema="org.virt-manager.virt-manager.new-vm"

if gsettings list-schemas | grep -qx "$schema"; then
  gsettings set $schema firmware 'uefi'
  gsettings set $schema cpu-default 'host-passthrough'
  gsettings set $schema graphics-type 'spice'
fi

echo -n "/home/$USER/Documents/projects/default/dotfiles/firefox/ublock.txt" | wl-copy
echo -n "/home/$USER/Documents/projects/default/dotfiles/firefox/stylux-sidebar.css" | wl-copy
dir=$(echo ~/.mozilla/firefox/*.default-release)
ln -sf ~/Documents/projects/default/dotfiles/firefox/user.js "$dir/"
ln -sf ~/Documents/projects/default/dotfiles/firefox/userChrome.css "$dir/chrome/"
cp -f ~/Documents/projects/default/dotfiles/firefox/book* "$dir/bookmarkbackups/"

ya pkg add bennyyip/gruvbox-dark
ya pkg add dedukun/relative-motions
ya pkg add yazi-rs/plugins:full-border
ya pkg add yazi-rs/plugins:smart-paste
ya pkg add yazi-rs/plugins:zoom
ya pkg add yazi-rs/plugins:jump-to-char

gh auth login
