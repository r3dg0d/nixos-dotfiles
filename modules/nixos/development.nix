# Toolchains: the Android SDK/NDK and the cross-compilers this machine builds
# with. Split out because it is by far the heaviest part of the closure and the
# easiest thing to drop on a machine that does not need it.
{ config, lib, pkgs, ... }:

let
  cfg = config.my.development;

  # Android SDK + NDK. Every version is left at "latest" on purpose: androidenv
  # resolves those against its pinned repo.json, so nothing here goes stale and
  # breaks eval the way hardcoded version strings ("34.0.0", "27.0.12077973", …)
  # do when nixpkgs updates. Emulator and system images are excluded — they are
  # multi-GB and this box uses a physical device (see the kloak-android work).
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    includeEmulator = false;
    includeSystemImages = false;
  };
  androidSdkRoot = "${androidComposition.androidsdk}/libexec/android-sdk";
in
{
  options.my.development = {
    android.enable = lib.mkEnableOption "the Android SDK/NDK toolchain" // { default = true; };
    crossCompilers.enable = lib.mkEnableOption "the ARM64/mingw32 cross toolchains" // { default = true; };
  };

  config = lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        nodejs
        jdk25 # Java 25 for Minecraft 1.26.x server
        gcc-unwrapped
      ];
    }

    (lib.mkIf cfg.android.enable {
      environment.systemPackages = [
        androidComposition.androidsdk # SDK + platform-tools + build-tools + NDK
        pkgs.android-tools # standalone adb/fastboot on $PATH
      ];

      environment.sessionVariables = {
        # Gradle/Android Studio/CMake look these up rather than searching $PATH.
        ANDROID_HOME = androidSdkRoot;
        ANDROID_SDK_ROOT = androidSdkRoot;
      };

      # The Android SDK components are under Google's non-free SDK licence,
      # which androidenv refuses to unpack until this is set.
      nixpkgs.config.android_sdk.accept_license = true;
    })

    (lib.mkIf cfg.crossCompilers.enable {
      environment.systemPackages = with pkgs; [
        # Linux ARM64 from this x86_64 host: aarch64-unknown-linux-gnu-{gcc,g++}.
        # .buildPackages is the part that RUNS here; pkgsCross.<t>.gcc would be a
        # compiler built to run ON the target, which is not what's wanted.
        pkgsCross.aarch64-multiplatform.buildPackages.gcc
        pkgsCross.aarch64-multiplatform.buildPackages.binutils
        # Windows 32-bit: i686-w64-mingw32-{gcc,g++}. mingwW64 would be the 64-bit
        # x86_64-w64-mingw32 toolchain; mingw32 is the i686 one that was asked for.
        # mingw32-cc is the mcfgthread-fixed wrapper (pkgs/mingw32-cc.nix); the
        # unwrapped pkgsCross.mingw32.buildPackages.gcc cannot compile anything.
        mingw32-cc
        pkgsCross.mingw32.buildPackages.binutils
      ];
    })
  ];
}
