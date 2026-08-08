{ symlinkJoin, makeWrapper, quickshell, qt6 }:

# quickshell with QtMultimedia on its QML import path, so the Mirror widget
# (config/quickshell/Mirror) can `import QtMultimedia` for the webcam feed.
# Upstream quickshell does not depend on qtmultimedia, and quickshell resolves
# QML imports from NIXPKGS_QT6_QML_IMPORT_PATH rather than the usual
# QML2_IMPORT_PATH, so the plain package cannot find it.
symlinkJoin {
  name = "quickshell-mirror-${quickshell.version}";
  paths = [ quickshell ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm -f $out/bin/qs $out/bin/quickshell
    makeWrapper ${quickshell}/bin/qs $out/bin/qs \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtmultimedia}/lib/qt-6/qml \
      --prefix QT_PLUGIN_PATH : ${qt6.qtmultimedia}/lib/qt-6/plugins
    makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtmultimedia}/lib/qt-6/qml \
      --prefix QT_PLUGIN_PATH : ${qt6.qtmultimedia}/lib/qt-6/plugins
  '';
}
