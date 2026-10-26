#!/bin/bash
# Legger Fyrlys i programmenyen for deg (ikke hele maskinen). Kjør den fra Fyrlys-mappen: ./lag-snarvei.sh
# Flytter du mappen, kjører du den igjen.
set -e
dir="$(cd "$(dirname "$0")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data/applications" "$data/icons/hicolor/256x256/apps"
cp "$dir/fyrlys.png" "$data/icons/hicolor/256x256/apps/no.peag.fyrlys.png"
cat > "$data/applications/no.peag.fyrlys.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Fyrlys
Comment=TV, TV-guide, filmer og serier fra IPTV-abonnementet ditt
Exec="$dir/fyrlys"
Icon=no.peag.fyrlys
Terminal=false
Categories=AudioVideo;Video;Player;TV;
StartupWMClass=no.peag.fyrlys
DESKTOP
command -v update-desktop-database > /dev/null && update-desktop-database "$data/applications" > /dev/null 2>&1 || true
echo "Fyrlys ligger nå i programmenyen."
# Fyrlys trenger libmpv (avspilleren) fra systemet
if ! ldconfig -p 2> /dev/null | grep -q 'libmpv\.so\.2'; then
  echo
  echo "Fant ikke libmpv, som Fyrlys bruker til å spille av. Installer den:"
  echo "  Fedora:          sudo dnf install mpv-libs"
  echo "  Ubuntu, Debian:  sudo apt install libmpv2"
  echo "  Arch:            sudo pacman -S mpv"
fi
