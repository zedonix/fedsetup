#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

echo "Choose one:"
select hardware in "vm" "hardware"; do
  [[ -n $hardware ]] && break
  echo "Invalid choice. Please select 1 for vm or 2 for hardware."
done

if [[ "$hardware" == "hardware" ]]; then
  echo "Choose one:"
  select extra in "laptop" "bluetooth" "none"; do
    [[ -n $extra ]] && break
    echo "Invalid choice."
  done
else
  extra="none"
fi

case "$hardware" in
vm)
  sed -n '1p;3p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
  ;;
hardware)
  sed -n '1,4p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
  ;;
esac

if [[ "$hardware" == "hardware" ]]; then
  case "$extra" in
  laptop)
    sed -n '5,6p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
    ;;
  bluetooth)
    sed -n '5p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
    ;;
  none) ;;
  esac
fi

tee -a /etc/dnf/dnf.conf <<EOF
fastestmirror=True
deltarpm=True
gpgcheck=True

[fedora-cisco-openh264]
enabled=0
EOF
tee /etc/yum.repos.d/adoptium.repo >/dev/null <<'EOF'
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF
tee /etc/yum.repos.d/wayscriber.repo >/dev/null <<'EOF'
[wayscriber]
name=Wayscriber Repo
baseurl=https://wayscriber.com/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://wayscriber.com/rpm/RPM-GPG-KEY-wayscriber.asc
EOF
# dnf config-manager setopt fedora-cisco-openh264.enabled=0 # cuz fuck cisco
dnf upgrade -y --refresh
dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm
dnf makecache --enablerepo=Adoptium,wayscriber

dnf copr enable -y \
  erizur/firefox-esr \
  solopasha/hyprland

xargs dnf install -y <pkglist.txt
dnf clean all
dnf makecache

if [[ "$extra" == "laptop" ]]; then
  cat <<'EOF' >/etc/tlp.d/01-custom.conf
# -------------------------
# USB Power Management
# -------------------------
USB_AUTOSUSPEND=1
USB_EXCLUDE_PHONE=1
# Allow TLP to touch Bluetooth
USB_EXCLUDE_BTUSB=0
USB_EXCLUDE_WWAN=1
USB_EXCLUDE_AUDIO=1
USB_EXCLUDE_PRINTER=1

# -------------------------
# PCIe / Runtime Power Management
# -------------------------
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_DENYLIST="amdgpu nouveau nvidia"

# -------------------------
# AHCI / SATA
# -------------------------
AHCI_RUNTIME_PM_ON_AC=auto
AHCI_RUNTIME_PM_ON_BAT=auto
AHCI_RUNTIME_PM_TIMEOUT=15
SATA_LINKPWR_ON_AC="max_performance"
SATA_LINKPWR_ON_BAT="med_power_with_dipm"

# -------------------------
# Sound / Audio
# -------------------------
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=0
SOUND_POWER_SAVE_CONTROLLER=N

# -------------------------
# Wi-Fi
# -------------------------
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off

# -------------------------
# Radio Device Wizard (RDW)
# -------------------------
DEVICES_TO_DISABLE_ON_BAT="bluetooth wwan nfc"
DEVICES_TO_DISABLE_ON_STARTUP="bluetooth"
DEVICES_TO_ENABLE_ON_BAT=""

DEVICES_TO_DISABLE_ON_AC=""
DEVICES_TO_ENABLE_ON_AC=""

DEVICES_TO_DISABLE_ON_LAN_CONNECT="wifi"
DEVICES_TO_DISABLE_ON_WIFI_CONNECT="wwan"
EOF
fi

scaling_f="/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
pstate_supported=false
driver=""
if [ -d /sys/devices/system/cpu/intel_pstate ]; then
  driver="intel_pstate"
  pstate_supported=true
elif [ -d /sys/devices/system/cpu/amd_pstate ] || [ -d /sys/devices/system/cpu/amd-pstate ]; then
  # kernel docs and kernels may expose amd_pstate/amd-pstate; accept either
  driver="amd_pstate"
  pstate_supported=true
elif [ -r "$scaling_f" ]; then
  # fallback: read scaling_driver and normalise
  rawdrv=$(cat "$scaling_f" 2>/dev/null || true)
  case "$rawdrv" in
  *intel*)
    driver="intel_pstate"
    pstate_supported=true
    ;;
  *amd*)
    driver="amd_pstate"
    pstate_supported=true
    ;;
  *) driver="$rawdrv" ;;
  esac
fi

pstate_param=""
if [ "$pstate_supported" = true ]; then
  if [ "$driver" = "intel_pstate" ]; then
    pstate_param="intel_pstate=active"
  elif [ "$driver" = "amd_pstate" ]; then
    pstate_param="amd_pstate=active"
  fi
