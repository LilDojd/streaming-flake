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
pkgs.runCommand "streaming-obs-module-check"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    profile="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/basic.ini"
    streamEncoder="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/streamEncoder.json"
    recordEncoder="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/recordEncoder.json"

    grep -q '^Mode=Advanced$' "$profile"
    grep -q '^BaseCX=2560$' "$profile"
    grep -q '^BaseCY=1440$' "$profile"
    grep -q '^FPSCommon=60$' "$profile"
    grep -q '^RecFormat2=mkv$' "$profile"
    grep -q '^RecTracks=7$' "$profile"
    grep -q '^AutoRemux=true$' "$profile"
    grep -q '^TrackIndex=1$' "$profile"
    jq -e '.rate_control == "CBR" and .bitrate == 8000 and .keyint_sec == 2' "$streamEncoder"
    jq -e '.rate_control == "CQP" and .cqp == 20' "$recordEncoder"
    touch "$out"
  ''
