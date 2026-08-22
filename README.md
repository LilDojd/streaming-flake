# streaming-flake

Declarative, Linux-only Home Manager configuration for OBS programming streams.
It provides an NVIDIA-accelerated profile, a managed scene collection, vendored
WebGL backgrounds, separate stream/desktop/microphone audio tracks, and optional
Twitch service configuration.

## Use

```nix
{
  inputs.streaming-flake.url = "github:LilDojd/streaming-flake";

  imports = [ inputs.streaming-flake.homeManagerModules.default ];

  programs.streaming-obs = {
    enable = true;

    profileName = "Programming";
    sceneCollectionName = "Programming";
    recordingDirectory = "${config.xdg.userDirs.videos}/OBS";

    twitch = {
      enable = true;
      streamKeyFile = "/run/agenix/twitchStreamKey";
      channel = "my_channel";
      chat.enable = true;
    };

    webSocket = {
      enable = true;
      passwordFile = "/run/agenix/obsWebSocketPassword";
    };

    alerts = {
      enable = true;
      urlFile = "/run/agenix/streamAlertsUrl";
    };

    accessibility = {
      captions.enable = true;
      keystrokeCallouts.enable = true;
    };
  };
}
```

The key file is optional unless `twitch.enable` is true. When enabled, it must
exist at Home Manager activation time. The module reads it only during
activation and writes OBS `service.json` with mode `0600`.

OBS can also be used only for recording:

```nix
programs.streaming-obs.enable = true;
```

## Scene ownership

`scenes.overwrite` defaults to `false`. On the first activation the bundled
collection is installed. Later activations retain existing OBS edits and refresh
only fields managed by the module, such as shader paths, dimensions, and chat
settings. Set `scenes.overwrite = true` to restore the bundled template; the
previous collection is saved as `Programming.json.backup` by default.

## Scenes and controls

The collection contains reusable component scenes for the primary display,
secondary display, and stream overlays. Public scenes and their emergency
hotkeys are:

- `Second Monitor`: `Ctrl+Shift+F7`
- `Privacy`: `Ctrl+Shift+F8`
- streaming start/stop: `Ctrl+Shift+F9`
- recording start/stop: `Ctrl+Shift+F10`
- `BRB`: `Ctrl+Shift+F11`
- `Programming`: `Ctrl+Shift+F12`

After first activation, select each PipeWire capture source once in OBS and
choose the intended display. Their independent portal restore tokens survive
later activations and template upgrades.

`streaming-obs-control` provides authenticated OBS WebSocket v5 commands:

```console
streaming-obs-control scene privacy
streaming-obs-control scene live
streaming-obs-control scene second
streaming-obs-control mic toggle
streaming-obs-control clean-record start
streaming-obs-control callout "Ctrl+K — command palette"
```

Privacy control switches scenes before muting the microphone and stopping the
clean recording. The direct F8 scene hotkey remains available if WebSocket is
down, but it is visual privacy only: it cannot mute the microphone or stop a
Source Record session without WebSocket.

## Audio, clean recordings, and accessibility

The microphone defaults to RNNoise, an expander, a compressor, and a limiter.
Their thresholds are starting points and should be tuned using a local test
recording. The Source Record plugin records `[Component] Primary Monitor`
without chat, alerts, captions, or keystroke callouts.

Caption text is read from a transient runtime file. An external caption
producer should atomically replace that UTF-8 file. Keystroke callouts are
explicit messages sent through `streaming-obs-control`; global keyboard logging
is intentionally not enabled. Alert widget URLs are also read at activation
from a runtime file so their tokens never enter the Nix store.

## Customization

Common options include:

- `profileName` and `sceneCollectionName`
- `recordingDirectory`
- `video.baseWidth`, `video.baseHeight`, `video.outputWidth`,
  `video.outputHeight`, and `video.fps`
- `twitch.channel`, `twitch.chat.url`, and `twitch.chat.css`
- `secondMonitor`, `privacy`, `cleanRecording`, and `audio.microphone.filters`
- `alerts`, `accessibility`, and `webSocket`
- `extraPlugins`
- `extraProfileSettings`, `extraStreamEncoderSettings`, and
  `extraRecordEncoderSettings`

Build the complete generated option reference with:

```console
nix build .#module-options
```

## Other outputs

```console
nix develop              # jq, Node.js, deadnix, statix, and nixfmt-tree
nix run                   # launch the Programming OBS profile and collection
nix build                 # build the shader assets
nix build .#launcher      # build the OBS launcher
nix flake check -L
```

Override launcher names with `OBS_PROFILE` and `OBS_SCENE_COLLECTION`.

## Shader assets

The OBS scenes use shader sources vendored in `shader-desk-assets` from Shader
Desk revision `c63d758336962a9097f0b6bc3c8f1a5b61edbddb`. See the bundled
attribution and license files before redistributing or using them commercially;
`cosmic_strings.glsl` is licensed CC BY-NC-SA 4.0.

## License

The original Nix, HTML, JavaScript, and JSON code is MIT licensed. Files in
`shader-desk-assets` remain under their documented upstream licenses and are not
relicensed by this project.
