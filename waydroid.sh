#!/usr/bin/env bash
sudo waydroid init -c https://ota.waydro.id/system -v https://ota.waydro.id/vendor -s GAPPS
sudo waydroid shell -- sh -c "pm uninstall --user 0 com.google.android.googlequicksearchbox"
curl -fOL --retry 3 --retry-delay 3 "https://github.com/Xtr126/cage-xtmapper/releases/latest/download/cage-xtmapper-v0.2.0.tar"
tar xvf cage-xtmapper-v0.2.0.tar
cd usr/local/bin
install -Dm755 ./cage_xtmapper /usr/local/bin/
install -Dm755 ./cage_xtmapper.sh /usr/local/bin/
sudo XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" waydroid shell -- sh /sdcard/Android/data/xtr.keymapper/files/xtMapper.sh --wayland-client
cd ~/Downloads
REPO="Xtr126/XtMapper"
curl -s "https://api.github.com/repos/$REPO/releases/latest" |
  jq -r '.assets[].browser_download_url' |
  grep -E '\.apk$' |
  xargs -n1 wget
waydroid app install XtMapper-release-v2.4.2.apk
git clone https://github.com/casualsnek/waydroid_script.git
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
venv/bin/python3 main.py install libndk
# venv/bin/python3 main.py install libhoudini
# sudo XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" waydroid shell -- sh /sdcard/Android/data/xtr.keymapper/files/xtMapper.sh --wayland-client
