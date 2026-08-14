#version 300 es
precision highp float;

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aBary;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform float time;

uniform float speed;
uniform float mountain_height;
uniform float road_width;
uniform float audio_reactivity;
uniform float grid_scale;

uniform float audio_bass;
uniform float audio_volume;
uniform sampler2D audio_history; 

uniform float shockwave_phase; 

out vec3 FragPos;
out vec3 vBary;
out float vElevation;
out float vAudio; 
out float vZDistance;
out float vRoadMask;

// ==============================================================================
// 2D SIMPLEX NOISE ALGORITHM
// ==============================================================================
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }
float snoise(vec2 v){
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 )) + i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m; m = m*m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

void main() {
    float cell_size = 1.0;
    float z_shift = mod(time * speed, cell_size);
    vec3 pos = aPos;
    pos.z += z_shift; 
    
    // 1. BASE TERRAIN (Subtle Noise for silent areas)
    float world_z = aPos.z - floor(time * speed);
    vec2 sample_pos = vec2(pos.x, world_z) * grid_scale;
    float n = snoise(sample_pos) * 0.5 + 0.5;
    n = pow(clamp(n, 0.0, 1.0), 2.5); 
    
    // 2. RUNNING SPECTROGRAM (The main visualizer)
    float abs_x = abs(pos.x);
    float road_mask = smoothstep(road_width, road_width + 4.0, abs_x);
    
    // U: Frequency mapping. 0.0 near road (Bass), 1.0 near outer edge (Treble)
    float raw_u = clamp((abs_x - road_width) / 40.0, 0.0, 1.0);
    float u = pow(raw_u, 0.4); // Curve stretches the bass to be wide and imposing
    
    // V: History mapping. 
    // CRITICAL FIX: We use aPos.z (the static un-shifted grid) instead of pos.z.
    // This perfectly locks the moving texture to the grid, creating smooth running waves
    // that travel away into the distance without wiggling.
    float v = clamp(abs(aPos.z) / 120.0, 0.0, 1.0);
    
    // Hardware accelerated bilinear fetch from the spectrogram
    float band_energy = texture(audio_history, vec2(u, v)).r;
    
    // Shape the audio wave into sharp mountain ridges
    float audio_wave = pow(band_energy, 1.5) * audio_reactivity * mountain_height;
    
    // 3. EVENT-DRIVEN SHOCKWAVE (Triggered by Lua Event Bus)
    float dist_from_cam = length(pos.xz);
    float wave_radius = shockwave_phase * 150.0; 
    float ring_thickness = max(0.0, 1.0 - abs(dist_from_cam - wave_radius) * 0.15);
    float shock_elevation = ring_thickness * pow(1.0 - shockwave_phase, 2.5) * (audio_bass * 15.0);

    // 4. COMBINE ELEVATION
    // The Audio Wave is now the dominant terrain. Noise is reduced to just 10% 
    // to give some texture to the valleys when the music is quiet.
    float elevation = (n * mountain_height * 0.1 + audio_wave + shock_elevation) * road_mask;
    
    pos.y += elevation;
    
    vAudio = band_energy; 
    vElevation = elevation;
    vBary = aBary;
    vZDistance = abs(pos.z);
    vRoadMask = road_mask;
    
    FragPos = vec3(model * vec4(pos, 1.0));
    gl_Position = projection * view * vec4(FragPos, 1.0);
}