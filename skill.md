---
name: ghostty-retro-stars
description: 一键部署 Ghostty 复古星空终端环境，包含 CRT 着色器、光标尾迹、星空背景及 Zellij/Helix 透明化配置。
---

当用户调用此 skill 时，请作为执行者，严格按照以下 4 个阶段的先后顺序，在本地文件系统中进行目录创建、文件写入和配置修改。不要省略任何一个步骤。所有文件内容请直接写入，不依赖外部网络拉取。

## 阶段一：环境基建与目录初始化

请检查并创建以下目录（如果已存在则跳过）：
1. `mkdir -p ~/.config/ghostty/custom_shader`
2. `mkdir -p ~/.config/zellij`
3. `mkdir -p ~/.config/helix/themes`

## 阶段二：Shader（着色器）部署与深度定制

**1. 部署 cursor_blaze.glsl (光标尾迹)**
在 `~/.config/ghostty/custom_shader/` 下创建 `cursor_blaze.glsl`，写入以下内容：

```glsl
// Based on https://gist.github.com/chardskarth/95874c54e29da6b5a36ab7b50ae2d088
float ease(float x) {
    return pow(1.0 - x, 10.0);
}

float sdBox(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
// Based on Inigo Quilez's 2D distance functions article: https://iquilezles.org/articles/distfunctions2d/
// Potencially optimized by eliminating conditionals and loops to enhance performance and reduce branching
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float blend(float t)
{
    float sqr = t * t;
    return sqr / (2.0 * (sqr - t) + 1.0);
}

float antialising(float distance) {
    return 1. - smoothstep(0., normalize(vec2(2., 2.), 0.).x, distance);
}

float determineStartVertexFactor(vec2 a, vec2 b) {
    // Conditions using step
    float condition1 = step(b.x, a.x) * step(a.y, b.y); // a.x < b.x && a.y > b.y
    float condition2 = step(a.x, b.x) * step(b.y, a.y); // a.x > b.x && a.y < b.y

    // If neither condition is met, return 1 (else case)
    return 1.0 - max(condition1, condition2);
}
vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.), rectangle.y - (rectangle.w / 2.));
}

const vec4 TRAIL_COLOR = vec4(1.0, 0.725, 0.161, 1.0); // yellow
const vec4 CURRENT_CURSOR_COLOR = TRAIL_COLOR;
const vec4 PREVIOUS_CURSOR_COLOR = TRAIL_COLOR;
const vec4 TRAIL_COLOR_ACCENT = vec4(1.0, 0., 0., 1.0); // red-orange
const float DURATION = .5;
const float OPACITY = .2;
// Don't draw trail within that distance * cursor size.
// This prevents trails from appearing when typing.
const float DRAW_THRESHOLD = 1.5;
// Don't draw trails within the same line: same line jumps are usually where
// people expect them.
const bool HIDE_TRAILS_ON_THE_SAME_LINE = false;

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif
    //Normalization for fragCoord to a space of -1 to 1;
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    //Normalization for cursor position and size;
    //cursor xy has the postion in a space of -1 to 1;
    //zw has the width and height
    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    //When drawing a parellelogram between cursors for the trail i need to determine where to start at the top-left or top-right vertex of the cursor
    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    //Set every vertex of my parellogram
    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    vec2 v2 = vec2(previousCursor.x + currentCursor.z * invertedVertexFactor, previousCursor.y);
    vec2 v3 = vec2(previousCursor.x + currentCursor.z * vertexFactor, previousCursor.y - previousCursor.w);

    vec4 newColor = vec4(fragColor);

    float progress = blend(clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1));
    float easedProgress = ease(progress);

    //Distance between cursors determine the total length of the parallelogram;
    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);
    float cursorSize = max(currentCursor.z, currentCursor.w);
    float trailThreshold = DRAW_THRESHOLD * cursorSize;
    float lineLength = distance(centerCC, centerCP);
    //
    bool isFarEnough = lineLength > trailThreshold;
    bool isOnSeparateLine = HIDE_TRAILS_ON_THE_SAME_LINE ? currentCursor.y != previousCursor.y : true;
    if (isFarEnough && isOnSeparateLine) {
        float distanceToEnd = distance(vu.xy, centerCC);
        float alphaModifier = distanceToEnd / (lineLength * (easedProgress));

        if (alphaModifier > 1.0) { // this change fixed it for me.
            alphaModifier = 1.0;
        }

        float sdfCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
        float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

        newColor = mix(newColor, TRAIL_COLOR_ACCENT, 1.0 - smoothstep(sdfTrail, -0.01, 0.001));
        newColor = mix(newColor, TRAIL_COLOR, antialising(sdfTrail));
        newColor = mix(fragColor, newColor, 1.0 - alphaModifier);
        fragColor = mix(newColor, fragColor, step(sdfCursor, 0));
    }
}
```

