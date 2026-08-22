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

## Customization

Common options include:

- `profileName` and `sceneCollectionName`
- `recordingDirectory`
- `video.baseWidth`, `video.baseHeight`, `video.outputWidth`,
  `video.outputHeight`, and `video.fps`
- `twitch.channel`, `twitch.chat.url`, and `twitch.chat.css`
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
