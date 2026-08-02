{ appimageTools
, fetchurl
, lib
, makeDesktopItem
, symlinkJoin
, copyDesktopItems
, gamemode
, gst_all_1
, gtk3
, libnotify
, librsvg
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

    extraPkgs = pkgs: with pkgs; [
      gtk3
      fuse
      librsvg
      libnotify
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav
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
  nativeBuildInputs = [ copyDesktopItems ];
  desktopItems = [ desktopItem ];
  postBuild = ''
    mkdir -p $out/share/applications
    cp ${desktopItem}/share/applications/*.desktop $out/share/applications/
  '';

  meta = {
    description = "Unofficial Linux port of the Kyber mod launcher for Star Wars Battlefront II";
    homepage = "https://github.com/simonlinuxcraft/kyber-linuxport-unofficial";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kyber-linuxport-unofficial";
  };
}
