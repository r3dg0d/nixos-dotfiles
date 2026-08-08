{ lib
, appimageTools
, fetchurl
, makeWrapper
, runCommand
, desktop-file-utils
}:

# Helium — a privacy-focused Chromium fork (github.com/imputnet/helium-linux),
# shipped only as an AppImage. Not in nixpkgs, so it is vendored here.
#
# Two layers:
#   1. appimageTools.wrapType2 unpacks the image and runs it inside an FHS
#      sandbox, which is what makes a distro-agnostic binary work on NixOS.
#   2. a wrapper on top of that fixes rendering under niri — the same two
#      problems the Hydra Launcher AppImage has, for the same reason: the
#      bundled browser never passes through a nixpkgs wrapper, so NIXOS_OZONE_WL
#      does nothing for it. See pkgs/hydralauncher-wayland.nix.
#
# Note it is *not* run with --no-sandbox. Chromium's namespace sandbox works
# inside the FHS env here, and turning the sandbox off in the browser that
# renders untrusted code all day would be a poor trade for a launch flag.

let
  pname = "helium";
  version = "0.15.2.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-Sn3MWsvqZw5YUYVKrEkJLW1gFQ1Sr+whEsCiFxYNvgg=";
  };

  # The unpacked image, for the .desktop entry and the icon.
  contents = appimageTools.extractType2 { inherit pname version src; };

  fhs = appimageTools.wrapType2 {
    inherit pname version src;
    # Everything Chromium needs beyond appimageTools' Steam-chroot baseline:
    # glvnd so __EGL_VENDOR_LIBRARY_FILENAMES below is honoured at all, and
    # libnotify for web notifications.
    extraPkgs = pkgs: with pkgs; [ libglvnd libnotify ];
  };
in
runCommand "${pname}-${version}"
{
  # desktop-file-validate runs at build time so a broken launcher entry fails
  # the build instead of silently not showing up in rofi.
  nativeBuildInputs = [ makeWrapper desktop-file-utils ];

  meta = {
    description = "Private, fast, and honest web browser — a Chromium fork";
    homepage = "https://helium.computer";
    downloadPage = "https://github.com/imputnet/helium-linux/releases";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "helium";
  };
}
  ''
    mkdir -p $out/bin $out/share/applications

    # 1. --ozone-platform-hint=auto is not enough for a bundled Chromium; it
    #    picks X11 and goes through XWayland. Only the explicit
    #    --ozone-platform=wayland selects the Wayland backend.
    # 2. On Wayland the bundled EGL cannot drive the NVIDIA card, the GPU
    #    process dies at init, and the window paints solid white. GLVND has to
    #    be pointed at the NVIDIA ICD *by filename* — naming the whole
    #    egl_vendor.d directory is not enough, Mesa's 50_mesa.json still wins.
    # Both are guarded on WAYLAND_DISPLAY so an X11 session still works.
    makeWrapper ${fhs}/bin/helium $out/bin/helium \
      --run 'nvidia_icd=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
             if [ -n "''${WAYLAND_DISPLAY-}" ]; then
               set -- --ozone-platform=wayland \
                      --enable-features=WaylandWindowDecorations "$@"
               [ -e "$nvidia_icd" ] && export __EGL_VENDOR_LIBRARY_FILENAMES="$nvidia_icd"
             fi'

    install -Dm444 ${contents}/usr/share/icons/hicolor/256x256/apps/helium.png \
      $out/share/icons/hicolor/256x256/apps/helium.png

    # Repoint every Exec= — the main entry and both desktop actions — at the
    # wrapper, or the launcher runs the bare FHS binary and none of the above
    # applies. No StartupWMClass is needed: the window's Wayland app_id is
    # already "helium", which matches this file's basename.
    substitute ${contents}/helium.desktop $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
    desktop-file-validate $out/share/applications/helium.desktop
  ''
