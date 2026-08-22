{
  description = "Declarative OBS setup for programming streams";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      obsPackage = pkgs.obs-studio.override { cudaSupport = true; };
      shaderAssets = import ./shader-assets.nix { inherit pkgs; };
      launcher = pkgs.writeShellApplication {
        name = "streaming-obs";
        runtimeInputs = [ obsPackage ];
        text = ''
          exec obs --profile "''${OBS_PROFILE:-Programming}" \
            --collection "''${OBS_SCENE_COLLECTION:-Programming}" "$@"
        '';
      };
      testHome = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          self.homeManagerModules.default
          {
            home = {
              username = "test";
              homeDirectory = "/home/test";
              stateVersion = "25.11";
            };
            programs.streaming-obs = {
              enable = true;
              twitch = {
                enable = true;
                streamKeyFile = "/run/agenix/twitchStreamKey";
                channel = "test_channel";
                chat.enable = true;
              };
              alerts = {
                enable = true;
                urlFile = "/run/agenix/streamAlertsUrl";
              };
              accessibility = {
                captions.enable = true;
                keystrokeCallouts.enable = true;
              };
              webSocket = {
                enable = true;
                passwordFile = "/run/agenix/obsWebSocketPassword";
              };
            };
          }
        ];
      };
      recordingOnlyHome = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          self.homeManagerModules.default
          {
            home = {
              username = "recorder";
              homeDirectory = "/home/recorder";
              stateVersion = "25.11";
            };
            programs.streaming-obs.enable = true;
          }
        ];
      };
      optionDocs = pkgs.nixosOptionsDoc {
        options = testHome.options.programs.streaming-obs;
      };
    in
    {
      homeManagerModules.default = import ./module.nix;

      checks.${system}.default = import ./check.nix {
        inherit pkgs recordingOnlyHome testHome;
      };

      packages.${system} = {
        default = shaderAssets;
        shader-assets = shaderAssets;
        launcher = launcher;
        module-options = optionDocs.optionsCommonMark;
      };

      apps.${system}.default = {
        type = "app";
        program = "${launcher}/bin/streaming-obs";
      };

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          deadnix
          jq
          nixfmt-tree
          nodejs
          statix
        ];
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
