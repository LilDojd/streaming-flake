{ pkgs }:
pkgs.symlinkJoin {
  name = "streaming-obs-shaders";
  paths = [
    ./shaders
    (pkgs.writeTextDir "shaders.js" ''
      window.shaderDeskShaders = ${
        builtins.toJSON {
          synthwaveVertex = builtins.readFile ./shader-desk-assets/terrain_vert.glsl;
          synthwaveFragment = builtins.readFile ./shader-desk-assets/terrain_frag.glsl;
          cosmicFragment = builtins.readFile ./shader-desk-assets/cosmic_strings.glsl;
        }
      };
    '')
    (pkgs.writeTextDir "ATTRIBUTION" (builtins.readFile ./shader-desk-assets/ATTRIBUTION))
    (pkgs.writeTextDir "LICENSE.shader-desk" (
      builtins.readFile ./shader-desk-assets/LICENSE.shader-desk
    ))
  ];
}
