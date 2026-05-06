# ffmpeg-gl-transition: FFmpeg 8.x Support + Performance Design

**Date:** 2026-05-06

## Goals

1. Support FFmpeg 8.x (currently broken due to API changes since the filter was written)
2. Improve execution performance via YUV native input and async PBO readback

---

## Section 1: FFmpeg 8.x via Fork

### Approach

Fork FFmpeg at the `n8.0` release tag into a GitHub repo (e.g., `your-org/ffmpeg`). Commit the filter and its registration changes directly into the fork — no patch file.

### Changes in the fork

- `libavfilter/vf_gltransition.c` — copied from this repo
- `libavfilter/Makefile` — add `OBJS-$(CONFIG_GLTRANSITION_FILTER) += vf_gltransition.o`
- `libavfilter/allfilters.c` — add `extern const AVFilter ff_vf_gltransition;`

### FFmpeg 8.x API fixes in `vf_gltransition.c`

**1. Remove `{NULL}` sentinel from `AVFilterPad` arrays** (dropped in FFmpeg 5.x):
```c
static const AVFilterPad gltransition_inputs[] = {
  { .name = "from", .type = AVMEDIA_TYPE_VIDEO, .config_props = setup_gl },
  { .name = "to",   .type = AVMEDIA_TYPE_VIDEO },
};
static const AVFilterPad gltransition_outputs[] = {
  { .name = "default", .type = AVMEDIA_TYPE_VIDEO, .config_props = config_output },
};
// AVFilter struct uses .nb_inputs = 2, .nb_outputs = 1
```

**2. Replace `query_formats` + `ff_set_common_formats`** (removed in FFmpeg 7.x):
```c
static const enum AVPixelFormat pix_fmts[] = { AV_PIX_FMT_YUV420P, AV_PIX_FMT_NONE };
// declared via ff_set_common_formats_from_list in config_output, or via AVFilterFormatsConfig
```
Remove the `query_formats` function and its reference in the `AVFilter` struct.

**3. Update `ffmpeg.diff`** — deleted from this repo entirely. Changes live in the fork.

### Repo changes

| File | Action |
|------|--------|
| `vf_gltransition.c` | Updated with 8.x API fixes + perf changes (source of truth) |
| `Dockerfile` | Clone from fork; remove `git apply` and EGL-stripping `grep` |
| `README.md` | Update build instructions to reference fork |
| `ffmpeg.diff` | Deleted |

### Workflow for future updates

1. Edit `vf_gltransition.c` in this repo
2. Copy to fork at `libavfilter/vf_gltransition.c`, commit and push
3. Dockerfile pins fork at a specific commit SHA for reproducible builds

---

## Section 2: YUV Native Upload + PBO Async Readback

### 2a. YUV420P Native Input

**Problem:** Current filter declares `AV_PIX_FMT_RGB24`, forcing FFmpeg to convert every frame YUV→RGB before the filter and RGB→YUV after. Two full-frame color conversions per frame.

**Fix:** Declare `AV_PIX_FMT_YUV420P`. FFmpeg stops converting.

Each YUV420P frame has 3 planes:
- Y: full resolution (`w × h`)
- U, V: half resolution (`w/2 × h/2`)

**GL texture setup (6 textures total, pre-allocated once):**

| Texture | Format | Size | Bound to uniform |
|---------|--------|------|-----------------|
| `from_y` | `GL_RED` | `w × h` | `from_y_tex` |
| `from_u` | `GL_RED` | `w/2 × h/2` | `from_u_tex` |
| `from_v` | `GL_RED` | `w/2 × h/2` | `from_v_tex` |
| `to_y` | `GL_RED` | `w × h` | `to_y_tex` |
| `to_u` | `GL_RED` | `w/2 × h/2` | `to_u_tex` |
| `to_v` | `GL_RED` | `w/2 × h/2` | `to_v_tex` |

Textures are allocated once in `setup_tex` with `glTexImage2D(..., NULL)`. Per-frame updates use `glTexSubImage2D` — no GPU memory reallocation.

`GL_UNPACK_ROW_LENGTH` is set per-plane to handle FFmpeg's `linesize` padding.

**GLSL preamble (injected before user transition source):**

```glsl
uniform sampler2D from_y_tex, from_u_tex, from_v_tex;
uniform sampler2D to_y_tex,   to_u_tex,   to_v_tex;

vec4 yuv2rgb(float y, float u, float v) {
  // BT.601 full range
  return vec4(
    y + 1.402   * (v - 0.5),
    y - 0.344   * (u - 0.5) - 0.714 * (v - 0.5),
    y + 1.772   * (u - 0.5),
    1.0
  );
}

vec4 getFromColor(vec2 uv) {
  vec2 uv_flip = vec2(uv.x, 1.0 - uv.y);
  float y = texture2D(from_y_tex, uv_flip).r;
  float u = texture2D(from_u_tex, uv_flip).r;
  float v = texture2D(from_v_tex, uv_flip).r;
  return yuv2rgb(y, u, v);
}

vec4 getToColor(vec2 uv) {
  vec2 uv_flip = vec2(uv.x, 1.0 - uv.y);
  float y = texture2D(to_y_tex, uv_flip).r;
  float u = texture2D(to_u_tex, uv_flip).r;
  float v = texture2D(to_v_tex, uv_flip).r;
  return yuv2rgb(y, u, v);
}
```

