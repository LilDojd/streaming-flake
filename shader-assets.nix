{ pkgs, shaderDesk }:
pkgs.symlinkJoin {
  name = "streaming-obs-shaders";
  paths = [
    ./shaders
    (pkgs.writeTextDir "shaders.js" ''
      window.shaderDeskShaders = ${
        builtins.toJSON {
          synthwaveVertex = builtins.readFile "${shaderDesk}/plugins/synthwave-terrain/shaders/terrain_vert.glsl";
          synthwaveFragment = builtins.readFile "${shaderDesk}/plugins/synthwave-terrain/shaders/terrain_frag.glsl";
          cosmicFragment = builtins.readFile "${shaderDesk}/plugins/shadertoy-effect/shaders/cosmic_strings.glsl";
        }
      };
    '')
    (pkgs.writeTextDir "ATTRIBUTION" ''
      Shader Desk: https://github.com/KMartianov/shader-desk (MPL-2.0)
      Synthwave Terrain: KMartianov / Shader Desk
      Cosmic Strings: Kazoops; Shader Desk port from https://openprocessing.org/@Kazoops/2983233
    '')
    (pkgs.writeTextDir "LICENSE.shader-desk" (builtins.readFile "${shaderDesk}/LICENSE"))
  ];
}
