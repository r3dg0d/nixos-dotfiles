# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  silentSDDM-src = builtins.fetchTarball {
    url = "https://github.com/uiriansan/SilentSDDM/archive/refs/heads/main.tar.gz";
    sha256 = "10k71i4gc28jzcnchr0zrb68fb101ivd7x9i87jax115rq0gkpga";
  };
  silentSDDM = pkgs.callPackage "${silentSDDM-src}/nix/package.nix" {};
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 48 GB swap file on the NVMe SSD, in addition to the 4 GB swap
  # partition from hardware-configuration.nix (52 GB total).
  swapDevices = [
    { device = "/swapfile"; size = 48 * 1024; } # size in MiB
  ];

  networking.hostName = "nixos-btw"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Allow unfree pkg's
  nixpkgs.config.allowUnfree = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  services.xserver.enable = false;
  services.xserver.windowManager.qtile.enable = false;

  # Graphics — NVIDIA open-source kernel modules + Wayland modesetting
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open               = true;   # NVIDIA's open-source kernel modules (Turing+)
    modesetting.enable = true;   # required for Wayland DRM KMS
    nvidiaSettings     = true;
  };
  
  programs.niri.enable = true;
  
  qt.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "silent";
    extraPackages = silentSDDM.propagatedBuildInputs;
    settings.General = {
      GreeterEnvironment = "QML2_IMPORT_PATH=${silentSDDM}/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard";
      InputMethod = "qtvirtualkeyboard";
    };
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  environment.variables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    GTK_THEME = "Adwaita:dark";
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
 users.users.r3dg0d = {
   isNormalUser = true;
   shell = pkgs.zsh;
   extraGroups = [ "wheel" "ydotool" ]; # Enable ‘sudo’ for the user.
   packages = with pkgs; [
     tree
   ];
 };

  programs.chromium.enable = true;

  # SIVA voice assistant: virtual input for cursor/keyboard control on Wayland
  programs.ydotool.enable = true;

  programs.zsh.enable = true;
  environment.localBinInPath = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
 environment.systemPackages = with pkgs; [
   zsh
   zsh-autocomplete
   zsh-syntax-highlighting
   wtype
   sox
   chromium
   alsa-utils
   lm_sensors
   python3
   vim
   neovim
   ripgrep
   gcc
   curl
   waybar
   wofi
   nodejs
   claude-code
   bibata-cursors
   github-cli
   git
   wget
   ghostty
   btop
   swaybg
   fastfetch
   gpufetch
   cpufetch
   wofi-emoji
   wl-clipboard
   quickshell
   easyeffects
   nautilus
   typr
   xdg-desktop-portal-gtk
   silentSDDM
   whisper-cpp
   # SIVA voice assistant stack
   (llama-cpp.override { cudaSupport = true; }) # local LLM server with CUDA
   grim             # screen capture for the vision loop
   slurp            # region selection
   jq
   socat            # UI <-> daemon unix-socket plumbing
   piper-tts        # local TTS voice output
   libnotify        # notify-send for error surfacing
 ];
  
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    inter
    (pkgs.callPackage "${silentSDDM-src}/nix/fonts.nix" {})
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}

