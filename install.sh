#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

# Which type of install?
# First choice: vm or hardware
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

# Which type of packages?
# Main package selection
case "$hardware" in
vm)
  sed -n '1p;3p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
  ;;
hardware)
  # For hardware:max, we will add lines 5 and/or 6 later based on $extra
  sed -n '1,4p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
  ;;
esac

# For hardware:max, add lines 5 and/or 6 based on $extra
if [[ "$hardware" == "hardware" ]]; then
  case "$extra" in
  laptop)
    # Add both line 5 and 6
    sed -n '5,6p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
    ;;
  bluetooth)
    # Add only line 5
    sed -n '5p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
    ;;
  none)
    # Do not add line 5 or 6
    ;;
  esac
fi

# Install stuff
# dnf mirror
tee -a /etc/dnf/dnf.conf <<EOF
fastestmirror=True
deltarpm=True
gpgcheck=True
EOF
dnf clean all
dnf makecache
dnf upgrade --refresh
## Adding repos
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm
dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm
dnf -y copr enable erizur/firefox-esr
dnf makecache

dnf config-manager setopt fedora-cisco-openh264.enabled=0 # cuz fuck cisco
xargs dnf install -y <pkglist.txt

cat <<'EOF' >/etc/tlp.d/01-custom.conf
# Custom TLP overrides for Fedora laptop
# Focus: USB stability, AC performance, audio stability, and radio power management

# -------------------------
# USB Power Management
# -------------------------
USB_AUTOSUSPEND=1
USB_EXCLUDE_PHONE=1
USB_EXCLUDE_BTUSB=1
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
DEVICES_TO_DISABLE_ON_BAT="bluetooth wwan"
DEVICES_TO_ENABLE_ON_BAT=""

DEVICES_TO_DISABLE_ON_AC=""
DEVICES_TO_ENABLE_ON_AC=""

DEVICES_TO_DISABLE_ON_LAN_CONNECT="wifi"
DEVICES_TO_DISABLE_ON_WIFI_CONNECT="wwan"
EOF

# Reload TLP to apply changes
systemctl restart tlp

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

# Kernel parameter to encourage pstate driver mode on next boot (set only when pstate is supported)
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

# Sudo Configuration
echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/wheel
echo "Defaults pwfeedback" >/etc/sudoers.d/pwfeedback
echo 'Defaults env_keep += "SYSTEMD_EDITOR XDG_RUNTIME_DIR WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS WAYLAND_SOCKET"' >/etc/sudoers.d/wayland
chmod 440 /etc/sudoers.d/*
# User setup
usermod -aG wheel,video,audio,docker piyush
if [[ "$hardware" == "hardware" ]]; then
  usermod -aG kvm,libvirt,lp piyush
fi

# firewalld setup
firewall-cmd --permanent --zone=home --add-source=192.168.0.0/24
# firewall-cmd --permanent --zone=home --remove-service=mdns
firewall-cmd --permanent --zone=public --remove-service=ssh
firewall-cmd --permanent --zone=public --remove-service=cups
firewall-cmd --permanent --zone=public --remove-service=mdns
firewall-cmd --permanent --zone=public --remove-port=631/tcp
firewall-cmd --permanent --zone=libvirt --add-interface=virbr0
firewall-cmd --permanent --zone=libvirt --add-service=dhcp
firewall-cmd --permanent --zone=libvirt --add-service=dns
firewall-cmd --permanent --zone=libvirt --add-masquerade
firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/tcp
firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/udp
firewall-cmd --permanent --zone=FedoraServer --remove-service=ssh
firewall-cmd --permanent --zone=FedoraWorkstation --remove-service=ssh
firewall-cmd --permanent --zone=dmz --remove-service=ssh
firewall-cmd --permanent --zone=external --remove-service=ssh
firewall-cmd --permanent --zone=internal --remove-service=ssh
firewall-cmd --permanent --zone=nm-shared --remove-service=ssh
firewall-cmd --permanent --zone=work --remove-service=ssh
firewall-cmd --permanent --zone=work --remove-service=ssh
firewall-cmd --permanent --zone=work --remove-service=mdns
firewall-cmd --set-log-denied=all
# firewall-cmd --permanent --remove-service=dhcpv6-client
firewall-cmd --reload
systemctl enable firewalld
# Bind dnsmasq to virbr0 only
sed -i -E 's/^#?\s*interface=.*/interface=virbr0/; s/^#?\s*bind-interfaces.*/bind-interfaces/' /etc/dnsmasq.conf

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
sysctl --system

