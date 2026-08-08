{ lib, stdenvNoCC, imagemagick }:

# Custom SDDM theme: animated ASCII rain over a procedural ASCII city, with an
# ASCII-framed login panel and a desktop-session selector.
#
# The source lives at the repository root (../sddm-ascii-city) and is kept
# byte-for-byte in sync with the standalone https://github.com/r3dg0d/sddm-ascii-city
# repo, so the theme can be developed here and published there unchanged.
#
# The avatar is grayscaled at build time so it matches the monochrome look
# without having to keep a pre-processed copy in git.
stdenvNoCC.mkDerivation {
  pname = "sddm-ascii-city";
  version = "1.1";

  # Everything in the theme directory except the developer test harness, which
  # SDDM has no use for and which would otherwise force a rebuild of the theme
  # whenever a test changes.
  src = lib.fileset.toSource {
    root = ../sddm-ascii-city;
    fileset = lib.fileset.difference ../sddm-ascii-city (../sddm-ascii-city + "/test");
  };

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
