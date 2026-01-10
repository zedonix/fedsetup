#!/usr/bin/env bash
set -e

echo "Choose one:"
select hardware in "vm" "hardware"; do
  [[ -n $hardware ]] && break
  echo "Invalid choice. Please select 1 for vm or 2 for hardware."
done

# extra choice: laptop or bluetooth or none
if [[ "$hardware" == "hardware" ]]; then
  echo "Choose one:"
  select extra in "laptop" "bluetooth" "none"; do
    [[ -n $extra ]] && break
    echo "Invalid choice."
  done
else
  extra="none"
fi

kvantummanager --set Gruvbox
gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Material-Dark'
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
declare -A gsettings_keys=(
  ["org.virt-manager.virt-manager.new-vm firmware"]="uefi"
  ["org.virt-manager.virt-manager.new-vm cpu-default"]="host-passthrough"
  ["org.virt-manager.virt-manager.new-vm graphics-type"]="spice"
)

for key in "${!gsettings_keys[@]}"; do
  schema="${key% *}"
  subkey="${key#* }"
  value="${gsettings_keys[$key]}"

  if gsettings describe "$schema" "$subkey" >/dev/null; then
    gsettings set "$schema" "$subkey" "$value"
  fi
done

# Firefox user.js linking
echo -n "/home/$USER/Documents/projects/default/dotfiles/ublock.txt" | wl-copy
gh auth login
dir=$(echo ~/.mozilla/firefox/*.default-esr)
ln -sf ~/Documents/projects/default/dotfiles/user.js "$dir/user.js"
cp -f ~/Documents/projects/default/dotfiles/book* "$dir/bookmarkbackups/"

# Configure static IP, gateway, and custom DNS
# sudo tee /etc/systemd/resolved.conf <<EOF
# [Resolve]
# DNS=8.8.8.8 8.8.4.4
# EOF
# sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# sudo tee /etc/NetworkManager/conf.d/dns.conf <<EOF
# [main]
# dns=none
# systemd-resolved=false
# EOF
# sudo tee /etc/resolv.conf <<EOF
# nameserver 1.1.1.1
# nameserver 1.0.0.1
# EOF
# sudo systemctl restart NetworkManager

flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark
if [[ "$hardware" == "hardware" ]]; then
  flatpak install -y flathub com.github.wwmm.easyeffects
  # flatpak install -y flathub no.mifi.losslesscut
  # flatpak install -y flathub com.obsproject.Studio
fi
if [[ "$extra" == "laptop" ]]; then
  flatpak install -y flathub com.github.d4nj1.tlpui
  flatpak install -y nl.brixit.powersupply
fi

bemoji --download all &
foot -e nvim +MasonToolsInstall &
foot -e sudo nvim +MasonToolsInstall &
foot -e tmux &

# Libvirt setup
NEW="/home/piyush/Documents/libvirt"
TMP="/tmp/default-pool.xml"

# wrapper so we don't accidentally pass a quoted command string to sudo
virsh_connect() { sudo virsh --connect qemu:///system "$@"; }

if rpm -q libvirt-daemon &>/dev/null; then
  # ensure default network is autostarted if present; ignore errors if already set
  virsh_connect net-autostart default 2>/dev/null || true
  virsh_connect net-start default 2>/dev/null || true

  sudo mkdir -p "$NEW"
  sudo chown -R root:libvirt "$NEW"
  sudo chmod -R 2775 "$NEW"

  # remove any existing pools that point to this path (except keep 'default' for now)
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if virsh_connect pool-dumpxml "$p" 2>/dev/null | grep -q "<path>${NEW}</path>"; then
      if [ "$p" != "default" ]; then
        virsh_connect pool-destroy "$p" || true
        virsh_connect pool-undefine "$p" || true
      fi
    fi
  done < <(virsh_connect pool-list --all --name 2>/dev/null || true)

  # if a 'default' storage pool exists, replace it with our path
  if virsh_connect pool-list --all 2>/dev/null | awk 'NR>2{print $1}' | grep -qx default; then
    virsh_connect pool-destroy default 2>/dev/null || true
    virsh_connect pool-undefine default 2>/dev/null || true
  fi

  # write pool XML with variable expansion
  cat <<EOF | sudo tee "$TMP" >/dev/null
<pool type='dir'>
  <name>default</name>
  <target><path>${NEW}</path></target>
</pool>
EOF

  # define, start, refresh and autostart the pool
  virsh_connect pool-define "$TMP" || true
  virsh_connect pool-build default 2>/dev/null || true
  virsh_connect pool-start default 2>/dev/null || true
  virsh_connect pool-refresh default 2>/dev/null || true
  virsh_connect pool-autostart default 2>/dev/null || true

  # ensure files under NEW/images are world-readable where appropriate
  sudo find "${NEW}" -type d -exec sudo chmod 2775 {} + || true
  sudo find "${NEW}" -type f -exec sudo chmod 0644 {} + || true

  echo "Libvirt pool configured at ${NEW}"
else
  echo "libvirt-daemon not installed; skip configuration" >&2
  exit 1
fi
