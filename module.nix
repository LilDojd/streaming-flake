{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.streaming-obs;
in
{
  options.programs.streaming-obs = {
    enable = lib.mkEnableOption "the programming stream OBS setup";
    twitchStreamKeyFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = "Runtime path to the Twitch stream key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isLinux;
        message = "programs.streaming-obs is supported only on Linux.";
      }
      {
        assertion = cfg.twitchStreamKeyFile != null;
        message = "programs.streaming-obs.twitchStreamKeyFile must be set.";
      }
    ];

    programs.obs-studio = {
      enable = true;
      package = pkgs.obs-studio.override { cudaSupport = true; };
      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture
        obs-wayland-hotkeys
        obs-source-record
        obs-composite-blur
      ];
    };
  };
}
