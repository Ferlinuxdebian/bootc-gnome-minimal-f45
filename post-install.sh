#!/bin/bash
set -euo pipefail

MARKER="/var/lib/flatpak-bootstrap.done"
TARGET_USER="fernando"

[ -f "$MARKER" ] && exit 0

flatpak remote-delete --force fedora 2>/dev/null || true

run_as_user() {
    runuser -l "$TARGET_USER" -c "$1"
}

run_as_user "flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"

apps=(
be.alexandervanhee.gradia
ca.desrt.dconf-editor
com.borgbase.Vorta
com.brave.Browser
com.dec05eba.gpu_screen_recorder
com.github.dynobo.normcap
com.github.finefindus.eyedropper
com.github.tchx84.Flatseal
com.mattjakeman.ExtensionManager
com.obsproject.Studio
com.protonvpn.www
com.spotify.Client
fr.handbrake.ghb
im.riot.Riot
io.github.fabrialberio.pinapp
io.github.flattool.Ignition
io.github.flattool.Warehouse
io.github.giantpinkrobots.varia
io.gitlab.news_flash.NewsFlash
io.mpv.Mpv
io.typora.Typora
net.nokyan.Resources
org.deluge_torrent.deluge
org.gimp.GIMP
org.gnome.Calculator
org.gnome.Loupe
org.gnome.Papers
org.gnome.Showtime
org.gnome.meld
org.libreoffice.LibreOffice
org.localsend.localsend_app
org.mozilla.firefox
org.shotcut.Shotcut
org.telegram.desktop
org.upscayl.Upscayl
org.videolan.VLC
org.virt_manager.virt-manager
page.codeberg.libre_menu_editor.LibreMenuEditor
page.tesk.Refine
xyz.tytanium.DoorKnocker
)

installed=$(run_as_user "flatpak list --user --app --columns=application")

failed=0
for app in "${apps[@]}"; do
    grep -qx "$app" <<< "$installed" && continue
    echo "Instalando $app"
    run_as_user "flatpak install --user -y --noninteractive flathub $app" || {
        echo "Falha: $app" >&2
        failed=1
    }
done

[ "$failed" -eq 0 ] && touch "$MARKER"
exit "$failed"