{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.streaming-obs;
  between =
    minimum: maximum: value:
    value >= minimum && value <= maximum;
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
  baseObsPackage = pkgs.obs-studio.override { cudaSupport = true; };
  obsPackage =
    if cfg.graphics.nvidiaOnly then
      pkgs.symlinkJoin {
        name = "obs-studio-nvidia-only";
        paths = [ baseObsPackage ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/obs" \
            --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json \
            --set __GLX_VENDOR_LIBRARY_NAME nvidia \
            --set __NV_PRIME_RENDER_OFFLOAD 1 \
            --set __VK_LAYER_NV_optimus NVIDIA_only \
            --set GBM_BACKEND nvidia-drm \
            --set VK_DRIVER_FILES /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
        '';
        meta = baseObsPackage.meta // {
          mainProgram = "obs";
        };
      }
    else
      baseObsPackage;
  defaultPlugins = with pkgs.obs-studio-plugins; [
    obs-pipewire-audio-capture
    obs-source-record
    obs-composite-blur
  ];
  microphoneFilters = [
    {
      name = "Mic Noise Suppression";
      uuid = "19191919-1111-4111-8111-111111111111";
      id = "noise_suppress_filter";
      versioned_id = "noise_suppress_filter_v2";
      settings.method = cfg.audio.microphone.filters.noiseSuppressionMethod;
      enabled = true;
      hotkeys = { };
    }
    {
      name = "Mic Expander";
      uuid = "19191919-2222-4222-8222-222222222222";
      id = "expander_filter";
      versioned_id = "expander_filter";
      settings = {
        presets = "expander";
        ratio = cfg.audio.microphone.filters.expander.ratio;
        threshold = cfg.audio.microphone.filters.expander.threshold;
        attack_time = cfg.audio.microphone.filters.expander.attackTime;
        release_time = cfg.audio.microphone.filters.expander.releaseTime;
        output_gain = 0.0;
        detector = "RMS";
      };
      enabled = true;
      hotkeys = { };
    }
    {
      name = "Mic Compressor";
      uuid = "19191919-3333-4333-8333-333333333333";
      id = "compressor_filter";
      versioned_id = "compressor_filter";
      settings = {
        ratio = cfg.audio.microphone.filters.compressor.ratio;
        threshold = cfg.audio.microphone.filters.compressor.threshold;
        attack_time = cfg.audio.microphone.filters.compressor.attackTime;
        release_time = cfg.audio.microphone.filters.compressor.releaseTime;
        output_gain = cfg.audio.microphone.filters.compressor.outputGain;
        sidechain_source = "none";
      };
      enabled = true;
      hotkeys = { };
    }
    {
      name = "Mic Limiter";
      uuid = "19191919-4444-4444-8444-444444444444";
      id = "limiter_filter";
      versioned_id = "limiter_filter";
      settings = {
        threshold = cfg.audio.microphone.filters.limiterThreshold;
        release_time = 60;
      };
      enabled = true;
      hotkeys = { };
    }
  ];
  cleanRecordingFilter = {
    name = "Clean Recording";
    uuid = "18181818-1818-4818-8818-181818181818";
    id = "source_record_filter";
    versioned_id = "source_record_filter";
    enabled = true;
    hotkeys = { };
    settings = {
      record_mode =
        {
          off = 0;
          always = 1;
          streaming = 2;
          recording = 3;
          either = 4;
        }
        .${cfg.cleanRecording.mode};
      stream_mode = 0;
      path = cfg.cleanRecording.directory;
      filename_formatting = cfg.cleanRecording.filenameFormatting;
      rec_format = "mkv";
      encoder = "nvenc";
      rate_control = "CQP";
      cqp = cfg.cleanRecording.cqp;
      preset = "p6";
      tune = "hq";
      multipass = "qres";
      profile = "high";
      lookahead = false;
      bf = 2;
      audio_encoder = "ffmpeg_aac";
      audio_bitrate = 160;
      different_audio = true;
      audio_track = -1;
      scale = false;
      frame_rate_divisor = 0;
      replay_buffer = false;
      split_file = false;
      remove_after_record = false;
      record_max_seconds = 0;
      backgroundColor = 4278190080;
    };
  };
  pythonWithObs = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.obsws-python ]);
  obsControl = pkgs.writeShellApplication {
    name = "streaming-obs-control";
    runtimeInputs = [ pythonWithObs ];
    text = ''
      export STREAMING_OBS_PASSWORD_FILE=${lib.escapeShellArg (toString cfg.webSocket.passwordFile)}
      export STREAMING_OBS_HOST=${lib.escapeShellArg cfg.webSocket.host}
      export STREAMING_OBS_PORT=${toString cfg.webSocket.port}
      export STREAMING_OBS_TIMEOUT=${toString cfg.webSocket.timeout}
      export STREAMING_OBS_PRIVACY_MUTE_MIC=${if cfg.privacy.muteMicrophone then "1" else "0"}
      export STREAMING_OBS_PRIVACY_STOP_CLEAN_RECORDING=${
        if cfg.privacy.stopCleanRecording then "1" else "0"
      }
      exec python ${./obs-control.py} "$@"
    '';
  };
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

    graphics.nvidiaOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Restrict OBS and its CEF browser subprocesses to NVIDIA's EGL and Vulkan
        drivers. This prevents WebGL browser sources from selecting another GPU
        independently of the OBS renderer on hybrid systems.
      '';
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

    secondMonitor.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install a separately selectable second-monitor capture scene.";
    };

    privacy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install the capture-free Privacy scene on Ctrl+Shift+F8.";
      };
      text = lib.mkOption {
        type = lib.types.str;
        default = "PRIVACY MODE";
        description = "Text displayed by the Privacy scene.";
      };
      muteMicrophone = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Mute the microphone when privacy mode is entered through WebSocket control.";
      };
      stopCleanRecording = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Stop Source Record clean recording when privacy mode is entered through WebSocket control.";
      };
    };

    audio.microphone.filters = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Apply RNNoise, expander, compressor, and limiter microphone filters.";
      };
      noiseSuppressionMethod = lib.mkOption {
        type = lib.types.enum [
          "rnnoise"
          "speex"
        ];
        default = "rnnoise";
        description = "OBS microphone noise suppression method.";
      };
      expander = {
        ratio = lib.mkOption {
          type = with lib.types; either int float;
          default = 2.0;
        };
        threshold = lib.mkOption {
          type = with lib.types; either int float;
          default = -45.0;
          description = "Expander threshold in dB.";
        };
        attackTime = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = "Expander attack in milliseconds.";
        };
        releaseTime = lib.mkOption {
          type = lib.types.ints.positive;
          default = 100;
          description = "Expander release in milliseconds.";
        };
      };
      compressor = {
        ratio = lib.mkOption {
          type = with lib.types; either int float;
          default = 3.0;
        };
        threshold = lib.mkOption {
          type = with lib.types; either int float;
          default = -18.0;
          description = "Compressor threshold in dB.";
        };
        attackTime = lib.mkOption {
          type = lib.types.ints.positive;
          default = 6;
          description = "Compressor attack in milliseconds.";
        };
        releaseTime = lib.mkOption {
          type = lib.types.ints.positive;
          default = 80;
          description = "Compressor release in milliseconds.";
        };
        outputGain = lib.mkOption {
          type = with lib.types; either int float;
          default = 0.0;
          description = "Compressor make-up gain in dB.";
        };
      };
      limiterThreshold = lib.mkOption {
        type = with lib.types; either int float;
        default = -1.0;
        description = "Limiter threshold in dB.";
      };
    };

    cleanRecording = {
      enable = lib.mkEnableOption "a clean code recording using the Source Record plugin" // {
        default = true;
      };
      directory = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.recordingDirectory}/clean";
        description = "Directory for clean recordings without stream overlays.";
      };
      mode = lib.mkOption {
        type = lib.types.enum [
          "off"
          "always"
          "streaming"
          "recording"
          "either"
        ];
        default = "recording";
        description = "Source Record lifecycle mode. Use off with manual WebSocket controls.";
      };
      filenameFormatting = lib.mkOption {
        type = lib.types.str;
        default = "clean-%CCYY-%MM-%DD-%hh-%mm-%ss";
      };
      cqp = lib.mkOption {
        type = lib.types.ints.positive;
        default = 20;
      };
    };

    alerts = {
      enable = lib.mkEnableOption "an alert browser source";
      urlFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "Runtime file containing the alert widget URL, keeping widget tokens out of the Nix store.";
      };
    };

    accessibility = {
      captions = {
        enable = lib.mkEnableOption "live captions read from a runtime text file";
        textFile = lib.mkOption {
          type = lib.types.str;
          default =
            if config.home.uid == null then
              "${config.xdg.cacheHome}/streaming-obs/captions.txt"
            else
              "/run/user/${toString config.home.uid}/streaming-obs/captions.txt";
          defaultText = lib.literalExpression ''
            "/run/user/''${toString config.home.uid}/streaming-obs/captions.txt"
          '';
          description = "Transient UTF-8 caption file updated atomically by an external caption producer.";
        };
      };
      keystrokeCallouts.enable = lib.mkEnableOption "WebSocket-updated keystroke callouts";
      showCursor = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show the cursor in both PipeWire monitor capture sources.";
      };
    };

    webSocket = {
      enable = lib.mkEnableOption "authenticated OBS WebSocket control";
      passwordFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "Runtime password file for OBS WebSocket; never copied into the Nix store.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "OBS WebSocket host used by the control client.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 4455;
      };
      timeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "WebSocket client timeout in seconds.";
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
          {
            assertion = !cfg.alerts.enable || cfg.alerts.urlFile != null;
            message = "programs.streaming-obs.alerts.urlFile must be set when alerts are enabled.";
          }
          {
            assertion = !cfg.webSocket.enable || cfg.webSocket.passwordFile != null;
            message = "programs.streaming-obs.webSocket.passwordFile must be set when WebSocket control is enabled.";
          }
          {
            assertion = !cfg.accessibility.keystrokeCallouts.enable || cfg.webSocket.enable;
            message = "WebSocket control must be enabled for keystroke callouts.";
          }
          {
            assertion =
              between 1 32 cfg.audio.microphone.filters.expander.ratio
              && between (-60) 0 cfg.audio.microphone.filters.expander.threshold
              && between 1 500 cfg.audio.microphone.filters.expander.attackTime
              && between 1 1000 cfg.audio.microphone.filters.expander.releaseTime
              && between 1 32 cfg.audio.microphone.filters.compressor.ratio
              && between (-60) 0 cfg.audio.microphone.filters.compressor.threshold
              && between 1 500 cfg.audio.microphone.filters.compressor.attackTime
              && between 1 1000 cfg.audio.microphone.filters.compressor.releaseTime
              && between (-32) 32 cfg.audio.microphone.filters.compressor.outputGain
              && between (-60) 0 cfg.audio.microphone.filters.limiterThreshold;
            message = "Microphone filter settings are outside OBS-supported ranges.";
          }
          {
            assertion = between 1 51 cfg.cleanRecording.cqp;
            message = "programs.streaming-obs.cleanRecording.cqp must be between 1 and 51.";
          }
        ];

        xdg.configFile = {
          "${profileDirectory}/basic.ini".text = lib.generators.toINI { } profile;
          "${profileDirectory}/streamEncoder.json".text = builtins.toJSON streamEncoder;
          "${profileDirectory}/recordEncoder.json".text = builtins.toJSON recordEncoder;
        };

        programs.obs-studio = {
          enable = true;
          package = obsPackage;
          plugins = lib.unique (defaultPlugins ++ cfg.extraPlugins);
        };

        home.packages = lib.optional cfg.webSocket.enable obsControl;
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
            install -d -m 0700 "$sceneDir" ${lib.escapeShellArg cfg.cleanRecording.directory}
            sourceScene=${sceneTemplate}
            primaryRestoreToken=""
            secondaryRestoreToken=""
            shouldBackup=false

            if [[ -f "$sceneFile" ]]; then
              primaryRestoreToken="$(${lib.getExe pkgs.jq} -r \
                '.sources[] | select(.uuid == "33333333-3333-4333-8333-333333333333") | .settings.RestoreToken // ""' \
                "$sceneFile")"
              secondaryRestoreToken="$(${lib.getExe pkgs.jq} -r \
                '.sources[] | select(.uuid == "cccccccc-cccc-4ccc-8ccc-cccccccccccc") | .settings.RestoreToken // ""' \
                "$sceneFile")"

              if ${lib.boolToString cfg.scenes.overwrite}; then
                shouldBackup=true
              else
                sourceScene="$sceneFile"
                if [[ "$(${lib.getExe pkgs.jq} -r '.modules["streaming-flake"].version // 0' "$sceneFile")" -lt 3 ]]; then
                  shouldBackup=true
                fi
              fi
            fi

            if $shouldBackup && ${lib.boolToString cfg.scenes.backup}; then
              cp --preserve=mode,timestamps "$sceneFile" "$sceneFile.backup"
            fi

            temporaryAlertsUrlFile=""
            if ${lib.boolToString cfg.alerts.enable}; then
              alertsUrlFile=${
                lib.escapeShellArg (if cfg.alerts.urlFile == null then "" else cfg.alerts.urlFile)
              }
              if [[ ! -r "$alertsUrlFile" ]]; then
                printf 'OBS alerts URL file is not readable: %s\n' "$alertsUrlFile" >&2
                exit 1
              fi
              if [[ -z "$(tr -d '\r\n' < "$alertsUrlFile")" ]]; then
                printf 'OBS alerts URL file is empty: %s\n' "$alertsUrlFile" >&2
                exit 1
              fi
            else
              temporaryAlertsUrlFile="$sceneDir/.alerts-url.empty"
              install -m 0600 /dev/null "$temporaryAlertsUrlFile"
              alertsUrlFile="$temporaryAlertsUrlFile"
            fi

            if ${lib.boolToString cfg.accessibility.captions.enable}; then
              captionFile=${lib.escapeShellArg cfg.accessibility.captions.textFile}
              install -d -m 0700 "$(dirname "$captionFile")"
              if [[ -e "$captionFile" && ( -L "$captionFile" || ! -f "$captionFile" ) ]]; then
                printf 'OBS caption path is not a regular file: %s\n' "$captionFile" >&2
                exit 1
              fi
              if [[ ! -e "$captionFile" ]]; then
                install -m 0600 /dev/null "$captionFile"
              fi
              chmod 0600 "$captionFile"
            fi

            temporaryScene="$sceneFile.new"
            ${lib.getExe pkgs.jq} \
              --from-file ${./scene-transform.jq} \
              --arg collectionName "$sceneCollection" \
              --arg synthwaveShader "${shaderAssets}/synthwave.html" \
              --arg cosmicShader "${shaderAssets}/cosmic.html" \
              --arg primaryRestoreToken "$primaryRestoreToken" \
              --arg secondaryRestoreToken "$secondaryRestoreToken" \
              --arg chatUrl ${lib.escapeShellArg chatUrl} \
              --arg chatCss ${lib.escapeShellArg cfg.twitch.chat.css} \
              --rawfile alertsUrl "$alertsUrlFile" \
              --arg captionsFile ${lib.escapeShellArg cfg.accessibility.captions.textFile} \
              --arg privacyText ${lib.escapeShellArg cfg.privacy.text} \
              --argjson chatEnabled ${lib.boolToString cfg.twitch.chat.enable} \
              --argjson alertsEnabled ${lib.boolToString cfg.alerts.enable} \
              --argjson captionsEnabled ${lib.boolToString cfg.accessibility.captions.enable} \
              --argjson keystrokesEnabled ${lib.boolToString cfg.accessibility.keystrokeCallouts.enable} \
              --argjson secondMonitorEnabled ${lib.boolToString cfg.secondMonitor.enable} \
              --argjson privacyEnabled ${lib.boolToString cfg.privacy.enable} \
              --argjson micFiltersEnabled ${lib.boolToString cfg.audio.microphone.filters.enable} \
              --argjson cleanRecordingEnabled ${lib.boolToString cfg.cleanRecording.enable} \
              --argjson showCursor ${lib.boolToString cfg.accessibility.showCursor} \
              --argjson shaderWidth ${toString cfg.video.outputWidth} \
              --argjson shaderHeight ${toString cfg.video.outputHeight} \
              --argjson shaderFps ${toString (if cfg.video.fps < 30 then cfg.video.fps else 30)} \
              --argjson micFilters ${lib.escapeShellArg (builtins.toJSON microphoneFilters)} \
              --argjson cleanRecordingFilter ${lib.escapeShellArg (builtins.toJSON cleanRecordingFilter)} \
              --argjson width ${toString cfg.video.baseWidth} \
              --argjson height ${toString cfg.video.baseHeight} \
              --slurpfile template ${sceneTemplate} \
              "$sourceScene" > "$temporaryScene"
            chmod 0600 "$temporaryScene"
            mv "$temporaryScene" "$sceneFile"
            if [[ -n "$temporaryAlertsUrlFile" ]]; then
              rm -f "$temporaryAlertsUrlFile"
            fi

            touch "$userConfig"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic Profile "$profileName"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic ProfileDir "$profileName"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollection "$sceneCollection"
            ${lib.getExe pkgs.crudini} --set "$userConfig" Basic SceneCollectionFile "$sceneCollection.json"
          fi
        '';
      })

      {
        home.activation.writeObsWebSocket = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -z "$DRY_RUN_CMD" ]]; then
            configuredPasswordFile=${
              lib.escapeShellArg (if cfg.webSocket.passwordFile == null then "" else cfg.webSocket.passwordFile)
            }
            pluginDir="${config.xdg.configHome}/obs-studio/plugin_config/obs-websocket"
            configFile="$pluginDir/config.json"
            temporaryConfig="$pluginDir/config.json.new"
            temporaryPasswordFile=""
            install -d -m 0700 "$pluginDir"

            if ${lib.boolToString cfg.webSocket.enable}; then
              passwordFile="$configuredPasswordFile"
              if [[ ! -r "$passwordFile" ]]; then
                printf 'OBS WebSocket password file is not readable: %s\n' "$passwordFile" >&2
                exit 1
              fi
              if [[ -z "$(tr -d '\r\n' < "$passwordFile")" ]]; then
                printf 'OBS WebSocket password file is empty: %s\n' "$passwordFile" >&2
                exit 1
              fi
            else
              temporaryPasswordFile="$pluginDir/.password.empty"
              install -m 0600 /dev/null "$temporaryPasswordFile"
              passwordFile="$temporaryPasswordFile"
            fi

            umask 077
            ${lib.getExe pkgs.jq} -n \
              --rawfile password "$passwordFile" \
              --argjson enabled ${lib.boolToString cfg.webSocket.enable} \
              --argjson port ${toString cfg.webSocket.port} \
              '{
                first_load: false,
                server_enabled: $enabled,
                server_port: $port,
                alerts_enabled: false,
                auth_required: $enabled,
                server_password: ($password | sub("\\r?\\n$"; ""))
              }' > "$temporaryConfig"
            chmod 0600 "$temporaryConfig"
            mv "$temporaryConfig" "$configFile"
            if [[ -n "$temporaryPasswordFile" ]]; then
              rm -f "$temporaryPasswordFile"
            fi
          fi
        '';
      }

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
