{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.streaming-obs;
  profileDirectory = "obs-studio/basic/profiles/Programming";
  sceneTemplate = ./scenes.json;
  shaderAssets = import ./shader-assets.nix { inherit pkgs; };
  hotkey =
    key:
    builtins.toJSON {
      bindings = [
        {
          control = true;
          shift = true;
          inherit key;
        }
      ];
    };
  profile = {
    General.Name = "Programming";
    Output = {
      Mode = "Advanced";
      FilenameFormatting = "%CCYY-%MM-%DD %hh-%mm-%ss";
      Reconnect = true;
      RetryDelay = 2;
      MaxRetries = 25;
    };
    AdvOut = {
      ApplyServiceSettings = false;
      UseRescale = false;
      TrackIndex = 1;
      Encoder = "obs_nvenc_h264_tex";
      RecType = "Standard";
      RecFilePath = "${config.xdg.userDirs.videos}/OBS";
      RecFormat2 = "mkv";
      RecUseRescale = false;
      RecTracks = 7;
      RecEncoder = "obs_nvenc_h264_tex";
      AudioEncoder = "ffmpeg_aac";
      RecAudioEncoder = "ffmpeg_aac";
      Track1Bitrate = 160;
      Track2Bitrate = 160;
      Track3Bitrate = 160;
    };
    Video = {
      BaseCX = 2560;
      BaseCY = 1440;
      OutputCX = 2560;
      OutputCY = 1440;
      FPSType = 0;
      FPSCommon = 60;
      ScaleType = "lanczos";
      ColorFormat = "NV12";
      ColorSpace = 709;
      ColorRange = "Partial";
      AutoRemux = true;
    };
    Audio = {
      SampleRate = 48000;
      ChannelSetup = "Stereo";
    };
    Hotkeys = {
      "OBSBasic.StartStreaming" = hotkey "OBS_KEY_F9";
      "OBSBasic.StopStreaming" = hotkey "OBS_KEY_F9";
      "OBSBasic.StartRecording" = hotkey "OBS_KEY_F10";
      "OBSBasic.StopRecording" = hotkey "OBS_KEY_F10";
    };
  };
  streamEncoder = {
    rate_control = "CBR";
    bitrate = 8000;
    keyint_sec = 2;
    preset = "p6";
    tune = "hq";
    multipass = "qres";
    profile = "high";
    adaptive_quantization = true;
    lookahead = false;
    bf = 2;
  };
  recordEncoder = streamEncoder // {
    rate_control = "CQP";
    cqp = 20;
  };
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

    home.activation.installObsScene = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configDir="${config.xdg.configHome}/obs-studio"
      sceneDir="$configDir/basic/scenes"
      sceneFile="$sceneDir/Programming.json"
      userConfig="$configDir/user.ini"

      if [[ -z "$DRY_RUN_CMD" ]]; then
        install -d -m 0700 "$sceneDir"
        restoreToken=""
        if [[ -f "$sceneFile" ]]; then
          restoreToken="$(${lib.getExe pkgs.jq} -r \
            '.sources[] | select(.id == "pipewire-screen-capture-source") | .settings.RestoreToken // ""' \
            "$sceneFile")"
        fi

        temporaryScene="$sceneFile.new"
        ${lib.getExe pkgs.jq} \
          --arg restoreToken "$restoreToken" \
          --arg synthwaveShader "${shaderAssets}/synthwave.html" \
          --arg cosmicShader "${shaderAssets}/cosmic.html" \
          '(.sources[] | select(.id == "pipewire-screen-capture-source") | .settings.RestoreToken) = $restoreToken |
           (.sources[] | select(.name == "Synthwave Terrain") | .settings.local_file) = $synthwaveShader |
           (.sources[] | select(.name == "Cosmic Strings") | .settings.local_file) = $cosmicShader' \
          ${sceneTemplate} > "$temporaryScene"
        mv "$temporaryScene" "$sceneFile"

        touch "$userConfig"
        ${lib.getExe pkgs.crudini} --set "$userConfig" Basic Profile Programming
        ${lib.getExe pkgs.crudini} --set "$userConfig" Basic ProfileDir Programming
        ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollection Programming
        ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollectionFile Programming.json
      fi
    '';

    home.activation.writeTwitchService = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -z "$DRY_RUN_CMD" ]]; then
        keyFile=${lib.escapeShellArg cfg.twitchStreamKeyFile}
        profileDir="${config.xdg.configHome}/${profileDirectory}"
        serviceFile="$profileDir/service.json"
        temporaryService="$profileDir/service.json.new"

        if [[ ! -r "$keyFile" ]]; then
          printf 'Twitch stream key is not readable: %s\n' "$keyFile" >&2
          exit 1
        fi

        twitchKey="$(<"$keyFile")"
        twitchKey="''${twitchKey//$'\r'/}"
        twitchKey="''${twitchKey//$'\n'/}"
        if [[ -z "$twitchKey" ]]; then
          printf 'Twitch stream key is empty: %s\n' "$keyFile" >&2
          exit 1
        fi

        install -d -m 0700 "$profileDir"
        umask 077
        printf '%s' "$twitchKey" | ${lib.getExe pkgs.jq} -Rs '{
          type: "rtmp_common",
          settings: {
            service: "Twitch",
            server: "auto",
            key: .,
            protocol: "RTMP"
          }
        }' > "$temporaryService"
        unset twitchKey
        chmod 0600 "$temporaryService"
        mv "$temporaryService" "$serviceFile"
      fi
    '';

    xdg.configFile = {
      "${profileDirectory}/basic.ini".text = lib.generators.toINI { } profile;
      "${profileDirectory}/streamEncoder.json".text = builtins.toJSON streamEncoder;
      "${profileDirectory}/recordEncoder.json".text = builtins.toJSON recordEncoder;
    };

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
