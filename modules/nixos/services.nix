# Long-running system services that are part of the desktop but not part of
# any one session: media server, private metasearch, VR streaming.
{ config, pkgs, ... }:

{
  # Jellyfin media server — stream movies/TV from this PC to the TV.
  # openFirewall opens 8096 (web UI/API) + 8920 (HTTPS) TCP and UDP
  # 1900/7359 for DLNA + client auto-discovery on the LAN. The service runs
  # as its own `jellyfin` user; add it to the video/render groups so it can
  # reach the GPU's /dev/nvidia* + /dev/dri nodes for NVENC hardware
  # transcoding (enable it under Dashboard > Playback once running).
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # The media lives under ~/Videos, but the home directory is mode 0700 so the
  # jellyfin user can't traverse into it. A POSIX ACL grants it the traverse
  # (+x) bit on the home dir only — the contents stay unreadable to everyone
  # else. This has to live in tmpfiles rather than a one-off `setfacl`: the
  # users activation snippet runs `chmod <homeMode> <home>` on *every*
  # `nixos-rebuild switch`, and chmod recalculates the ACL mask from the group
  # bits (0 here), silently reducing the named-user entry to `#effective:---`.
  # The explicit `m::x` re-establishes the mask; systemd-tmpfiles-resetup runs
  # after the activation scripts, so it undoes the damage each rebuild.
  systemd.tmpfiles.rules = [
    "a+ ${config.my.homeDirectory} - - - - u:jellyfin:x,m::x"
  ];

  # SearXNG metasearch, localhost-only. Secret lives in /etc/searxng.env
  # (not in the repo / nix store); @SEARXNG_SECRET@ is substituted from it.
  # `install.sh` generates that file if it is missing.
  services.searx = {
    enable = true;
    environmentFile = "/etc/searxng.env";
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "@SEARXNG_SECRET@";
      };
      search = {
        # feeds the omnibox suggest URL in desktop/apps.nix
        autocomplete = "duckduckgo";
        # expose the JSON API too (default is html only) so SIVA's web_search
        # tool can consume results programmatically — localhost-only anyway
        formats = [ "html" "json" ];
      };
    };
  };

  # WiVRn: OpenXR streaming to standalone VR headsets. The module installs the
  # dashboard/server, enables Avahi for headset discovery, and opens port 9757.
  services.wivrn = {
    enable = true;
    openFirewall = true;
    steam.importOXRRuntimes = true;
  };
}
