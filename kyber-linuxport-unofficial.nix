{ appimageTools
, fetchurl
, lib
, makeDesktopItem
, symlinkJoin
, copyDesktopItems
, makeWrapper
, gamemode
, gnutls
, gst_all_1
, gtk3
, libnotify
, librsvg
, nettle
, wayland
, xdg-utils
, zenity
}:

let
  pname = "kyber-linuxport-unofficial";
  version = "0.1.0-beta.6.4.11";

  src = fetchurl {
    url = "https://github.com/simonlinuxcraft/kyber-linuxport-unofficial/releases/download/v${version}/KyberLinuxPort-x86_64.AppImage";
    hash = "sha256-R/gE2zlLdw+TvzOHzaI0fD3dijsfVWgs/R8k8ES9gIA=";
  };

  appimage = appimageTools.wrapType2 {
    inherit pname version src;

    extraBwrapArgs = [
      ''--setenv DISPLAY "$DISPLAY"''
      ''--setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"''
      ''--setenv DBUS_SESSION_BUS_ADDRESS "$DBUS_SESSION_BUS_ADDRESS"''
      ''--ro-bind-try "$XDG_RUNTIME_DIR/bus" "$XDG_RUNTIME_DIR/bus"''
      ''--ro-bind-try "/tmp/.X11-unix/X''${DISPLAY#:}" "/tmp/.X11-unix/X''${DISPLAY#:}"''
    ];

    extraPkgs = pkgs: with pkgs; [
      gtk3
      fuse
      gnutls
      librsvg
      libnotify
      nettle
      wayland
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav
      xdg-utils
      zenity
      gamemode
    ];
  };

  desktopItem = makeDesktopItem {
    name = "kyber-linuxport-unofficial";
    desktopName = "Kyber Linux Port";
    comment = "Unofficial Linux port of the Kyber launcher for Star Wars Battlefront II";
    exec = "kyber-linuxport-unofficial";
    categories = [ "Game" ];
  };
in
symlinkJoin {
  inherit pname version;
  paths = [ appimage ];
  nativeBuildInputs = [ copyDesktopItems makeWrapper ];
  desktopItems = [ desktopItem ];
  postBuild = ''
    rm $out/bin/kyber-linuxport-unofficial
    makeWrapper ${appimage}/bin/kyber-linuxport-unofficial $out/bin/kyber-linuxport-unofficial \
      --run 'mkdir -p "''${XDG_CONFIG_HOME:-$HOME/.config}/kyber-linuxport"
             printf "%s\n" x11 > "''${XDG_CONFIG_HOME:-$HOME/.config}/kyber-linuxport/backend"' \
      --set GDK_BACKEND x11 \
      --set GTK_IM_MODULE gtk-im-context-simple \
      --set NIXOS_OZONE_WL 1 \
      --set MOZ_ENABLE_WAYLAND 1

    mkdir -p $out/share/applications
    cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
    substituteInPlace $out/share/applications/kyber-linuxport-unofficial.desktop \
      --replace-fail 'Exec=kyber-linuxport-unofficial' "Exec=$out/bin/kyber-linuxport-unofficial"
  '';

  meta = {
    description = "Unofficial Linux port of the Kyber mod launcher for Star Wars Battlefront II";
    homepage = "https://github.com/simonlinuxcraft/kyber-linuxport-unofficial";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kyber-linuxport-unofficial";
  };
}