fi

dracut --force
extra_params="fsck.repair=yes zswap.enabled=0"
if [ -n "$pstate_param" ]; then
  all_params="$pstate_param $extra_params"
else
  all_params="$extra_params"
fi
sed -i 's/[[:space:]]*\b\(rhgb\|quiet\)\b[[:space:]]*/ /g' /etc/default/grub
sed -i "s/^\(GRUB_CMDLINE_LINUX=\"[^\"]*\)/\1 $all_params/" /etc/default/grub
sed -i 's/^#GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >>/etc/default/grub
echo "GRUB_GFXMODE=text" >>/etc/default/grub
echo "GRUB_GFXPAYLOAD_LINUX=text" >>/etc/default/grub
echo "GRUB_SAVEDEFAULT=true" >>/etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/wheel
echo "Defaults pwfeedback" >/etc/sudoers.d/pwfeedback
echo 'Defaults env_keep += "SYSTEMD_EDITOR XDG_RUNTIME_DIR WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS WAYLAND_SOCKET"' >/etc/sudoers.d/wayland
chmod 440 /etc/sudoers.d/*
usermod -aG video,audio,docker piyush
if [[ "$hardware" == "hardware" ]]; then
  usermod -aG kvm,libvirt,lp piyush
  chown root:libvirt /var/lib/libvirt/images
  chmod 2775 /var/lib/libvirt/images
fi

firewall-cmd --permanent --zone=home --add-source=192.168.0.0/24
# firewall-cmd --permanent --zone=home --remove-service=mdns
# firewall-cmd --permanent --zone=public --remove-service=ssh
# firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/24" service name="ssh" accept'
# firewall-cmd --permanent --zone=public --remove-service=cups
firewall-cmd --permanent --zone=public --remove-service=mdns
# firewall-cmd --permanent --zone=public --remove-port=631/tcp
if [[ "$hardware" == "hardware" ]]; then
  firewall-cmd --permanent --zone=libvirt --add-interface=virbr0
  firewall-cmd --permanent --zone=libvirt --add-service=dhcp
  firewall-cmd --permanent --zone=libvirt --add-service=dns
  firewall-cmd --permanent --zone=libvirt --add-masquerade
fi
firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/tcp
firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/udp
# firewall-cmd --permanent --zone=FedoraServer --remove-service=ssh
# firewall-cmd --permanent --zone=FedoraWorkstation --remove-service=ssh
# firewall-cmd --permanent --zone=dmz --remove-service=ssh
# firewall-cmd --permanent --zone=external --remove-service=ssh
# firewall-cmd --permanent --zone=internal --remove-service=ssh
# firewall-cmd --permanent --zone=nm-shared --remove-service=ssh
# firewall-cmd --permanent --zone=work --remove-service=ssh
# firewall-cmd --permanent --zone=work --remove-service=ssh
firewall-cmd --permanent --zone=work --remove-service=mdns
# firewall-cmd --set-log-denied=all
# firewall-cmd --permanent --remove-service=dhcpv6-client

# Bind dnsmasq to virbr0 only
if [[ "$hardware" == "hardware" ]]; then
  sed -i -E 's/^#?\s*interface=.*/interface=virbr0/; s/^#?\s*bind-interfaces.*/bind-interfaces/' /etc/dnsmasq.conf
fi
echo 'ListenAddress 127.0.0.1' >>/etc/ssh/sshd_config

# disable llmnr
mkdir -p /etc/systemd/resolved.conf.d
tee /etc/systemd/resolved.conf.d/disable-llmnr.conf >/dev/null <<'EOF'
[Resolve]
LLMNR=no
EOF

tee /etc/sysctl.d/99-hardening.conf >/dev/null <<'EOF'
# networking
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Enable IP forwarding for NAT
# net.ipv4.ip_forward = 1

# kernel hardening
kernel.kptr_restrict = 2

# file protections
fs.protected_fifos = 2

# bpf jit harden (if present)
net.core.bpf_jit_harden = 2
EOF

