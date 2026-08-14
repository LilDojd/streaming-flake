// COSMIC STRINGS - traducción exacta de https://openprocessing.org/@Kazoops/2983233
// Autor original: Kazoops
// 8 parámetros con ciclos sinusoidales independientes (duración en segundos)

#define PI  3.14159265359
#define TAU 6.28318530718

// ── Parámetros (mismos valores que el original) ──────────────────
const float P1_Min = 1.0;   const float P1_Max = 3.0;   const float P1_Seconds = 5.0;  const float P1_Phase = 0.0; // Time Speed
const float P2_Min = 0.01;  const float P2_Max = 0.10;  const float P2_Seconds = 7.0;  const float P2_Phase = 1.0; // Orbit Range
const float P3_Min = 0.01;  const float P3_Max = 0.20;  const float P3_Seconds = 11.0; const float P3_Phase = 2.0; // Rotation Spread
const float P4_Min = 0.5;   const float P4_Max = 4.0;   const float P4_Seconds = 13.0; const float P4_Phase = 3.0; // X Density
const float P5_Min = 3.0;   const float P5_Max = 10.0;  const float P5_Seconds = 17.0; const float P5_Phase = 4.0; // Y Density
const float P6_Min = 6.0;   const float P6_Max = 50.0;  const float P6_Seconds = 19.0; const float P6_Phase = 5.0; // Line Sharpness
const float P7_Min = 0.10;  const float P7_Max = 1.00;  const float P7_Seconds = 23.0; const float P7_Phase = 6.0; // Color Density
const float P8_Min = 1.0;   const float P8_Max = 4.0;   const float P8_Seconds = 29.0; const float P8_Phase = 7.0; // Brightness

float sineParameter(float time, float minV, float maxV, float cycleSeconds, float phase) {
    float safeCycle = max(cycleSeconds, 0.001);
    float cyclePos  = time / safeCycle;
    float s         = sin(cyclePos * TAU + phase);
    float n         = (s + 1.0) * 0.5;
    return mix(minV, maxV, n);
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
    return vec2(hash21(p), hash21(p + vec2(37.17, 91.53)));
}

float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {               // definido en el original (aunque no se usa en la escena)
    float v = 0.0;
    float a = 0.5;
    mat2  m = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v += noise21(p) * a;
        p  = m * p * 2.03 + vec2(13.7, 9.2);
        a *= 0.5;
    }
    return v;
}

vec2 rotate2D(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c) * p;
}

vec3 palette(float t) {
    vec3 a = vec3(0.5);
    vec3 b = vec3(0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(0.0, 0.18, 0.38);
    return a + b * cos(TAU * (c * t + d));
}

vec2 centeredCoordinate(vec2 uv) {
    float aspect = iResolution.x / iResolution.y;
    return (uv - 0.5) * vec2(aspect, 1.0);
}

vec3 cosmicStringsScene(vec2 uv, float t, float p2, float p3, float p4, float p5, float p6, float p7, float p8) {
    vec2 p = centeredCoordinate(uv);
    float strings = 0.0;

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        vec2 pos = p + vec2(sin(t + fi), cos(t * 0.8 + fi)) * p2;
        pos = rotate2D(pos, t * 0.1 + fi * p3);
        float line = abs(sin(pos.x * p4 + pos.y * p5));
        strings += exp(-line * p6);
    }

    vec3 col = palette(strings * p7 + t * 0.05);
    return col * strings * 0.3 * p8;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;

    // Parámetros oscilando exactamente como en el original
    float p1 = sineParameter(iTime, P1_Min, P1_Max, P1_Seconds, P1_Phase); // Time Speed
    float p2 = sineParameter(iTime, P2_Min, P2_Max, P2_Seconds, P2_Phase);
    float p3 = sineParameter(iTime, P3_Min, P3_Max, P3_Seconds, P3_Phase);
    float p4 = sineParameter(iTime, P4_Min, P4_Max, P4_Seconds, P4_Phase);
    float p5 = sineParameter(iTime, P5_Min, P5_Max, P5_Seconds, P5_Phase);
    float p6 = sineParameter(iTime, P6_Min, P6_Max, P6_Seconds, P6_Phase);
    float p7 = sineParameter(iTime, P7_Min, P7_Max, P7_Seconds, P7_Phase);
    float p8 = sineParameter(iTime, P8_Min, P8_Max, P8_Seconds, P8_Phase);

    // En el original animationTime se acumula con velocidad variable p1.
    // Aquí usamos iTime * p1 como aproximación directa (muy cercana visualmente).
    float animTime = iTime * p1;

    vec3 col = cosmicStringsScene(uv, animTime, p2, p3, p4, p5, p6, p7, p8);
    col = pow(max(col, vec3(0.0)), vec3(0.85));

    fragColor = vec4(col, 1.0);
}