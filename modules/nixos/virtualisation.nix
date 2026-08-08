# QEMU/KVM virtual machines, managed through libvirt and driven by
# virt-manager's GUI.
{ config, pkgs, ... }:

{
  # The libvirtd module already puts libvirt + the qemu package into
  # systemPackages (so qemu-img, virsh, etc. are on $PATH) and loads the `tun`
  # module, so nothing extra is needed for those.
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore"; # don't resume saved guests on boot, just leave them off
    onShutdown = "shutdown"; # ACPI-shutdown running guests instead of save-to-disk
    qemu = {
      # UEFI/OVMF firmware no longer needs to be wired up by hand — as of
      # 26.05 the module publishes every firmware image shipped with QEMU.
      swtpm.enable = true; # emulated TPM 2.0 (Windows 11 guests need it)
      vhostUserPackages = [ pkgs.virtiofsd ]; # virtiofs host<->guest shared folders
    };
  };

  # Redirect host USB devices into a guest from virt-manager's toolbar.
  virtualisation.spiceUSBRedirection.enable = true;

  # The virt-manager GUI. The module also seeds a dconf default so it
  # autoconnects to qemu:///system instead of asking on every launch.
  programs.virt-manager.enable = true;

  # libvirt ships a `default` NAT network (virbr0, 192.168.122.0/24, with
  # dnsmasq handing out DHCP) and libvirtd-config copies its XML into
  # /var/lib/libvirt on every rebuild — but nothing ever marks it autostart,
  # so out of the box every new VM fails with "Network not active". This
  # oneshot flips the autostart flag and brings it up after libvirtd, which
  # makes guest networking work from a cold boot with no manual `virsh`.
  # NOTE: NAT'd guests are reachable from the host, not from the LAN; for
  # LAN-visible guests make a bridge and add it to `allowedBridges`.
  systemd.services.libvirt-default-network = {
    description = "Start and autostart libvirt's default NAT network";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        virsh = "${config.virtualisation.libvirtd.package}/bin/virsh";
      in
      ''
        # Re-define from the package copy if a previous `net-undefine` removed it
        if ! ${virsh} net-info default > /dev/null 2>&1; then
          ${virsh} net-define ${config.virtualisation.libvirtd.package}/var/lib/libvirt/qemu/networks/default.xml
        fi
        ${virsh} net-autostart default
        # Already-running is not an error (e.g. on `nixos-rebuild switch`)
        ${virsh} net-info default | grep -q 'Active:.*yes' || ${virsh} net-start default
      '';
  };
}
