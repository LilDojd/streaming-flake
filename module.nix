{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.streaming-obs;
  profileDirectory = "obs-studio/basic/profiles/${cfg.profileName}";
  sceneTemplate = ./scenes.json;
  shaderAssets = import ./shader-assets.nix { inherit pkgs; };
  defaultChatCss = ''
    body { background: transparent; margin: 0; overflow: hidden; }
    #chat_box { background: transparent; color: #f8fafc; font: 600 22px sans-serif; }
    .chat_line { background: rgba(2, 6, 23, 0.82); border-radius: 12px; line-height: 1.35; margin: 8px 0; padding: 10px 14px; }
  '';
  chatUrl =
    if cfg.twitch.chat.url != null then
      cfg.twitch.chat.url
    else if cfg.twitch.channel != null then
      "https://nightdev.com/hosted/obschat?channel=${cfg.twitch.channel}&style=clear&fade=30&bot_activity=false&prevent_clipping=true"
    else
      "";
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
  profile = lib.recursiveUpdate {
    General.Name = cfg.profileName;
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
      RecFilePath = cfg.recordingDirectory;
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
      BaseCX = cfg.video.baseWidth;
      BaseCY = cfg.video.baseHeight;
      OutputCX = cfg.video.outputWidth;
      OutputCY = cfg.video.outputHeight;
      FPSType = 0;
      FPSCommon = cfg.video.fps;
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
  } cfg.extraProfileSettings;
  streamEncoder = lib.recursiveUpdate {
    rate_control = "CBR";
    bitrate = 6000;
    keyint_sec = 2;
    preset = "p6";
    tune = "hq";
    multipass = "qres";
    profile = "high";
    adaptive_quantization = true;
    lookahead = false;
    bf = 2;
  } cfg.extraStreamEncoderSettings;
  recordEncoder = lib.recursiveUpdate (
    streamEncoder
    // {
      rate_control = "CQP";
      cqp = 20;
    }
  ) cfg.extraRecordEncoderSettings;
  defaultPlugins = with pkgs.obs-studio-plugins; [
    obs-pipewire-audio-capture
    obs-wayland-hotkeys
    obs-source-record
    obs-composite-blur
  ];
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "programs" "streaming-obs" "twitchStreamKeyFile" ]
      [ "programs" "streaming-obs" "twitch" "streamKeyFile" ]
    )
  ];

  options.programs.streaming-obs = {
    enable = lib.mkEnableOption "the programming stream OBS setup";

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "Programming";
      description = "Name of the managed OBS profile.";
    };

    sceneCollectionName = lib.mkOption {
      type = lib.types.str;
      default = "Programming";
      description = "Name of the managed OBS scene collection.";
    };

    recordingDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.userDirs.videos}/OBS";
      description = "Directory used for local recordings.";
    };

    video = {
      baseWidth = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2560;
        description = "OBS canvas width.";
      };
      baseHeight = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1440;
        description = "OBS canvas height.";
      };
      outputWidth = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1920;
        description = "Stream and recording output width.";
      };
      outputHeight = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1080;
        description = "Stream and recording output height.";
      };
      fps = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Stream frame rate.";
      };
    };

    twitch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.twitch.streamKeyFile != null;
        defaultText = lib.literalExpression "config.programs.streaming-obs.twitch.streamKeyFile != null";
        description = "Whether to write the Twitch streaming service configuration.";
      };

      streamKeyFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "Runtime path to the Twitch stream key.";
      };

      channel = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "my_channel";
        description = "Twitch channel used by the stream chat browser source.";
      };

      chat = {
        enable = lib.mkEnableOption "the Twitch chat browser source";

        url = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = "Chat overlay URL; generated from the channel when unset.";
        };

        css = lib.mkOption {
          type = lib.types.lines;
          default = defaultChatCss;
          description = "CSS applied to the Twitch chat browser source.";
        };
      };
    };

    scenes = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install and select the managed scene collection.";
      };

      overwrite = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Replace an existing scene collection from the bundled template. When false,
          existing scene edits are retained and only managed asset paths and chat
          settings are refreshed.
        '';
      };

      backup = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Back up the existing scene collection before overwriting it.";
      };
    };

    extraPlugins = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = "Additional OBS plugins to install.";
    };

    extraProfileSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = lib.literalExpression "{ AdvOut.Track1Bitrate = 192; }";
      description = "Settings recursively merged into the generated OBS profile INI.";
    };

    extraStreamEncoderSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings recursively merged into streamEncoder.json.";
    };

    extraRecordEncoderSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings recursively merged into recordEncoder.json.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "programs.streaming-obs is supported only on Linux.";
          }
          {
            assertion = !cfg.twitch.enable || cfg.twitch.streamKeyFile != null;
            message = "programs.streaming-obs.twitch.streamKeyFile must be set when Twitch service management is enabled.";
          }
          {
            assertion = !cfg.twitch.chat.enable || cfg.twitch.channel != null || cfg.twitch.chat.url != null;
            message = "Set programs.streaming-obs.twitch.channel or twitch.chat.url when the chat source is enabled.";
          }
        ];

        xdg.configFile = {
          "${profileDirectory}/basic.ini".text = lib.generators.toINI { } profile;
          "${profileDirectory}/streamEncoder.json".text = builtins.toJSON streamEncoder;
          "${profileDirectory}/recordEncoder.json".text = builtins.toJSON recordEncoder;
        };

        programs.obs-studio = {
          enable = true;
          package = pkgs.obs-studio.override { cudaSupport = true; };
          plugins = lib.unique (defaultPlugins ++ cfg.extraPlugins);
        };
      }

      (lib.mkIf cfg.scenes.enable {
        home.activation.installObsScene = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          configDir="${config.xdg.configHome}/obs-studio"
          sceneDir="$configDir/basic/scenes"
          sceneCollection=${lib.escapeShellArg cfg.sceneCollectionName}
          profileName=${lib.escapeShellArg cfg.profileName}
          sceneFile="$sceneDir/$sceneCollection.json"
          userConfig="$configDir/user.ini"

          if [[ -z "$DRY_RUN_CMD" ]]; then
            install -d -m 0700 "$sceneDir"
            sourceScene=${sceneTemplate}
            if [[ -f "$sceneFile" ]]; then
              if ${lib.boolToString cfg.scenes.overwrite}; then
                if ${lib.boolToString cfg.scenes.backup}; then
                  cp --preserve=mode,timestamps "$sceneFile" "$sceneFile.backup"
                fi
              else
                sourceScene="$sceneFile"
              fi
            fi

            temporaryScene="$sceneFile.new"
            ${lib.getExe pkgs.jq} \
              --arg collectionName "$sceneCollection" \
              --arg synthwaveShader "${shaderAssets}/synthwave.html" \
              --arg cosmicShader "${shaderAssets}/cosmic.html" \
              --arg chatUrl ${lib.escapeShellArg chatUrl} \
              --arg chatCss ${lib.escapeShellArg cfg.twitch.chat.css} \
              --argjson chatEnabled ${lib.boolToString cfg.twitch.chat.enable} \
              --slurpfile template ${sceneTemplate} \
              --argjson width ${toString cfg.video.baseWidth} \
              --argjson height ${toString cfg.video.baseHeight} \
              '.name = $collectionName |
               (.sources[] | select(.name == "Synthwave Terrain") | .settings) |=
                 (.local_file = $synthwaveShader | .width = $width | .height = $height) |
               (.sources[] | select(.name == "Cosmic Strings") | .settings) |=
                 (.local_file = $cosmicShader | .width = $width | .height = $height) |
               if $chatEnabled then
                 (if any(.sources[]; .name == "Twitch Chat") then . else
                   .sources += [($template[0].sources[] | select(.name == "Twitch Chat"))]
                 end) |
                 (.sources[] | select(.name == "Programming") | .settings.items) |=
                   (if any(.[]; .source_uuid == "99999999-9999-4999-8999-999999999999") then . else
                     . + [($template[0].sources[] | select(.name == "Programming") |
                       .settings.items[] | select(.source_uuid == "99999999-9999-4999-8999-999999999999"))]
                   end) |
                 (.sources[] | select(.name == "Twitch Chat") | .settings) |=
                   (.url = $chatUrl | .css = $chatCss)
               else
                 .sources |= map(select(.name != "Twitch Chat")) |
                 (.sources[] | select(.name == "Programming") | .settings.items) |=
                   map(select(.source_uuid != "99999999-9999-4999-8999-999999999999"))
               end' \
              "$sourceScene" > "$temporaryScene"
            chmod 0600 "$temporaryScene"
            mv "$temporaryScene" "$sceneFile"

            touch "$userConfig"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic Profile "$profileName"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic ProfileDir "$profileName"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollection "$sceneCollection"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollectionFile "$sceneCollection.json"
          fi
        '';
      })

      (lib.mkIf cfg.twitch.enable {
        home.activation.writeTwitchService = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -z "$DRY_RUN_CMD" ]]; then
            keyFile=${lib.escapeShellArg cfg.twitch.streamKeyFile}
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
      })
    ]
  );
}