**2. 部署 bettercrt.glsl (CRT 质感)**
在同目录下创建 `bettercrt.glsl`，写入以下内容（参数已强制替换为增强数值）：

```glsl
// Enhanced CRT Shader for Ghostty
// Modified for stronger cathode-ray tube texture and retro authenticity

float warp = 0.22; // 屏幕弯曲程度
float scan = 0.35; // 扫描线对比度
float aberration_strength = 0.0015; // RGB 色差分离强度
float noise_intensity = 0.04; // 动态雪花噪点强度
float feather_edge = 0.03; // 屏幕边缘的柔和度

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // 归一化坐标
    vec2 uv = fragCoord / iResolution.xy;
    vec2 orig_uv = uv;
    vec2 dc = abs(0.5 - uv);
    dc *= dc;
    
    // 弯曲坐标 (桶形畸变)
    uv.x -= 0.5; uv.x *= 1.0 + (dc.y * (0.3 * warp)); uv.x += 0.5;
    uv.y -= 0.5; uv.y *= 1.0 + (dc.x * (0.4 * warp)); uv.y += 0.5;

    // 屏幕边界检测
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // 色差特效 - 分离采样 RGB 通道
    vec3 color;
    color.r = texture(iChannel0, uv + vec2(aberration_strength, 0.0)).r;
    color.g = texture(iChannel0, uv).g;
    color.b = texture(iChannel0, uv - vec2(aberration_strength, 0.0)).b;

    // 扫描线特效 - 频率根据屏幕高度自适应
    float scanlines_freq = iResolution.y * 0.6; 
    float scanline_effect = 0.5 + 0.5 * sin(orig_uv.y * scanlines_freq);
    scanline_effect = smoothstep(0.3, 0.7, scanline_effect); 
    color *= mix(vec3(1.0), vec3(0.65), scanline_effect * scan);

    // 动态噪点 (模拟电子管底噪)
    float noise_time = iTime * 100.0;
    float x = (orig_uv.x - mod(orig_uv.x, 0.003)) * (orig_uv.y - mod(orig_uv.y, 0.002)) * noise_time;
    x = mod(x, 13.0) * mod(x, 123.0);
    float noise = mod(x, 0.2) / 0.2;
    color = mix(color, vec3(noise), noise_intensity);

    // 边缘羽化
    vec2 edge_dist = abs(uv * 2.0 - 1.0);
    float edge_mask = (1.0 - smoothstep(1.0 - feather_edge, 1.0, edge_dist.x)) *
                      (1.0 - smoothstep(1.0 - feather_edge, 1.0, edge_dist.y));

    // 暗角特效 (Vignette) - 四周变暗
    float vignette = 1.0 - (dc.x * dc.y * 12.0);
    color *= clamp(vignette, 0.6, 1.0);

    // 亮度/对比度微调
    color = (color - 0.5) * 1.08 + 0.58; 

    fragColor = vec4(color * edge_mask, 1.0);
}
```

**3. 部署 starfield.glsl (星空背景)**
在同目录下创建 `starfield.glsl`，写入以下内容（已包含 `fragColor.a = 0.85` 的强制修改）：