flatpak --system remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak --system install -y org.gtk.Gtk3theme.Adwaita-dark
systemctl start docker.service
su - piyush -c '
  mkdir -p ~/Downloads ~/Desktop ~/Public ~/Templates ~/Videos ~/Pictures/Screenshots/temp ~/.config
  mkdir -p ~/Documents/personal/default ~/Documents/projects ~/Documents/personal/wiki
  mkdir -p ~/.local/bin ~/.cache/cargo-target ~/.local/state/bash ~/.local/state/zsh ~/.local/share/wineprefixes
  touch ~/.local/state/bash/history ~/.local/state/zsh/history

  echo todo.txt > ~/Documents/personal/wiki/index.txt
  echo 1. Write some todos > ~/Documents/personal/wiki/todo.txt
  echo "if [ -z \"\$WAYLAND_DISPLAY\" ] && [ \"\$(tty)\" = \"/dev/tty1\" ]; then
    exec sway
  fi" >> ~/.bash_profile

  git clone https://github.com/zedonix/scripts.git ~/Documents/personal/default/scripts
  git clone https://github.com/zedonix/dotfiles.git ~/Documents/personal/default/dotfiles
  git clone https://github.com/zedonix/fedsetup.git ~/Documents/personal/default/fedsetup
  git clone https://github.com/zedonix/notes.git ~/Documents/personal/default/notes
  git clone https://github.com/zedonix/GruvboxTheme.git ~/Documents/personal/default/GruvboxTheme

  cp ~/Documents/personal/default/dotfiles/.config/sway/archLogo.png ~/Pictures/
  cp ~/Documents/personal/default/dotfiles/.config/sway/debLogo.png ~/Pictures/
  cp ~/Documents/personal/default/dotfiles/pics/* ~/Pictures/
  ln -sf ~/Documents/personal/default/dotfiles/.bashrc ~/.bashrc
  ln -sf ~/Documents/personal/default/dotfiles/.zshrc ~/.zshrc
  ln -sf ~/Documents/personal/default/dotfiles/.XCompose ~/.XCompose

  for link in ~/Documents/personal/default/dotfiles/.config/*; do
    ln -sf $link ~/.config/
  done
  for link in ~/Documents/personal/default/dotfiles/copy/*; do
    cp -r $link ~/.config/
  done
  for link in ~/Documents/personal/default/scripts/bin/*; do
    ln -sf $link ~/.local/bin/
  done
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
  zoxide add /home/piyush/Documents/personal/default/debsetup
  source ~/.bashrc

  # Iosevka
  mkdir -p ~/.local/share/fonts/iosevka
  cd ~/.local/share/fonts/iosevka
  curl -LO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/IosevkaTerm.zip
  unzip IosevkaTerm.zip
  rm IosevkaTerm.zip

  rustup-init -y
  docker create --name omni-tools --restart no -p 1024:80 iib0011/omni-tools:latest
  docker create --name bentopdf --restart no -p 1025:8080 bentopdf/bentopdf:latest
  docker create --name convertx --restart no -p 1026:3000 -v ./data:/app/data ghcr.io/c4illin/convertx
'
rm /usr/share/fonts/google-noto-color-emoji-fonts/Noto-COLRv1.ttf
wget https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf -O /usr/share/fonts/google-noto-color-emoji-fonts/NotoColorEmoji.ttf

# Root dots
mkdir -p ~/.config ~/.local/state/bash ~/.local/state/zsh
echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >~/.bash_profile
touch ~/.local/state/zsh/history ~/.local/state/bash/history
ln -sf /home/piyush/Documents/personal/default/dotfiles/nix.conf /etc/nix/nix.conf
ln -sf /home/piyush/Documents/personal/default/dotfiles/.bashrc ~/.bashrc
ln -sf /home/piyush/Documents/personal/default/dotfiles/.zshrc ~/.zshrc
ln -sf /home/piyush/Documents/personal/default/dotfiles/.config/starship.toml ~/.config
ln -sf /home/piyush/Documents/personal/default/dotfiles/.config/nvim/ ~/.config

systemctl restart nix-daemon

sudo -iu piyush nix profile add \
  nixpkgs#hyprpicker \
  nixpkgs#bemoji \
  nixpkgs#lazydocker \
  nixpkgs#upscaler \
  nixpkgs#cliphist \
  nixpkgs#wl-clip-persist \
  nixpkgs#onlyoffice-desktopeditors \
  nixpkgs#networkmanager_dmenu \
  nixpkgs#newsraft \
  nixpkgs#swappy \
  nixpkgs#caligula \
  nixpkgs#opencode \
  nixpkgs#javaPackages.compiler.temurin-bin.jre-17 \
  nixpkgs#poweralertd
# nix build nixpkgs#opencode --no-link --no-substitute

nix profile add nixpkgs#yazi nixpkgs#starship nixpkgs#eza

git clone --depth 1 https://gitlab.com/ananicy-cpp/ananicy-cpp.git
cd ananicy-cpp
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_SYSTEMD=ON -DUSE_BPF_PROC_IMPL=ON -DWITH_BPF=ON
cmake --build build --target ananicy-cpp
cmake --install build --component Runtime

# Setup gruvbox theme
THEME_SRC="/home/piyush/Documents/personal/default/GruvboxTheme"
THEME_DEST="/usr/share/Kvantum/Gruvbox"
mkdir -p "$THEME_DEST"
cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig"
cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg"

THEME_DEST="/usr/share"
cp -r "$THEME_SRC/themes/Gruvbox-Material-Dark" "$THEME_DEST/themes"
cp -r "$THEME_SRC/icons/Gruvbox-Material-Dark" "$THEME_DEST/icons"

# Anancy-cpp rules
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

# Firefox policy
mkdir -p /etc/firefox/policies
ln -sf "/home/piyush/Documents/personal/default/dotfiles/policies.json" /etc/firefox/policies/policies.json

# zram config
# Get total memory in MiB
TOTAL_MEM=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
ZRAM_SIZE=$((TOTAL_MEM / 2))

# Create zram config
mkdir -p /etc/systemd/zram-generator.conf.d
{
  echo "[zram0]"
  echo "zram-size = ${ZRAM_SIZE}"
  echo "compression-algorithm = zstd"
  echo "swap-priority = 100"
  echo "fs-type = swap"
} >/etc/systemd/zram-generator.conf.d/00-zram.conf

# Services
# rfkill unblock bluetooth
# modprobe btusb || true
if [[ "$hardware" == "hardware" ]]; then
  systemctl enable fstrim.timer acpid libvirtd.socket cups ipp-usb docker.socket
  systemctl disable dnsmasq
fi
if [[ "$extra" == "laptop" || "$extra" == "bluetooth" ]]; then
  systemctl enable bluetooth
fi
if [[ "$extra" == "laptop" ]]; then
  systemctl enable tlp
fi
systemctl enable NetworkManager NetworkManager-dispatcher ananicy-cpp
systemctl mask systemd-rfkill systemd-rfkill.socket
systemctl disable NetworkManager-wait-online.service

# cleanup
dnf remove -y plymouth cmake make gcc-c++ systemd-devel libbpf-devel elfutils-libelf-devel clang llvm kernel-headers bpftool