flatpak --system remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak --system install -y org.gtk.Gtk3theme.Adwaita-dark
su - piyush -c 'bash -s' <<'EOF'
  mkdir -p ~/Downloads ~/Desktop ~/Public ~/Templates ~/Videos ~/Pictures/Screenshots/temp ~/.config
  mkdir -p ~/Documents/projects/default ~/Documents/projects ~/Documents/personal/wiki
  mkdir -p ~/.local/bin ~/.cache/cargo-target ~/.local/state/bash ~/.local/state/zsh ~/.local/share/wineprefixes
  touch ~/.local/state/bash/history ~/.local/state/zsh/history

  echo todo.txt > ~/Documents/personal/wiki/index.txt
  echo 1. Write some todos > ~/Documents/personal/wiki/todo.txt
  cat >> ~/.bash_profile <<'BASH'
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec sway
fi
BASH

  git clone https://github.com/zedmakesese/scripts.git ~/Documents/projects/default/scripts
  git clone https://github.com/zedmakesese/dotfiles.git ~/Documents/projects/default/dotfiles
  git clone https://github.com/zedmakesese/fedsetup.git ~/Documents/projects/default/fedsetup
  git clone https://github.com/zedmakesese/notes.git ~/Documents/projects/default/notes
  git clone https://github.com/zedmakesese/GruvboxTheme.git ~/Documents/projects/default/GruvboxTheme

  mkdir -p ~/.local/share/nvim/java-debug
  url=$(curl -fsSL 'https://open-vsx.org/api/vscjava/vscode-java-debug' | grep '"download"' | head -1 | sed -E 's/.*"download": *"([^"]+)".*/\1/')
  file=${url##*/}
  wget -c -O "$file" "$url"
  unzip -o "$file" 'extension/server/com.microsoft.java.debug.plugin-*.jar' -d /tmp
  mv /tmp/extension/server/com.microsoft.java.debug.plugin-*.jar ~/.local/share/nvim/java-debug/
  rm -rf /tmp/extension

  cp ~/Documents/projects/default/dotfiles/.config/sway/archLogo.png ~/Pictures/
  cp ~/Documents/projects/default/dotfiles/.config/sway/debLogo.png ~/Pictures/
  cp ~/Documents/projects/default/dotfiles/pics/* ~/Pictures/
  ln -sf ~/Documents/projects/default/dotfiles/.bashrc ~/.bashrc
  ln -sf ~/Documents/projects/default/dotfiles/.zshrc ~/.zshrc
  ln -sf ~/Documents/projects/default/dotfiles/.XCompose ~/.XCompose

  for link in ~/Documents/projects/default/dotfiles/.config/*; do
    ln -sf "$link" ~/.config/
  done
  for link in ~/Documents/projects/default/dotfiles/copy/*; do
    cp -r "$link" ~/.config/
  done
  for link in ~/Documents/projects/default/scripts/bin/*; do
    ln -sf "$link" ~/.local/bin/
  done
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
  /home/piyush/Documents/projects/default/dotfiles/.config/tmux/plugins/tpm/scripts/install_plugins.sh
  zoxide add /home/piyush/Documents/projects/default/fedsetup
  source ~/.bashrc

  cd ~/.local/share/fonts/iosevka
  mkdir -p ~/.local/share/fonts/iosevka
  curl -LO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/IosevkaTerm.zip
  unzip IosevkaTerm.zip
  rm IosevkaTerm.zip

  rustup-init -y
  cargo install clipvault --locked
  pnpm add -g opencode-ai

  podman create --name omni-tools --restart=no -p 127.0.0.1:1024:80 docker.io/iib0011/omni-tools:latest
  podman create --name bentopdf --restart=no -p 127.0.0.1:1025:8080 docker.io/bentopdf/bentopdf:latest
  podman volume create convertx-data
  podman create --name convertx --restart=no -p 127.0.0.1:1026:3000 -v convertx-data:/app/data:Z ghcr.io/c4illin/convertx
  podman create --name excalidraw --restart=no -p 127.0.0.1:1027:80 docker.io/excalidraw/excalidraw:latest
EOF
rm /usr/share/fonts/google-noto-color-emoji-fonts/Noto-COLRv1.ttf
wget https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf -O /usr/share/fonts/google-noto-color-emoji-fonts/NotoColorEmoji.ttf

mkdir -p ~/.config ~/.local/state/bash ~/.local/state/zsh
echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >~/.bash_profile
touch ~/.local/state/zsh/history ~/.local/state/bash/history
ln -sf /home/piyush/Documents/projects/default/dotfiles/nix.conf /etc/nix/nix.conf
ln -sf /home/piyush/Documents/projects/default/dotfiles/.bashrc ~/.bashrc
ln -sf /home/piyush/Documents/projects/default/dotfiles/.zshrc ~/.zshrc
ln -sf /home/piyush/Documents/projects/default/dotfiles/.config/starship.toml ~/.config
ln -sf /home/piyush/Documents/projects/default/dotfiles/.config/nvim/ ~/.config

nix registry add --registry /etc/nix/registry.json nixpkgs github:NixOS/nixpkgs/nixos-25.11
systemctl restart nix-daemon
sudo -iu piyush nix profile add \
  nixpkgs#bemoji \
  nixpkgs#poweralertd \
  nixpkgs#upscaler \
  nixpkgs#lazydocker \
  nixpkgs#networkmanager_dmenu \
  nixpkgs#wl-clip-persist \
  nixpkgs#caligula \
  nixpkgs#google-java-format \
  nixpkgs#jdt-language-server \
  nixpkgs#checkstyle \
  nixpkgs#lua-language-server \
  nixpkgs#stylua \
  nixpkgs#luajitPackages.luacheck \
  nixpkgs#texlab \
  nixpkgs#python313Packages.debugpy \
  nixpkgs#tex-fmt \
  nixpkgs#markdownlint-cli \
  nixpkgs#htmlhint \
  nixpkgs#eslint_d \
  nixpkgs#stylelint \
  nixpkgs#prettierd \
  nixpkgs#vscode-langservers-extracted \
  nixpkgs#typescript-language-server \
  nixpkgs#typescript-go

nix profile add nixpkgs#yazi nixpkgs#eza

sudo -iu piyush bemoji --download all >/dev/null 2>&1 || true

REPO="jgraph/drawio-desktop"
curl -s "https://api.github.com/repos/$REPO/releases/latest" |
  jq -r '.assets[].browser_download_url' |
  grep -E 'x86_64.*\.rpm$' |
  xargs -n1 wget
dnf install -y ~/fedsetup/*rpm

git clone --depth 1 https://gitlab.com/ananicy-cpp/ananicy-cpp.git
cd ananicy-cpp
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_SYSTEMD=ON -DUSE_BPF_PROC_IMPL=ON -DWITH_BPF=ON
cmake --build build --target ananicy-cpp
cmake --install build --component Runtime

THEME_SRC="/home/piyush/Documents/projects/default/GruvboxTheme"
THEME_DEST="/usr/share/Kvantum/Gruvbox"
mkdir -p "$THEME_DEST"
cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig"
cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg"

THEME_DEST="/usr/share"
cp -r "$THEME_SRC/themes/Gruvbox-Material-Dark" "$THEME_DEST/themes"
cp -r "$THEME_SRC/icons/Gruvbox-Material-Dark" "$THEME_DEST/icons"

git clone --depth=1 https://github.com/RogueScholar/ananicy.git
git clone --depth=1 https://github.com/CachyOS/ananicy-rules.git
mkdir -p /etc/ananicy.d/roguescholar /etc/ananicy.d/zz-cachyos
cp -r ananicy/ananicy.d/* /etc/ananicy.d/roguescholar/
cp -r ananicy-rules/00-default/* /etc/ananicy.d/zz-cachyos/
cp -r ananicy-rules/00-types.types /etc/ananicy.d/zz-cachyos/
cp -r ananicy-rules/00-cgroups.cgroups /etc/ananicy.d/zz-cachyos/
tee /etc/ananicy.d/ananicy.conf >/dev/null <<'EOF'
check_freq = 15
cgroup_load = false
type_load = true
rule_load = true
apply_nice = true
apply_latnice = true
apply_ionice = true
apply_sched = true
apply_oom_score_adj = true
apply_cgroup = true
loglevel = info
log_applied_rule = false
cgroup_realtime_workaround = false
EOF

mkdir -p /etc/firefox/policies
ln -sf "/home/piyush/Documents/projects/default/dotfiles/policies.json" /etc/firefox/policies/policies.json

TOTAL_MEM=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
ZRAM_SIZE=$((TOTAL_MEM / 2))

mkdir -p /etc/systemd/zram-generator.conf.d
{
  echo "[zram0]"
  echo "zram-size = ${ZRAM_SIZE}"
  echo "compression-algorithm = zstd"
  echo "swap-priority = 100"
  echo "fs-type = swap"
} >/etc/systemd/zram-generator.conf.d/00-zram.conf

# rfkill unblock bluetooth
# modprobe btusb || true
if [[ "$hardware" == "hardware" ]]; then
  systemctl enable fstrim.timer acpid libvirtd.socket cups ipp-usb docker.socket
  systemctl disable dnsmasq
fi
# if [[ "$extra" == "laptop" || "$extra" == "bluetooth" ]]; then
#   systemctl enable bluetooth
# fi
if [[ "$extra" == "laptop" ]]; then
  systemctl enable tlp
fi
systemctl enable NetworkManager NetworkManager-dispatcher ananicy-cpp nix-daemon firewalld
systemctl mask systemd-rfkill systemd-rfkill.socket
systemctl disable NetworkManager-wait-online.service acpid acpid.socket
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandlePowerKey=ignore\n' >/etc/systemd/logind.conf.d/90-ignore-power.conf
# HandlePowerKeyLongPress

dnf remove -y plymouth libbpf-devel elfutils-libelf-devel bpftool lzip
