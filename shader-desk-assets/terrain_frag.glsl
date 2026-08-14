#version 300 es
precision highp float;

in vec3 FragPos;
in vec3 vBary;
in float vElevation;
in float vAudio; 
in float vZDistance;
in float vRoadMask;

uniform vec3 wireframe_color;
uniform vec3 fill_color;
uniform vec3 fog_color;
uniform vec3 color_bass;
uniform float road_glow_intensity;

uniform float fog_distance;
uniform float line_width;

uniform float time;
uniform float speed;
uniform float audio_volume;
uniform vec3 viewPos;

out vec4 FragColor;

void main() {
    // 1. NEON WIREFRAME RENDERING WITH BLOOM HALO
    float minBary = min(min(vBary.x, vBary.y), vBary.z);
    float edgeWidth = fwidth(minBary) * line_width;
    
    float line_mix = smoothstep(edgeWidth + 0.02, edgeWidth, minBary);
    float bloom_mix = smoothstep(edgeWidth + 0.2, edgeWidth, minBary);
    
    // 2. AUDIO-REACTIVE COLOR GRADIENT
    // As the sound wave peaks, the line color shifts from Cyan to Hot Pink
    vec3 current_wire_color = mix(wireframe_color, color_bass, clamp(vAudio * 1.5, 0.0, 1.0));
    
    // Add white-hot glow strictly to the crests of the traveling sound waves
    float peak_glow = pow(clamp(vAudio, 0.0, 1.0), 2.5) * 2.0;
    current_wire_color += vec3(1.0, 0.9, 0.8) * peak_glow;
    
    // 3. ROAD VU METER (Running Lights)
    float inverted_road = 1.0 - vRoadMask;
    if (inverted_road > 0.01) {
        float stripes = fract(vZDistance * 0.5 - time * speed * 2.0);
        float stripe_glow = smoothstep(0.8, 1.0, stripes);
        
        float distance_fade = 1.0 - clamp(vZDistance / 40.0, 0.0, 1.0);
        float final_road_glow = stripe_glow * audio_volume * road_glow_intensity * distance_fade * inverted_road;
        
        current_wire_color += color_bass * (final_road_glow * 2.0);
        bloom_mix += final_road_glow; 
    }

    // 4. FINAL COMPOSITION
    vec3 base_color = fill_color;
    
    // Soft neon ground reflection
    base_color += current_wire_color * bloom_mix * 0.4;
    
    // Sharp solid wireframe lines
    base_color = mix(base_color, current_wire_color, line_mix);
    
    // 5. DEPTH FOG
    float dist = length(viewPos - FragPos);
    float fog_factor = smoothstep(fog_distance * 0.2, fog_distance, dist);
    
    vec3 final_color = mix(base_color, fog_color, fog_factor);
    
    if (fog_factor > 0.99) {
        discard;
    }

    FragColor = vec4(final_color, 1.0);
}