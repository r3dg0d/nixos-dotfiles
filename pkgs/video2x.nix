{ lib
, appimageTools
, bash
, fetchurl
, makeWrapper
, runCommand
, desktop-file-utils
, shellcheck
}:

# Video2X — machine-learning video upscaler and frame interpolator
# (github.com/k4yt3x/video2x). Upstream ships Linux only as an AppImage, so it
# is vendored here the same way pkgs/helium.nix vendors Helium.
#
# The AppImage bundles its own ffmpeg/ncnn/glslang stack but *not* the Vulkan
# loader, and every backend except libplacebo's CPU path is ncnn-on-Vulkan.
# So two things have to be arranged:
#   1. vulkan-loader goes into the FHS sandbox (extraPkgs below), and
#   2. the loader is pointed at the host ICD by filename — inside the sandbox
#      /usr/share/vulkan/icd.d is the FHS's own empty one, and NixOS keeps the
#      real driver manifests under /run/opengl-driver.
#
# The upstream .desktop is Terminal=true with a bare `Exec=video2x`, which in
# rofi means a terminal that opens and exits before you can read it. It is
# replaced below with an entry that opens ghostty on video2x-launch, a small
# prompt wrapper, so the launcher item is actually usable for a CLI tool.

let
  pname = "video2x";
  version = "6.4.0";

  src = fetchurl {
    url = "https://github.com/k4yt3x/video2x/releases/download/${version}/Video2X-x86_64.AppImage";
    hash = "sha256-gjj8ODJRB/CgihQNBpuu49uAxax0cLClFsxoMYP1+S0=";
  };

  # The unpacked image, for the icon.
  contents = appimageTools.extractType2 { inherit pname version src; };

  fhs = appimageTools.wrapType2 {
    inherit pname version src;
    extraPkgs = pkgs: with pkgs; [ vulkan-loader ];
  };
in
runCommand "${pname}-${version}"
{
  nativeBuildInputs = [ makeWrapper desktop-file-utils shellcheck ];

  meta = {
    description = "Machine-learning video upscaler and frame interpolator";
    longDescription = ''
      A video/GIF/image upscaling and frame interpolation framework built around
      Real-ESRGAN, Real-CUGAN, RIFE and libplacebo, all running on Vulkan via
      ncnn. This is upstream's AppImage build, which is CLI-only — the Qt6 GUI
      is shipped for Windows only.
    '';
    homepage = "https://github.com/k4yt3x/video2x";
    downloadPage = "https://github.com/k4yt3x/video2x/releases";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "video2x";
  };
}
  ''
    mkdir -p $out/bin $out/share/applications

    # Vulkan: name the host ICDs explicitly. VK_DRIVER_FILES is the current
    # spelling, VK_ICD_FILENAMES the pre-1.3.207 one — older loaders ignore the
    # former, so set both. Only exported when a manifest is actually there, so
    # a machine without a GPU driver still gets the loader's normal search.
    makeWrapper ${fhs}/bin/video2x $out/bin/video2x \
      --run 'icds=$(echo /run/opengl-driver/share/vulkan/icd.d/*.json | tr " " ":")
             case "$icds" in
               *"*"*) ;;
               *) export VK_DRIVER_FILES="$icds" VK_ICD_FILENAMES="$icds" ;;
             esac'

    install -Dm444 ${contents}/usr/share/icons/hicolor/256x256/apps/video2x.png \
      $out/share/icons/hicolor/256x256/apps/video2x.png

    substitute ${./video2x-launch} $out/bin/video2x-launch \
      --subst-var-by bash ${bash}/bin/bash \
      --subst-var-by video2x $out/bin/video2x
    chmod +x $out/bin/video2x-launch
    shellcheck $out/bin/video2x-launch

    cat > $out/share/applications/video2x.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Video2X
    Comment=Upscale and interpolate video with Real-ESRGAN, Real-CUGAN or RIFE
    Exec=ghostty --title=Video2X -e $out/bin/video2x-launch
    Icon=video2x
    Terminal=false
    Categories=AudioVideo;Video;
    Keywords=upscale;super-resolution;interpolation;anime;esrgan;rife;
    StartupWMClass=com.mitchellh.ghostty
    EOF
    desktop-file-validate $out/share/applications/video2x.desktop
  ''
