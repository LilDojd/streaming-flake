{
  pkgs,
  recordingOnlyHome,
  testHome,
}:
let
  cfg = testHome.config;
  recordingCfg = recordingOnlyHome.config;
  sceneTemplate = ./scenes.json;
  sceneActivation = pkgs.writeText "install-obs-scene" cfg.home.activation.installObsScene.data;
  twitchActivationScript = pkgs.writeText "write-twitch-service" cfg.home.activation.writeTwitchService.data;
  webSocketActivationScript = pkgs.writeText "write-obs-websocket" cfg.home.activation.writeObsWebSocket.data;
  disabledWebSocketActivationScript = pkgs.writeText "disable-obs-websocket" recordingCfg.home.activation.writeObsWebSocket.data;
  expectedPlugins = with pkgs.obs-studio-plugins; [
    obs-pipewire-audio-capture
    obs-source-record
    obs-composite-blur
  ];
in
assert cfg.programs.streaming-obs.enable;
assert cfg.programs.streaming-obs.twitch.enable;
assert cfg.programs.streaming-obs.twitch.streamKeyFile == "/run/agenix/twitchStreamKey";
assert cfg.programs.streaming-obs.twitch.channel == "test_channel";
assert cfg.programs.streaming-obs.twitch.chat.enable;
assert cfg.programs.obs-studio.enable;
assert recordingCfg.programs.streaming-obs.enable;
assert !recordingCfg.programs.streaming-obs.twitch.enable;
assert !(recordingCfg.home.activation ? writeTwitchService);
assert recordingCfg.programs.obs-studio.enable;
assert cfg.programs.obs-studio.plugins == expectedPlugins;
pkgs.runCommand "streaming-obs-module-check"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.jq
      pkgs.nodejs
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.obsws-python ]))
    ];
  }
  ''
    profile="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/basic.ini"
    streamEncoder="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/streamEncoder.json"
    recordEncoder="${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/recordEncoder.json"

    grep -q '^Mode=Advanced$' "$profile"
    grep -q '^BaseCX=2560$' "$profile"
    grep -q '^BaseCY=1440$' "$profile"
    grep -q '^OutputCX=1920$' "$profile"
    grep -q '^OutputCY=1080$' "$profile"
    grep -q '^FPSCommon=60$' "$profile"
    grep -q '^RecFormat2=mkv$' "$profile"
    grep -q '^RecTracks=7$' "$profile"
    grep -q '^AutoRemux=true$' "$profile"
    grep -q '^TrackIndex=1$' "$profile"
    jq -e '.rate_control == "CBR" and .bitrate == 6000 and .keyint_sec == 2' "$streamEncoder"
    jq -e '.rate_control == "CQP" and .cqp == 20' "$recordEncoder"
    jq -e '.name == "Programming" and .modules["streaming-flake"].version == 3' "${sceneTemplate}"
    jq -e '[.scene_order[].name] | index("Programming") != null and index("Second Monitor") != null and index("Privacy") != null' "${sceneTemplate}"
    jq -e '.DesktopAudioDevice1.mixers == 3 and .AuxAudioDevice1.mixers == 5' "${sceneTemplate}"
    jq -e '[.sources[] | select(.id == "pipewire-screen-capture-source")] | length == 2' "${sceneTemplate}"
    jq -e '[.sources[].uuid] as $uuids | ($uuids | unique | length) == ($uuids | length)' "${sceneTemplate}"
    jq -e 'all(.sources[] | select(.id == "scene");
      [.settings.items[].id] as $ids | ($ids | unique | length) == ($ids | length))' "${sceneTemplate}"
    jq -e '[.sources[].uuid] as $uuids | all(.sources[] | select(.id == "scene") | .settings.items[]; .source_uuid as $uuid | $uuids | index($uuid) != null)' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Programming") | [.settings.items[].source_uuid] == ["dddddddd-dddd-4ddd-8ddd-dddddddddddd", "ffffffff-ffff-4fff-8fff-ffffffffffff"]' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Second Monitor") | [.settings.items[].source_uuid] == ["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", "ffffffff-ffff-4fff-8fff-ffffffffffff"]' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "[Component] Secondary Monitor") | .settings.items[0] |
      .rot == 90 and .align == 0 and .pos == {x: 1280, y: 720} and
      .bounds == {x: 1440, y: 2560}' "${sceneTemplate}"
    jq -e '.sources as $sources | .sources[] | select(.name == "Privacy") |
      all(.settings.items[]; .source_uuid as $uuid | $sources[] | select(.uuid == $uuid) |
        .id != "pipewire-screen-capture-source" and .id != "browser_source" and .id != "scene")' "${sceneTemplate}"
    jq -e '[.AuxAudioDevice1.filters[].id] == ["noise_suppress_filter", "expander_filter", "compressor_filter", "limiter_filter"]' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "[Component] Primary Monitor") | .filters[0].id == "source_record_filter" and .filters[0].settings.record_mode == 3' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Live Captions") | .id == "text_ft2_source" and .settings.from_file' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Keystroke Display") | .id == "text_ft2_source"' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Twitch Chat" or .name == "Stream Alerts") | .settings.url == ""' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Stream Alerts") | .mixers == 1 and .settings.reroute_audio' "${sceneTemplate}"
    grep -q 'SceneCollection.*sceneCollection' "${sceneActivation}"
    grep -q 'sceneFile.backup' "${sceneActivation}"
    python -m py_compile ${./obs-control.py}
    python - <<'PY'
    import importlib.util
    spec = importlib.util.spec_from_file_location("obs_control", "${./obs-control.py}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    class Response:
        response_data = {"success": False, "error": "not recording"}

    class Client:
        def call_vendor_request(self, *_args, **_kwargs):
            return Response()

    try:
        module.clean_recording_request(Client(), "record_stop")
    except RuntimeError as error:
        assert str(error) == "not recording"
    else:
        raise AssertionError("Source Record rejection was ignored")
    PY
    grep -q -- '--rawfile alertsUrl' "${sceneActivation}"
    grep -q -- '--rawfile password' "${webSocketActivationScript}"
    if grep -q -E -- '--arg (alertsUrl|password)' "${sceneActivation}" "${webSocketActivationScript}"; then
      exit 1
    fi

    activation="$PWD/install-obs-scene"
    configDir="$PWD/obs-studio"
    sceneFile="$configDir/basic/scenes/Programming.json"
    userConfig="$configDir/user.ini"
    cleanDirectory="$PWD/clean-recordings"
    captionFile="$PWD/captions/current.txt"
    alertsUrlFile="$PWD/alerts-url"
    printf '%s\n' 'https://alerts.example.invalid/widget/runtime-token' > "$alertsUrlFile"
    substitute "${sceneActivation}" "$activation" \
      --replace-fail "${cfg.xdg.configHome}/obs-studio" "$configDir" \
      --replace-fail "${cfg.programs.streaming-obs.cleanRecording.directory}" "$cleanDirectory" \
      --replace-fail "${cfg.programs.streaming-obs.accessibility.captions.textFile}" "$captionFile" \
      --replace-fail "/run/agenix/streamAlertsUrl" "$alertsUrlFile"

    mkdir -p "$(dirname "$sceneFile")"
    jq '(.sources[] | select(.uuid == "33333333-3333-4333-8333-333333333333") | .settings.RestoreToken) = "primary-token-123" |
        .modules["streaming-flake"].version = 2 |
        .transition_duration = 987 |
        .sources |= map(select(.name != "Twitch Chat" and
          .name != "Secondary Monitor Capture" and
          .name != "Second Monitor" and
          .name != "Privacy" and
          .name != "Privacy Text" and
          .name != "[Component] Primary Monitor" and
          .name != "[Component] Secondary Monitor" and
          .name != "[Component] Stream Overlay")) |
        .AuxAudioDevice1.filters += [{
          name: "User Gain",
          uuid: "21212121-2121-4121-8121-212121212121",
          id: "gain_filter",
          versioned_id: "gain_filter",
          settings: { db: 2.5 },
          enabled: true,
          hotkeys: {}
        }] |
        .sources += [{
          name: "User Custom Source",
          uuid: "20202020-2020-4020-8020-202020202020",
          id: "color_source",
          versioned_id: "color_source_v3",
          settings: { color: 4294901760, width: 320, height: 180 }
        }] |
        (.sources[] | select(.name == "Programming") | .settings.items) += [{
          name: "User Custom Source",
          source_uuid: "20202020-2020-4020-8020-202020202020",
          visible: true,
          id: 99,
          align: 5,
          pos: { x: 123, y: 456 },
          scale: { x: 1.25, y: 1.25 }
        }]' \
      "${sceneTemplate}" > "$sceneFile"
    DRY_RUN_CMD= ${pkgs.runtimeShell} "$activation"
    jq -e '.modules["streaming-flake"].version == 3 and .transition_duration == 987' "$sceneFile"
    jq -e '.sources[] | select(.name == "Programming") | [.settings.items[] |
      select(.source_uuid == "20202020-2020-4020-8020-202020202020" and
        .pos == {x: 123, y: 456} and .scale == {x: 1.25, y: 1.25})] | length == 1' "$sceneFile"
    jq -e '.sources[] | select(.uuid == "33333333-3333-4333-8333-333333333333") | .settings.RestoreToken == "primary-token-123"' "$sceneFile"
    jq -e '.sources[] | select(.name == "Twitch Chat") | .settings.url == "https://nightdev.com/hosted/obschat?channel=test_channel&style=clear&fade=30&bot_activity=false&prevent_clipping=true"' "$sceneFile"
    jq -e '.sources[] | select(.name == "Stream Alerts") | .settings.url == "https://alerts.example.invalid/widget/runtime-token"' "$sceneFile"
    jq -e '.sources[] | select(.name == "Live Captions") | .settings.text_file == $captionFile' --arg captionFile "$captionFile" "$sceneFile"
    jq -e '[.sources[] | select(.name == "Second Monitor" or .name == "Privacy")] | length == 2' "$sceneFile"
    jq -e '.sources[] | select(.name == "[Component] Secondary Monitor") | .settings.items[0] |
      .rot == 90 and .align == 0 and .pos == {x: 1280, y: 720} and
      .bounds == {x: 1440, y: 2560}' "$sceneFile"
    jq -e '.sources[] | select(.name == "[Component] Primary Monitor") | .filters[0].settings.path == $path' --arg path "$cleanDirectory" "$sceneFile"
    jq -e '[.AuxAudioDevice1.filters[].id] == ["noise_suppress_filter", "expander_filter", "compressor_filter", "limiter_filter", "gain_filter"]' "$sceneFile"
    test -e "$sceneFile.backup"
    test "$(stat -c %a "$captionFile")" = 600

    runTransform() {
      input="$1"
      chat="$2"
      alerts="$3"
      captions="$4"
      keystrokes="$5"
      output="$6"
      jq \
        --from-file ${./scene-transform.jq} \
        --arg collectionName Programming \
        --arg synthwaveShader /tmp/synthwave.html \
        --arg cosmicShader /tmp/cosmic.html \
        --arg primaryRestoreToken primary-token \
        --arg secondaryRestoreToken secondary-token \
        --arg chatUrl https://chat.invalid \
        --arg chatCss "" \
        --rawfile alertsUrl "$alertsUrlFile" \
        --arg captionsFile "$captionFile" \
        --arg privacyText PRIVACY \
        --argjson chatEnabled "$chat" \
        --argjson alertsEnabled "$alerts" \
        --argjson captionsEnabled "$captions" \
        --argjson keystrokesEnabled "$keystrokes" \
        --argjson secondMonitorEnabled true \
        --argjson privacyEnabled true \
        --argjson micFiltersEnabled true \
        --argjson cleanRecordingEnabled true \
        --argjson showCursor true \
        --argjson shaderWidth 1920 \
        --argjson shaderHeight 1080 \
        --argjson shaderFps 30 \
        --argjson micFilters "$(jq -c '.AuxAudioDevice1.filters' ${sceneTemplate})" \
        --argjson cleanRecordingFilter "$(jq -c '.sources[] | select(.name == "[Component] Primary Monitor") | .filters[0]' ${sceneTemplate})" \
        --argjson width 2560 \
        --argjson height 1440 \
        --slurpfile template ${sceneTemplate} \
        "$input" > "$output"
    }

    disabledScene="$PWD/disabled-scene.json"
    reenabledScene="$PWD/reenabled-scene.json"
    runTransform "$sceneFile" false false false false "$disabledScene"
    runTransform "$disabledScene" true true true true "$reenabledScene"
    jq -e '.sources[] | select(.name == "[Component] Stream Overlay") |
      [.settings.items[].source_uuid] | sort == [
        "12121212-1212-4212-8212-121212121212",
        "13131313-1313-4313-8313-131313131313",
        "17171717-1717-4717-8717-171717171717",
        "99999999-9999-4999-8999-999999999999"
      ]' "$reenabledScene"

    startingSoonShader="$(jq -r '.sources[] | select(.name == "Synthwave Terrain") | .settings.local_file' "$sceneFile")"
    brbShader="$(jq -r '.sources[] | select(.name == "Cosmic Strings") | .settings.local_file' "$sceneFile")"
    jq -e 'all(.sources[] | select(.name == "Synthwave Terrain" or .name == "Cosmic Strings");
      .settings.width == 1920 and .settings.height == 1080 and .settings.fps == 30)' "$sceneFile"
    test -r "$startingSoonShader"
    test -r "$brbShader"
    node --check "$(dirname "$startingSoonShader")/runner.js"
    node --check "$(dirname "$startingSoonShader")/shaders.js"
    grep -q 'synthwaveSkyFragment' "$(dirname "$startingSoonShader")/runner.js"
    grep -q 'shockwavePhase' "$(dirname "$startingSoonShader")/runner.js"
    grep -q 'KMartianov/shader-desk' "$(dirname "$startingSoonShader")/ATTRIBUTION"

    printf '[Basic]\nProfile=DryRunSentinel\n' > "$userConfig"
    cp "$sceneFile" scene.before
    cp "$userConfig" user.before
    DRY_RUN_CMD=echo ${pkgs.runtimeShell} "$activation"
    cmp scene.before "$sceneFile"
    cmp user.before "$userConfig"
    test ! -e "$sceneFile.new"

    webSocketActivation="$PWD/write-obs-websocket"
    webSocketConfigDir="$PWD/websocket-config"
    webSocketPasswordFile="$PWD/websocket-password"
    substitute "${webSocketActivationScript}" "$webSocketActivation" \
      --replace-fail "${cfg.xdg.configHome}" "$webSocketConfigDir" \
      --replace-fail "/run/agenix/obsWebSocketPassword" "$webSocketPasswordFile"

    DRY_RUN_CMD=echo ${pkgs.runtimeShell} "$webSocketActivation"
    test ! -e "$webSocketConfigDir"
    printf '  runtime-websocket-password  \r\n' > "$webSocketPasswordFile"
    DRY_RUN_CMD= ${pkgs.runtimeShell} "$webSocketActivation"
    webSocketConfig="$webSocketConfigDir/obs-studio/plugin_config/obs-websocket/config.json"
    jq -e '.server_enabled and .server_port == 4455 and .auth_required and
      .server_password == "  runtime-websocket-password  "' "$webSocketConfig"
    test "$(stat -c %a "$webSocketConfig")" = 600

    disabledWebSocketActivation="$PWD/disable-obs-websocket"
    substitute "${disabledWebSocketActivationScript}" "$disabledWebSocketActivation" \
      --replace-fail "${recordingCfg.xdg.configHome}" "$webSocketConfigDir"
    DRY_RUN_CMD= ${pkgs.runtimeShell} "$disabledWebSocketActivation"
    jq -e '.server_enabled == false and .auth_required == false and .server_password == ""' "$webSocketConfig"

    twitchActivation="$PWD/write-twitch-service"
    twitchConfigDir="$PWD/twitch-config"
    twitchProfileDir="$twitchConfigDir/obs-studio/basic/profiles/Programming"
    twitchServiceFile="$twitchProfileDir/service.json"
    dummyKeyFile="$PWD/dummy-twitch-key"
    substitute "${twitchActivationScript}" "$twitchActivation" \
      --replace-fail "${cfg.xdg.configHome}" "$twitchConfigDir" \
      --replace-fail "/run/agenix/twitchStreamKey" "$dummyKeyFile"

    DRY_RUN_CMD=echo ${pkgs.runtimeShell} "$twitchActivation"
    test ! -e "$twitchConfigDir"

    expectTwitchFailure() {
      expectedError="$1"
      rm -f "$twitchServiceFile" "$twitchServiceFile.new"
      if DRY_RUN_CMD= ${pkgs.runtimeShell} "$twitchActivation" > twitch.stdout 2> twitch.stderr; then
        printf 'Expected Twitch activation failure: %s\n' "$expectedError" >&2
        return 1
      fi
      printf '%s\n' "$expectedError" > twitch.expected
      cmp twitch.expected twitch.stderr
      test ! -s twitch.stdout
      test ! -e "$twitchServiceFile"
      test ! -e "$twitchServiceFile.new"
    }

    rm -f "$dummyKeyFile"
    expectTwitchFailure "Twitch stream key is not readable: $dummyKeyFile"

    printf '%s\n' 'unreadable-key-content' > "$dummyKeyFile"
    chmod 000 "$dummyKeyFile"
    expectTwitchFailure "Twitch stream key is not readable: $dummyKeyFile"
    chmod 600 "$dummyKeyFile"

    : > "$dummyKeyFile"
    expectTwitchFailure "Twitch stream key is empty: $dummyKeyFile"

    printf '\r\n' > "$dummyKeyFile"
    expectTwitchFailure "Twitch stream key is empty: $dummyKeyFile"

    printf 'dummy-\r\nstream-key\r\n' > "$dummyKeyFile"
    DRY_RUN_CMD= ${pkgs.runtimeShell} "$twitchActivation"
    jq -e '.type == "rtmp_common" and .settings == {
      service: "Twitch",
      server: "auto",
      key: "dummy-stream-key",
      protocol: "RTMP"
    }' "$twitchServiceFile"
    test "$(stat -c %a "$twitchServiceFile")" = 600
    test ! -e "$twitchServiceFile.new"
    test ! -e "${cfg.home-files}/.config/obs-studio/basic/profiles/Programming/service.json"
    if grep -R -q -E 'live_|runtime-websocket-password|runtime-token' "${cfg.home-files}"; then
      exit 1
    fi
    touch "$out"
  ''
