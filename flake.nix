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
      shaderAssets = import ./shader-assets.nix { inherit pkgs; };
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
              twitchStreamKeyFile = "/run/agenix/twitchStreamKey";
            };
          }
        ];
      };
    in
    {
      homeManagerModules.default = import ./module.nix;
      checks.${system}.default = import ./check.nix {
        inherit pkgs testHome;
      };
      packages.${system}.shader-assets = shaderAssets;
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
