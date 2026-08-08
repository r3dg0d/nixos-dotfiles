# Command-line tooling: shell utilities, security tools, and the AI coding
# agents. Nothing here has any system configuration beyond being installed.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    git
    gh
    jq
    openssl
    gnupg
    shellcheck
    file
    unzip
    v4l-utils
    bibata-cursors

    # ---- AI coding agents ----
    claude-code
    opencode
    codex

    # ---- local inference ----
    ollama-cuda

    # ---- cybersecurity ----
    sqlmap # SQLi tool
    smap # Nmap fork that uses shodan.io
    hashcat
    wireshark
    wireshark-cli
    termshark

    # ---- containers ----
    docker
    docker-compose

    # TPM 2.0 emulator CLI (swtpm/swtpm_setup) — libvirtd already wires its own
    # copy in, this is for hand-run qemu
    swtpm

    # ---- rice ----
    figlet
    toilet
    lolcat
  ];
}
