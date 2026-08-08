# Base system: nix itself, the kernel, the primary user account, shells,
# fonts and the power-button policy. Nothing here is machine-specific.
{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  # The kernel choice lives in ./kernel.nix — it is a switch now (nixpkgs'
  # latest, or Linus' mainline tree), not a one-liner.

  # NTFS on removable drives: pulls in ntfs3g (mkfs.ntfs, ntfsfix) and lets
  # udisks auto-mount NTFS volumes on plug-in. The external Samsung T5 backup
  # SSD is NTFS so it stays readable from Windows.
  boot.supportedFilesystems = [ "ntfs" ];

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.${config.my.username} = {
    isNormalUser = true;
    linger = true; # start user services (mpd, siva-llama-server) at boot, not just on login
    # sudo + SIVA's ydotoold socket + libvirt (manage VMs without a polkit
    # prompt) + kvm (direct /dev/kvm access for non-libvirt qemu runs)
    extraGroups = [ "wheel" "ydotool" "libvirtd" "kvm" ];
    shell = pkgs.zsh; # zsh as the login shell
    packages = with pkgs; [
      tree
    ];
  };

  # zsh must be enabled system-wide to be a valid login shell
  programs.zsh.enable = true;

  # gpg-agent + a pinentry so gpg can prompt for passphrases
  # (fixes "no pinentry"). curses = prompts inside the terminal.
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  security.polkit.enable = true;

  # Never suspend on its own. The Pulsar PCMK 2 HE keyboard's "System Control"
  # HID interface (event9) spuriously emits KEY_POWER after a stretch of no
  # input, and logind turned that into a suspend -- every single sleep in the
  # journal is "Power key pressed short." followed by "The system will suspend
  # now!", never an idle timeout. It fires again the moment the keyboard
  # re-enumerates on resume, so the machine used to drop straight back to sleep.
  # Suspend is now only reachable deliberately, via the quickshell power widget
  # (`systemctl suspend`, see config/quickshell/Power.qml).
  services.logind.settings.Login = {
    HandlePowerKey = "ignore"; # the bogus event; short press does nothing
    HandlePowerKeyLongPress = "poweroff"; # holding the real case button still works
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
    HandleHibernateKey = "ignore";
    HandleHibernateKeyLongPress = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };
}
