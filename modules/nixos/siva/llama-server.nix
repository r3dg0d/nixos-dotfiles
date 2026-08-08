# The local LLM backend SIVA talks to.
#
# siva-daemon and siva-type-daemon both speak the OpenAI-compatible HTTP API at
# 127.0.0.1:8090; nothing else does. So this is one llama.cpp server, run as a
# **user** service (it needs no privileges — just the GPU and a loopback
# socket) with Restart=on-failure so a CUDA OOM self-heals instead of leaving
# the assistant throwing ConnectionRefused until the next reboot.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.siva.llama;
  sivaCfg = config.services.siva;
in
{
  options.services.siva.llama = {
    enable = lib.mkEnableOption "the llama.cpp server backing SIVA" // { default = true; };

    package = lib.mkOption {
      type = lib.types.package;
      default =
        if cfg.cuda
        then pkgs.llama-cpp.override { cudaSupport = true; }
        else pkgs.llama-cpp;
      defaultText = lib.literalExpression "pkgs.llama-cpp.override { cudaSupport = true; }";
      description = "llama.cpp build providing `llama-server`.";
    };

    cuda = lib.mkOption {
      type = lib.types.bool;
      default = config.my.nvidia.enable;
      defaultText = lib.literalExpression "config.my.nvidia.enable";
      description = ''
        Build llama.cpp with CUDA. Follows whether the NVIDIA driver is
        enabled, so a machine without one gets a CPU build instead of failing
        to start.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Listen address. Loopback by default and it should stay that way — the
        server has no authentication whatsoever, and binding it to a routable
        address publishes an unauthenticated LLM (and, via SIVA's tools, a
        remote foothold on the desktop) to the whole network.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Listen port. Must match LLAMA_PORT in the SIVA daemons.";
    };

    modelDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.users.users.${sivaCfg.user}.home}/models/gemma-4-31b";
      defaultText = lib.literalExpression ''"''${home}/models/gemma-4-31b"'';
      description = ''
        Directory holding the GGUF weights. Not in the nix store on purpose:
        ~18 GB of redistribution-restricted weights that change independently
        of the system closure.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "gemma-4-31B-it-qat-UD-Q4_K_XL.gguf";
      description = "Model filename inside `modelDir`.";
    };

    mmproj = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "mmproj-F16.gguf";
      description = ''
        Multimodal projector filename inside `modelDir`, or null for a
        text-only model. SIVA's screenshot/vision tools need this.
      '';
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = ''
        VRAM budget on a 24 GB card: ~17.3 GB weights + ~1.2 GB mmproj + a q8
        KV cache. 4096 (not 8k) leaves ~2 GB of headroom — at 8k the server sat
        at ~23.9/24 GB and the vision compute spike (processing a screenshot)
        plus the compositor's demand for the Stream overlay tipped it into a
        CUDA out-of-memory abort. siva-daemon trims old image frames from its
        history, so 4096 is comfortable for the agentic loop.

        This value is also exported to the daemons as SIVA_LLAMA_CTX so their
        history trimming matches the server.
      '';
    };

    gpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 99;
      description = "-ngl: layers offloaded to the GPU. 99 = all of them.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--batch-size"
        "256"
        "--ubatch-size"
        "256"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        "--jinja"
        "--alias"
        "siva"
      ];
      description = "Additional llama-server arguments.";
    };
  };

  config = lib.mkIf (sivaCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.host == "127.0.0.1" || cfg.host == "::1" || cfg.host == "localhost";
        message = ''
          services.siva.llama.host is "${cfg.host}". llama-server is
          unauthenticated; if exposing it beyond loopback is genuinely
          intended, put it behind an authenticating reverse proxy and remove
          this assertion deliberately.
        '';
      }
    ];

    environment.systemPackages = [ cfg.package ];

    systemd.user.services.siva-llama-server = {
      description = "SIVA LLM backend (llama.cpp server)";
      documentation = [ "https://github.com/ggml-org/llama.cpp" ];
      # No Wayland, no audio, no session — just the GPU and loopback. Starting
      # at default.target means it is already warm by the time the greeter is
      # done, because the user has `linger` enabled (modules/nixos/core.nix).
      wantedBy = [ "default.target" ];
      # Never give up: the common failure is transient VRAM pressure from
      # another GPU application. (Belongs in [Unit] — systemd silently ignores
      # StartLimit* in [Service].)
      startLimitIntervalSec = 0;

      environment = lib.mkIf cfg.cuda {
        # ProtectHome=read-only below makes the default ~/.nv/ComputeCache
        # unwritable, which CUDA complains about on every start. Point the JIT
        # cache at the unit's private /tmp instead.
        CUDA_CACHE_PATH = "%T/cuda-cache";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs ([
          "${cfg.package}/bin/llama-server"
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
          "-m"
          "${cfg.modelDir}/${cfg.model}"
        ]
        ++ lib.optionals (cfg.mmproj != null) [ "--mmproj" "${cfg.modelDir}/${cfg.mmproj}" ]
        ++ [
          "-ngl"
          (toString cfg.gpuLayers)
          "--ctx-size"
          (toString cfg.contextSize)
        ]
        ++ cfg.extraFlags);

        # Do not start until the weights are actually on disk. Without this a
        # fresh machine spends its first boot in a restart loop logging the
        # same "failed to load model" line.
        ExecCondition = "${pkgs.coreutils}/bin/test -r ${lib.escapeShellArg "${cfg.modelDir}/${cfg.model}"}";

        # Give a crashed CUDA context time to be reclaimed before retrying.
        Restart = "on-failure";
        RestartSec = 5;

        # Hardening. MemoryDenyWriteExecute and PrivateDevices are deliberately
        # absent: the CUDA runtime JITs code and needs the /dev/nvidia* nodes.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = "read-only"; # the weights are read from $HOME
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectClock = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      };
    };
  };
}
