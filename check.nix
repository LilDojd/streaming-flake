{ pkgs, testHome }:
let
  cfg = testHome.config;
  sceneTemplate = ./scenes.json;
  sceneActivation = pkgs.writeText "install-obs-scene" cfg.home.activation.installObsScene.data;
  twitchActivationScript = pkgs.writeText "write-twitch-service" cfg.home.activation.writeTwitchService.data;
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
    jq -e '.name == "Programming"' "${sceneTemplate}"
    jq -e '[.scene_order[].name] == ["Starting Soon", "Programming", "BRB"]' "${sceneTemplate}"
    jq -e '.DesktopAudioDevice1.mixers == 3 and .AuxAudioDevice1.mixers == 5' "${sceneTemplate}"
    jq -e '[.sources[].id] | index("pipewire-screen-capture-source") != null' "${sceneTemplate}"
    jq -e '[.sources[] | select(.id == "browser_source")] | length == 1' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Twitch Chat") | .settings.url == "https://nightdev.com/hosted/obschat?channel=yawnere&style=clear&fade=30&bot_activity=false&prevent_clipping=true"' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Twitch Chat") | .settings.width == 520 and .settings.height == 620 and .settings.shutdown and .settings.restart_when_active' "${sceneTemplate}"
    jq -e '.sources[] | select(.name == "Programming") | [.settings.items[] | select(.source_uuid == "99999999-9999-4999-8999-999999999999" and .pos.x == 2000 and .pos.y == 780)] | length == 1' "${sceneTemplate}"
    jq -e '[.sources[] | select(.name == "Starting Soon" or .name == "BRB") | .settings.items[].source_uuid] | index("99999999-9999-4999-8999-999999999999") == null' "${sceneTemplate}"
    grep -q 'RestoreToken' "${sceneActivation}"
    grep -q 'SceneCollection.*Programming' "${sceneActivation}"

    activation="$PWD/install-obs-scene"
    configDir="$PWD/obs-studio"
    sceneFile="$configDir/basic/scenes/Programming.json"
    userConfig="$configDir/user.ini"
    substitute "${sceneActivation}" "$activation" \
      --replace-fail "${cfg.xdg.configHome}/obs-studio" "$configDir"

    mkdir -p "$(dirname "$sceneFile")"
    jq '(.sources[] | select(.id == "pipewire-screen-capture-source") | .settings.RestoreToken) = "portal-token-123"' \
      "${sceneTemplate}" > "$sceneFile"
    DRY_RUN_CMD= ${pkgs.runtimeShell} "$activation"
    jq -e '.sources[] | select(.id == "pipewire-screen-capture-source") | .settings.RestoreToken == "portal-token-123"' \
      "$sceneFile"

    printf '[Basic]\nProfile=DryRunSentinel\n' > "$userConfig"
    cp "$sceneFile" scene.before
    cp "$userConfig" user.before
    DRY_RUN_CMD=echo ${pkgs.runtimeShell} "$activation"
    cmp scene.before "$sceneFile"
    cmp user.before "$userConfig"
    test ! -e "$sceneFile.new"

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
    if grep -R -q 'live_' "${cfg.home-files}"; then
      exit 1
    fi
    touch "$out"
  ''