```glsl
const bool transparent = true;
const float threshold = 0.15;
const float repeats = 20.;
const float layers = 15.;
const vec3 white = vec3(0.5, 0.4, 0.5);

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float N21(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

vec2 N22(vec2 p) {
    float n = N21(p);
    return vec2(n, N21(p + n));
}

mat2 scale(vec2 _scale) {
    return mat2(_scale.x, 0.0, 0.0, _scale.y);
}

// 2D Noise based on Morgan McGuire
float noise(in vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);

    float a = N21(i);
    float b = N21(i + vec2(1.0, 0.0));
    float c = N21(i + vec2(0.0, 1.0));
    float d = N21(i + vec2(1.0, 1.0));

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
        (c - a) * u.y * (1.0 - u.x) +
        (d - b) * u.x * u.y;
}

float perlin2(vec2 uv, int octaves, float pscale) {
    float col = 1.;
    float initScale = 4.;
    for (int l; l < octaves; l++) {
        float val = noise(uv * initScale);
        if (col <= 0.01) {
            col = 0.;
            break;
        }
        val -= 0.01;
        val *= 0.5;
        col *= val;
        initScale *= pscale;
    }
    return col;
}

vec3 stars(vec2 uv, float offset) {
    float timeScale = -((0.3 * iTime) + offset) / layers;
    float trans = fract(timeScale);
    float newRnd = floor(timeScale);
    vec3 col = vec3(0.);

    uv -= vec2(0.5);
    uv = scale(vec2(trans)) * uv;
    uv += vec2(0.5);

    uv.x *= iResolution.x / iResolution.y;
    uv *= repeats;

    vec2 ipos = floor(uv);
    uv = fract(uv);

    vec2 rndXY = N22(newRnd + ipos * (offset + 1.)) * 0.9 + 0.05;
    float rndSize = N21(ipos) * 100. + 200.;

    vec2 j = (rndXY - uv) * rndSize;
    float sparkle = 1. / dot(j, j);

    col += white * sparkle;

    col *= smoothstep(1., 0.8, trans);
    return col;
}

float easeInOutCubic(float x) {
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 col = vec3(0.);

    float aspectRatio = iResolution.x / iResolution.y;
    float d =  max(iResolution.x, iResolution.y);

    vec2 pos = (fragCoord) / vec2(d, d / aspectRatio);

    for (float i = 0.; i < layers; i++) {
        col += stars(pos, i);
    }

    vec4 terminalColor = texture(iChannel0, uv);

    if (transparent) {
        col += terminalColor.rgb;
    }

    float mask = 1 - step(threshold, luminance(terminalColor.rgb));

    vec3 blendedColor = mix(terminalColor.rgb, col, mask);

    fragColor = vec4(blendedColor, terminalColor.a);
    fragColor = mix(terminalColor, fragColor, easeInOutCubic(max(0, min((fragCoord.y - 5) / 85, 1))));
    fragColor.a = 0.85;
}
```

## 阶段三：Ghostty 宿主唤醒与挂载

创建或覆盖 `~/.config/ghostty/config`，写入以下配置：

```ini
# 1. 基础UI与字体
font-family = "JetBrains Mono"
font-size = 12
font-thicken = true
cursor-style = block
window-theme = system
mouse-hide-while-typing = true
clipboard-trim-trailing-spaces = true

# 2. 强制黑底与毛玻璃
background = #000000
background-opacity = 0.9
background-blur-radius = 20

# 3. 链式挂载 Shaders (顺序不可变)
custom-shader = "~/.config/ghostty/custom_shader/cursor_blaze.glsl"
custom-shader = "~/.config/ghostty/custom_shader/bettercrt.glsl"
custom-shader = "~/.config/ghostty/custom_shader/starfield.glsl"
```

## 阶段四：CLI 内部环境透明化

**1. Zellij 紧凑布局**
- 读取 `~/.config/zellij/config.kdl`（如果存在）。
- 如果文件中不存在 `default_layout "compact"`，则在文件**顶部**插入一行：`default_layout "compact"`。
- 如果文件不存在，则创建它并写入：`default_layout "compact"`。

**2. Helix 编辑器背景抽空**
- 创建透明主题文件 `~/.config/helix/themes/mytrans.toml`，写入：
  ```toml
  inherits = "default"
  "ui.background" = {}
  ```
- 读取 `~/.config/helix/config.toml`（如果存在）。
- 如果文件中已存在 `theme = ...`，将其修改为 `theme = "mytrans"`。
- 如果不存在 `theme` 配置行，在文件末尾追加：`theme = "mytrans"`。
- 如果文件不存在，则创建它并写入：`theme = "mytrans"`。

---

执行完毕后，请提示用户**完全重启 Ghostty 终端**以使所有层级的配置生效。
