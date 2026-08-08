{ lib, stdenvNoCC, imagemagick }:

# Custom SDDM theme: animated ASCII rain over a procedural ASCII city, with an
# ASCII-framed login panel.
#
# The source lives at the repository root (../sddm-ascii-city).
#
# The avatar is grayscaled at build time so it matches the monochrome look
# without having to keep a pre-processed copy in git.
stdenvNoCC.mkDerivation {
  pname = "sddm-ascii-city";
  version = "1.0";
  src = ../sddm-ascii-city;

  nativeBuildInputs = [ imagemagick ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/sddm/themes/ascii-city
    cp -r --no-preserve=mode . $out/share/sddm/themes/ascii-city/
    magick $src/pfp.png -colorspace Gray $out/share/sddm/themes/ascii-city/pfp.png
    runHook postInstall
  '';

  meta = with lib; {
    description = "SDDM theme: animated ASCII rain over an ASCII city";
    homepage = "https://github.com/r3dg0d/sddm-ascii-city";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
