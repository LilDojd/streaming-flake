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

## Automatic updates

Add a repository Actions secret named `GH_TOKEN_FOR_UPDATES`. Use a dedicated
token that can create pull requests in this repository. The daily workflow
opens a checked update pull request; Mergify merges it after `check` succeeds.
