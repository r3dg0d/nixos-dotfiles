# NetworkManager + ad-blocking encrypted DNS through Mullvad, and lokinet.
# `networking.hostName` and any host-specific firewall holes live in the host.
{ pkgs, ... }:

{
  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Prevent NetworkManager from overriding the resolved settings
  networking.networkmanager.dns = "systemd-resolved";

  # Ad-blocking encrypted Mullvad DNS
  services.resolved = {
    enable = true;

    settings.Resolve = {
      DNSSEC = "false";
      DNSOverTLS = "yes";
      Domains = "~.";

      # Avahi is the mDNS responder on this box (headset discovery for WiVRn,
      # printers, AirPlay). resolved's own mDNS stack competes with it —
      # avahi logs "Detected another IPv4 mDNS stack" and discovery goes flaky.
      MulticastDNS = "no";

      # Mullvad's Extended Ad/Tracker/Malware/Social blocking servers
      FallbackDNS = [
        "192.242.2.5#extended.dns.mullvad.net"
        "2a07:e340::5#extended.dns.mullvad.net"
      ];
    };
  };

  # Mullvad VPN daemon (the mullvad-vpn package is the GUI/CLI; this runs the daemon)
  services.mullvad-vpn.enable = true;

  # Runs the daemon with CAP_NET_ADMIN/CAP_NET_BIND_SERVICE and puts the
  # lokinet CLI in systemPackages. DNS for .loki lives on 127.3.2.1.
  services.lokinet.enable = true;
  services.lokinet.settings.network.keyfile = "identity.key";

  # Route .loki/.snode lookups to lokinet's DNS so they resolve system-wide
  # (browsers included). Lokinet tries to register this itself via
  # SetLinkDNS but the hardened DynamicUser service can't talk to resolved,
  # so do it from a privileged ("+") hook once lokitun0 exists. Per-link
  # DoT/DNSSEC off: the global Mullvad settings would break plain DNS
  # to 127.3.2.1, and the ~loki routing domain wins over global "~.".
  systemd.services.lokinet.serviceConfig.ExecStartPost =
    "+" + pkgs.writeShellScript "lokinet-register-dns" ''
      for _ in $(seq 1 60); do
        ${pkgs.systemd}/bin/resolvectl dns lokitun0 127.3.2.1 2>/dev/null && break
        sleep 0.5
      done
      ${pkgs.systemd}/bin/resolvectl domain lokitun0 '~loki' '~snode'
      ${pkgs.systemd}/bin/resolvectl dnsovertls lokitun0 no
      ${pkgs.systemd}/bin/resolvectl dnssec lokitun0 no
    '';
}
