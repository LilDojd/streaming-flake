(() => {
  "use strict";

  const canvas = document.getElementById("shader");
  const gl = canvas.getContext("webgl2", {
    alpha: false,
    antialias: true,
    powerPreference: "high-performance",
  });
  if (!gl) throw new Error("WebGL 2 is required");

  const shaders = window.shaderDeskShaders;
  const fullscreenVertex = `#version 300 es
    void main() {
      vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
      gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    }`;
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader));
    }
    return shader;
  };
  const link = (vertex, fragment) => {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(program));
    }
    return program;
  };
  const resize = () => {
    const width = Math.max(1, canvas.clientWidth);
    const height = Math.max(1, canvas.clientHeight);
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    gl.viewport(0, 0, width, height);
  };

  const startCosmic = () => {
    const fragment = `#version 300 es
      precision highp float;
      uniform vec3 iResolution;
      uniform float iTime;
      uniform vec4 iMouse;
      out vec4 outputColor;
      ${shaders.cosmicFragment}
      void main() { mainImage(outputColor, gl_FragCoord.xy); }`;
    const program = link(fullscreenVertex, fragment);
    const resolution = gl.getUniformLocation(program, "iResolution");
    const time = gl.getUniformLocation(program, "iTime");
    const mouse = gl.getUniformLocation(program, "iMouse");
    gl.bindVertexArray(gl.createVertexArray());
    gl.useProgram(program);
    gl.uniform4f(mouse, 0, 0, 0, 0);

    const render = (now) => {
      resize();
      gl.uniform3f(resolution, canvas.width, canvas.height, 1);
      gl.uniform1f(time, now * 0.001);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      requestAnimationFrame(render);
    };
    render(performance.now());
  };

  const synthwaveSkyFragment = `#version 300 es
    precision highp float;
    uniform vec2 resolution;
    uniform float time;
    out vec4 outputColor;

    float hash(vec2 p) {
      return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    void main() {
      vec2 uv = gl_FragCoord.xy / resolution;
      float horizon = 0.43;
      vec3 sky = mix(vec3(0.16, 0.012, 0.18), vec3(0.008, 0.001, 0.035), smoothstep(horizon, 1.0, uv.y));

      vec2 sunPoint = (uv - vec2(0.5, 0.57)) * vec2(resolution.x / resolution.y, 1.0);
      float distanceToSun = length(sunPoint);
      float radius = 0.17 + sin(time * 1.8) * 0.008;
      float disc = 1.0 - smoothstep(radius - 0.003, radius + 0.003, distanceToSun);
      float stripes = step(0.22, fract((uv.y - time * 0.018) * 38.0));
      vec3 sunColor = mix(vec3(1.0, 0.08, 0.55), vec3(1.0, 0.75, 0.08), smoothstep(0.42, 0.7, uv.y));
      float glow = exp(-distanceToSun * 9.0) * (0.7 + sin(time * 1.8) * 0.1);
      sky += sunColor * glow * 0.7;
      sky = mix(sky, sunColor, disc * stripes);

      vec2 starCell = floor(gl_FragCoord.xy / 7.0);
      float starSeed = hash(starCell);
      float twinkle = 0.45 + 0.55 * sin(time * (1.5 + starSeed * 2.0) + starSeed * 6.283);
      float stars = step(0.994, starSeed) * twinkle * smoothstep(horizon, 0.65, uv.y);
      sky += stars * mix(vec3(0.3, 0.7, 1.0), vec3(1.0, 0.35, 0.8), starSeed);

      outputColor = vec4(sky, 1.0);
    }`;

  const perspective = (fov, aspect, near, far) => {
    const f = 1 / Math.tan(fov / 2);
    return new Float32Array([
      f / aspect, 0, 0, 0,
      0, f, 0, 0,
      0, 0, (far + near) / (near - far), -1,
      0, 0, (2 * far * near) / (near - far), 0,
    ]);
  };
  const normalize = ([x, y, z]) => {
    const length = Math.hypot(x, y, z);
    return [x / length, y / length, z / length];
  };
  const cross = ([ax, ay, az], [bx, by, bz]) => [
    ay * bz - az * by,
    az * bx - ax * bz,
    ax * by - ay * bx,
  ];
  const lookAt = (eye, center) => {
    const z = normalize(eye.map((value, index) => value - center[index]));
    const x = normalize(cross([0, 1, 0], z));
    const y = cross(z, x);
    return new Float32Array([
      x[0], y[0], z[0], 0,
      x[1], y[1], z[1], 0,
      x[2], y[2], z[2], 0,
      -x.reduce((sum, value, index) => sum + value * eye[index], 0),
      -y.reduce((sum, value, index) => sum + value * eye[index], 0),
      -z.reduce((sum, value, index) => sum + value * eye[index], 0),
      1,
    ]);
  };

  const startSynthwave = () => {
    const skyProgram = link(fullscreenVertex, synthwaveSkyFragment);
    const skyVao = gl.createVertexArray();
    const skyResolution = gl.getUniformLocation(skyProgram, "resolution");
    const skyTime = gl.getUniformLocation(skyProgram, "time");
    const program = link(shaders.synthwaveVertex, shaders.synthwaveFragment);
    const vertices = new Float32Array(80 * 120 * 6 * 6);
    let offset = 0;
    const add = (x, z, bx, by, bz) => {
      vertices.set([x, 0, z, bx, by, bz], offset);
      offset += 6;
    };
    for (let z = 0; z < 120; z += 1) {
      for (let x = 0; x < 80; x += 1) {
        const x0 = x - 40;
        const z0 = -z;
        add(x0, z0, 1, 0, 0);
        add(x0 + 1, z0, 0, 1, 0);
        add(x0, z0 - 1, 0, 0, 1);
        add(x0 + 1, z0, 1, 0, 0);
        add(x0 + 1, z0 - 1, 0, 1, 0);
        add(x0, z0 - 1, 0, 0, 1);
      }
    }

    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 24, 0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 3, gl.FLOAT, false, 24, 12);

    const audioTexture = gl.createTexture();
    const audioHistory = new Uint8Array(64 * 128);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, audioTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);

    const location = (name) => gl.getUniformLocation(program, name);
    const projectionLocation = location("projection");
    const timeLocation = location("time");
    const shockwavePhase = location("shockwave_phase");
    const identity = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    const eye = [0, 2.2, 5];
    gl.useProgram(program);
    gl.uniformMatrix4fv(location("model"), false, identity);
    gl.uniformMatrix4fv(location("view"), false, lookAt(eye, [0, 1.7, -25]));
    gl.uniform3fv(location("viewPos"), eye);
    gl.uniform1f(location("speed"), -5);
    gl.uniform1f(location("mountain_height"), 5.5);
    gl.uniform1f(location("road_width"), 3.5);
    gl.uniform1f(location("audio_reactivity"), 2.8);
    gl.uniform1f(location("grid_scale"), 0.15);
    gl.uniform3f(location("wireframe_color"), 0, 0.8, 1);
    gl.uniform3f(location("color_bass"), 1, 0, 0.5);
    gl.uniform3f(location("fill_color"), 0.02, 0.01, 0.05);
    gl.uniform3f(location("fog_color"), 0.05, 0.01, 0.08);
    gl.uniform1f(location("fog_distance"), 60);
    gl.uniform1f(location("line_width"), 1);
    gl.uniform1f(location("road_glow_intensity"), 0.5);
    gl.uniform1f(location("audio_bass"), 0.6);
    gl.uniform1f(location("audio_volume"), 0.8);
    gl.uniform1i(location("audio_history"), 2);
    gl.enable(gl.DEPTH_TEST);

    const render = (now) => {
      resize();
      const seconds = now * 0.001;
      // ponytail: Procedural history keeps this source self-contained; use Web Audio if OBS exposes source audio.
      for (let y = 0; y < 128; y += 1) {
        for (let x = 0; x < 64; x += 1) {
          const phase = seconds - y * 0.035;
          const wave = Math.sin(phase * (2.2 + x * 0.025) + x * 0.38) * 0.5 + 0.5;
          const pulse = Math.max(0, Math.sin(phase * 2.7 - x * 0.08));
          audioHistory[y * 64 + x] = 255 * Math.pow(wave * 0.45 + pulse * 0.35, 2);
        }
      }
      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, audioTexture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, 64, 128, 0, gl.RED, gl.UNSIGNED_BYTE, audioHistory);
      gl.clearColor(0.05, 0.01, 0.08, 1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

      gl.disable(gl.DEPTH_TEST);
      gl.useProgram(skyProgram);
      gl.uniform2f(skyResolution, canvas.width, canvas.height);
      gl.uniform1f(skyTime, seconds);
      gl.bindVertexArray(skyVao);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      gl.enable(gl.DEPTH_TEST);
      gl.useProgram(program);
      gl.uniformMatrix4fv(projectionLocation, false, perspective(Math.PI / 3, canvas.width / canvas.height, 0.1, 200));
      gl.uniform1f(timeLocation, seconds);
      gl.uniform1f(shockwavePhase, (seconds % 4) / 4);
      gl.bindVertexArray(vao);
      gl.drawArrays(gl.TRIANGLES, 0, vertices.length / 6);
      requestAnimationFrame(render);
    };
    render(performance.now());
  };

  if (document.body.dataset.shader === "synthwave") startSynthwave();
  else startCosmic();
})();
