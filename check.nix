{ pkgs, testHome }:
let
  cfg = testHome.config;
  expectedPlugins = with pkgs.obs-studio-plugins; [
    obs-pipewire-audio-capture
    obs-wayland-hotkeys
    obs-source-record
    obs-composite-blur
  ];
in
assert cfg.programs.streaming-obs.enable;
assert cfg.programs.streaming-obs.twitchStreamKeyFile == "/run/agenix/twitchStreamKey";
assert cfg.programs.obs-studio.enable;
assert cfg.programs.obs-studio.plugins == expectedPlugins;
pkgs.runCommand "streaming-obs-module-check" { } ''
  touch "$out"
''
