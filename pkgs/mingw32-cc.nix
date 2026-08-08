{ lib, runCommand, makeWrapper, pkgsCross }:

# nixpkgs' i686-w64-mingw32 GCC is built with the mcfgthread threading model,
# but the mcfgthread headers/libs are only wired in by the cross *stdenv*.
# A bare compiler on $PATH therefore can't find them, and even a hello-world
# `#include <iostream>` dies with "mcfgthread/gthr.h: No such file or
# directory" (plain C fails too, at link time on -lmcfgthread). Bake the two
# paths into the compiler drivers so the toolchain works standalone.
# Only the drivers are wrapped; ar/as/ld/... come from the matching binutils
# package, so nothing collides inside system-path.
let
  cross = pkgsCross.mingw32;
  cc = cross.buildPackages.gcc;
  mcf = cross.windows.mcfgthreads;
in
runCommand "i686-w64-mingw32-cc-mcfgthread"
{
  nativeBuildInputs = [ makeWrapper ];
  meta.description = "i686-w64-mingw32 GCC with mcfgthread include/lib paths baked in";
}
  ''
    mkdir -p $out/bin
    for drv in gcc g++ c++ cc cpp; do
      src=${cc}/bin/i686-w64-mingw32-$drv
      [ -e "$src" ] || continue
      makeWrapper "$src" $out/bin/i686-w64-mingw32-$drv \
        --add-flags "-isystem ${lib.getDev mcf}/include" \
        --add-flags "-L${lib.getLib mcf}/lib"
    done
  ''