All existing `.glsl` transition files call `getFromColor` / `getToColor` and are unaffected.

### 2b. PBO Double-Buffered Readback

**Problem:** `glReadPixels` into a plain CPU pointer stalls the CPU until the GPU finishes rendering the current frame.

**Fix:** Use two Pixel Buffer Objects (PBOs) in a double-buffer pattern:

```
Frame N render  → glReadPixels into PBO[N%2]   (async, returns immediately)
Frame N CPU copy ← glMapBuffer(PBO[(N+1)%2])   (previous frame, already done)
```

**State added to `GLTransitionContext`:**
```c
GLuint pbo[2];       // two readback PBOs
int    pbo_index;    // current write PBO (0 or 1)
int    pbo_ready;    // becomes 1 after first frame so we don't read uninitialised PBO
```

**Init (`setup_gl`):**
```c
glGenBuffers(2, c->pbo);
size_t pbo_size = outLink->w * outLink->h * 3; // RGB24 output
for (int i = 0; i < 2; i++) {
  glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[i]);
  glBufferData(GL_PIXEL_PACK_BUFFER, pbo_size, NULL, GL_STREAM_READ);
}
glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
```

**Per-frame (`apply_transition`):**
```c
// 1. Kick off async readback into current PBO
glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[c->pbo_index]);
glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, 0); // offset=0, async

// 2. Map previous PBO to copy last frame's result to outFrame
int prev = 1 - c->pbo_index;
if (c->pbo_ready) {
  glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[prev]);
  GLubyte *ptr = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY);
  memcpy(outFrame->data[0], ptr, pbo_size);
  glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
}

glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
c->pbo_index = prev;
c->pbo_ready = 1;
```

**One-frame latency:** The double-buffer introduces a 1-frame output delay. This is acceptable for video transitions and is standard practice for GL readback pipelines. On the first frame `pbo_ready=0`, so `outFrame` must be explicitly zero-filled before returning to avoid uninitialized pixel data.

**Output pixel format:** Readback stays `RGB24`; FFmpeg does one RGB→YUV conversion on output. This is cheaper than the GPU stall we eliminate.

**Cleanup (`uninit`):**
```c
glDeleteBuffers(2, c->pbo);
```

### 2c. `linesize` Handling

YUV planes each need `GL_UNPACK_ROW_LENGTH` set to `frame->linesize[plane]` before upload (Y: `linesize[0]`, U: `linesize[1]`, V: `linesize[2]`). Reset to 0 after each upload.

---

## Section 3: Build & Repo Structure

### This repo (`ffmpeg-gl-transition`)

```
vf_gltransition.c       ← source of truth, all changes here
Dockerfile              ← updated (clone fork, no git apply, no grep)
README.md               ← updated build instructions
ffmpeg.diff             ← DELETED
```

### Fork repo (`your-org/ffmpeg`, based on tag `n8.0`)

```
libavfilter/vf_gltransition.c   ← copied from this repo
libavfilter/Makefile            ← +1 line (GLTRANSITION_FILTER obj)
libavfilter/allfilters.c        ← +1 line (extern AVFilter declaration)
```

### Dockerfile (updated)

```dockerfile
RUN git clone --branch n8.0 https://github.com/your-org/ffmpeg.git ffmpeg
# No git apply needed — changes are already in the fork
RUN (cd ffmpeg; ./configure --enable-libx264 --enable-gpl --enable-opengl \
    --enable-filter=gltransition --extra-libs='-lGLEW -lEGL -ldl')
RUN (cd ffmpeg; make -j$(nproc))
RUN (cd ffmpeg; make install)
```

---

## Performance Summary

| Change | Gain |
|--------|------|
| YUV420P input (no FFmpeg YUV↔RGB) | ~20–30% fewer CPU cycles per frame |
| `glTexSubImage2D` (no GPU realloc) | Reduced per-frame GL overhead |
| PBO async readback | Eliminates `glReadPixels` CPU stall; GPU and CPU pipeline in parallel |
| **Combined** | ~2–4× faster on HD/4K video |

---

## Out of Scope

- Rendering output as YUV (would require second render pass — not worth complexity)
- Supporting FFmpeg versions other than 8.x
- Changing the GLSL transition interface
