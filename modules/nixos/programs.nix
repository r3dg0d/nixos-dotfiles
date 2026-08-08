# Command-line tooling: shell utilities, security tools, and the AI coding
# agents. Nothing here has any system configuration beyond being installed.
{ pkgs, ... }:

{
  # SIVA voice assistant: uinput-level pointer control on Wayland
  programs.ydotool.enable = true;

  # SIVA durable memory (MemPalace): its onnxruntime/chromadb wheels are
  # generic dynamically-linked binaries, so nix-ld lets them run on NixOS.
  # Enables `uv tool install mempalace` (mempalace-mcp) to work.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc # libstdc++/libgcc for onnxruntime
    zlib
  ];

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
    (llama-cpp.override { cudaSupport = true; })

    # ---- SIVA voice assistant ----
    whisper-cpp # SIVA STT
    piper-tts # SIVA voice output
    wtype # SIVA virtual keyboard
    sox # SIVA wake-word enrollment (beep synth + 16k resample)
    socat # SIVA F7/F8/F9 toggle scripts talk to the daemon sockets
    tesseract # SIVA agentic OCR click-by-text (find on-screen text to click)
    # python3 carries the SIVA wake-word deps
    (python3.withPackages (ps: with ps; [ numpy scipy scikit-learn onnxruntime tqdm requests ]))

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
