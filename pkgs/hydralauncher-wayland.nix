{ runCommand, makeWrapper, hydralauncher }:

# Hydra Launcher ships as an AppImage with its own bundled Electron, so it
# never goes through the nixpkgs electron wrapper and ignores NIXOS_OZONE_WL.
# Two things have to be fixed for it to work under niri:
#
#   1. --ozone-platform-hint=auto is NOT honoured by this Electron build; it
#      silently picks X11 and runs through XWayland. Only the explicit
#      --ozone-platform=wayland actually selects the Wayland backend.
#   2. On Wayland the AppImage's *bundled* Mesa libEGL cannot drive the NVIDIA
#      card ("pci id 10de:2684, driver (null)" -> "failed to create dri2
#      screen"), the GPU process dies at init and the window paints solid
#      white/black. GLVND has to be pointed at the NVIDIA ICD explicitly:
#      pointing it at the whole egl_vendor.d dir is not enough, since Mesa's
#      50_mesa.json still wins and fails the same way.
#
# The .desktop entry is repointed at the wrapper so rofi launches the wrapped
# binary rather than the bare one.
runCommand "hydralauncher-wayland-${hydralauncher.version}"
{
  nativeBuildInputs = [ makeWrapper ];
  inherit (hydralauncher) meta;
}
  ''
    mkdir -p $out/bin $out/share/applications
    ln -s ${hydralauncher}/share/icons $out/share/icons

    # --no-sandbox: the FHS/bubblewrap env the AppImage runs in cannot use
    # Electron's SUID sandbox (upstream's own .desktop passes it too).
    makeWrapper ${hydralauncher}/bin/hydralauncher $out/bin/hydralauncher \
      --add-flags "--no-sandbox" \
      --run 'nvidia_icd=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
             if [ -n "''${WAYLAND_DISPLAY-}" ]; then
               set -- --ozone-platform=wayland \
                      --enable-features=WaylandWindowDecorations "$@"
               [ -e "$nvidia_icd" ] && export __EGL_VENDOR_LIBRARY_FILENAMES="$nvidia_icd"
             fi'

    substitute ${hydralauncher}/share/applications/hydralauncher.desktop \
      $out/share/applications/hydralauncher.desktop \
      --replace-fail '${hydralauncher}/bin/hydralauncher --no-sandbox' \
                     "$out/bin/hydralauncher"
  ''
