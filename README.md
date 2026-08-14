# streaming-flake

Linux-only Home Manager configuration for OBS programming streams and Twitch.

## Use

```nix
{
  inputs.streaming-flake.url = "github:LilDojd/streaming-flake";

  imports = [ inputs.streaming-flake.homeManagerModules.default ];

  programs.streaming-obs = {
    enable = true;
    twitchStreamKeyFile = "/run/agenix/twitchStreamKey";
  };
}
```

The key file must exist at Home Manager activation time. The module reads it
only at activation time and writes OBS `service.json` with mode `0600`.

## Shader assets

The OBS scenes use shader sources vendored in `shader-desk-assets` from Shader
Desk revision `c63d758336962a9097f0b6bc3c8f1a5b61edbddb`. See the bundled
attribution and license files before redistributing or using them commercially;
`cosmic_strings.glsl` is licensed CC BY-NC-SA 4.0.
