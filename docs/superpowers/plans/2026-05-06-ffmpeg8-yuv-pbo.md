# FFmpeg 8.x + YUV/PBO Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update ffmpeg-gl-transition to compile on FFmpeg 8.x and improve per-frame throughput by accepting YUV420P natively and using PBO double-buffered async readback.

**Architecture:** Fork FFmpeg at `n8.0` tag and commit filter changes directly (no patch file). Update `vf_gltransition.c` in three layers: API compat (remove obsolete FFmpeg 5.x+ breaking changes), YUV420P texture upload via 6 GL textures + GLSL YUV→RGB preamble, and PBO double-buffer to overlap GPU render with CPU readback.

**Tech Stack:** C, OpenGL (EGL on Linux), GLSL, FFmpeg 8.x internal filter API, git

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `vf_gltransition.c` | Modify | All filter logic — source of truth |
| `Dockerfile` | Modify | Point to fork; remove patch step |
| `README.md` | Modify | Updated build instructions |
| `ffmpeg.diff` | Delete | Replaced by direct fork commits |
| `your-org/ffmpeg:libavfilter/vf_gltransition.c` | Create (fork) | Copy of above |
| `your-org/ffmpeg:libavfilter/Makefile` | Modify (fork) | +1 line: register filter obj |
| `your-org/ffmpeg:libavfilter/allfilters.c` | Modify (fork) | +1 line: extern declaration |

---

## Task 1: Create FFmpeg 8.x fork

**Files:**
- Fork repo at `https://github.com/your-org/ffmpeg` (new GitHub repo, branched from tag `n8.0`)

- [ ] **Step 1: Fork FFmpeg at n8.0 on GitHub**

  Go to `https://github.com/FFmpeg/FFmpeg`, click Fork. Name it `ffmpeg` under your org.

  Then locally:
  ```bash
  git clone https://github.com/your-org/ffmpeg.git ffmpeg-fork
  cd ffmpeg-fork
  git fetch origin
  git checkout n8.0
  git checkout -b gltransition
  ```

- [ ] **Step 2: Add filter registration to Makefile**

  In `libavfilter/Makefile`, find the `ZSCALE` line and add the gltransition line immediately after:
  ```
  OBJS-$(CONFIG_ZSCALE_FILTER)                 += vf_zscale.o
  OBJS-$(CONFIG_GLTRANSITION_FILTER)           += vf_gltransition.o
  ```

- [ ] **Step 3: Add extern declaration to allfilters.c**

  In `libavfilter/allfilters.c`, find `ff_vf_zscale` and add immediately after:
  ```c
  extern const AVFilter ff_vf_zscale;
  extern const AVFilter ff_vf_gltransition;
  ```

- [ ] **Step 4: Copy current vf_gltransition.c into fork (placeholder — will be replaced)**

  ```bash
  cp /path/to/ffmpeg-gl-transition/vf_gltransition.c libavfilter/vf_gltransition.c
  ```

- [ ] **Step 5: Commit to fork**

  ```bash
  git add libavfilter/vf_gltransition.c libavfilter/Makefile libavfilter/allfilters.c
  git commit -m "feat: add gltransition filter"
  git push origin gltransition
  ```

---

## Task 2: FFmpeg 8.x API compatibility in vf_gltransition.c

**Files:**
- Modify: `vf_gltransition.c`

FFmpeg 5.x removed `{NULL}` sentinels from `AVFilterPad` arrays. FFmpeg 7.x removed `query_formats` from `AVFilter`. This task fixes both.

- [ ] **Step 1: Replace AVFilterPad arrays (remove NULL sentinels, use FILTER_ macros)**

  Replace the current pad arrays and `AVFilter` struct at the bottom of `vf_gltransition.c`.

  Old pad arrays (lines 544–578):
  ```c
  static const AVFilterPad gltransition_inputs[] = {
    {
      .name = "from",
      .type = AVMEDIA_TYPE_VIDEO,
      .config_props = setup_gl,
    },
    {
      .name = "to",
      .type = AVMEDIA_TYPE_VIDEO,
    },
    {NULL}
  };

  static const AVFilterPad gltransition_outputs[] = {
    {
      .name = "default",
      .type = AVMEDIA_TYPE_VIDEO,
      .config_props = config_output,
    },
    {NULL}
  };

  AVFilter ff_vf_gltransition = {
    .name          = "gltransition",
    .description   = NULL_IF_CONFIG_SMALL("OpenGL blend transitions"),
    .priv_size     = sizeof(GLTransitionContext),
    .preinit       = gltransition_framesync_preinit,
    .init          = init,
    .uninit        = uninit,
    .query_formats = query_formats,
    .activate      = activate,
    .inputs        = gltransition_inputs,
    .outputs       = gltransition_outputs,
    .priv_class    = &gltransition_class,
    .flags         = AVFILTER_FLAG_SUPPORT_TIMELINE_GENERIC
  };
  ```

  New pad arrays and AVFilter struct:
  ```c
  static const AVFilterPad gltransition_inputs[] = {
    {
      .name         = "from",
      .type         = AVMEDIA_TYPE_VIDEO,
      .config_props = setup_gl,
    },
    {
      .name         = "to",
      .type         = AVMEDIA_TYPE_VIDEO,
    },
  };

  static const AVFilterPad gltransition_outputs[] = {
    {
      .name         = "default",
      .type         = AVMEDIA_TYPE_VIDEO,
      .config_props = config_output,
    },
  };

  const AVFilter ff_vf_gltransition = {
    .name          = "gltransition",
    .description   = NULL_IF_CONFIG_SMALL("OpenGL blend transitions"),
    .priv_size     = sizeof(GLTransitionContext),
    .preinit       = gltransition_framesync_preinit,
    .init          = init,
    .uninit        = uninit,
    .activate      = activate,
    .priv_class    = &gltransition_class,
    .flags         = AVFILTER_FLAG_SUPPORT_TIMELINE_GENERIC,
    FILTER_INPUTS(gltransition_inputs),
    FILTER_OUTPUTS(gltransition_outputs),
    FILTER_PIXFMTS(AV_PIX_FMT_YUV420P),
  };
  ```

  Note: `FILTER_INPUTS`, `FILTER_OUTPUTS`, and `FILTER_PIXFMTS` are macros defined in `libavfilter/internal.h` since FFmpeg 5.x. They replace `.inputs`/`.outputs`/`.query_formats`.

- [ ] **Step 2: Remove the query_formats function**

  Delete the entire `query_formats` function (currently lines 494–502):
  ```c
  static int query_formats(AVFilterContext *ctx)
  {
    static const enum AVPixelFormat formats[] = {
      AV_PIX_FMT_RGB24,
      AV_PIX_FMT_NONE
    };

    return ff_set_common_formats(ctx, ff_make_format_list(formats));
  }
  ```

- [ ] **Step 3: Copy updated file to fork and attempt build**

  ```bash
  cp vf_gltransition.c /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork
  ./configure --enable-gpl --enable-opengl --enable-filter=gltransition \
    --extra-libs='-lGLEW -lEGL -ldl'
  make -j$(nproc) 2>&1 | head -50
  ```

  Expected: no errors related to `query_formats`, pad arrays, or `AVFilter` struct fields. Fix any compile errors before continuing. Common issue: if `FILTER_PIXFMTS` is not found, check that `libavfilter/internal.h` in the fork defines it — it should since `n8.0`.

- [ ] **Step 4: Verify filter is registered**

  ```bash
  ./ffmpeg -v 0 -filters | grep gltransition
  ```
  Expected: `... gltransition    VV->V  OpenGL blend transitions`

- [ ] **Step 5: Commit**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  git add vf_gltransition.c
  git commit -m "fix: FFmpeg 8.x API compat — remove NULL sentinels, replace query_formats with FILTER_PIXFMTS"
  ```

---

## Task 3: Add YUV texture fields to GLTransitionContext

**Files:**
- Modify: `vf_gltransition.c`

Replace the two `GLuint from/to` texture fields with six YUV plane textures.

- [ ] **Step 1: Update GLTransitionContext struct**

  Old (lines 107–108):
  ```c
  GLuint        from;
  GLuint        to;
  ```

  New:
  ```c
  GLuint        from_y, from_u, from_v;
  GLuint        to_y,   to_u,   to_v;
  ```

- [ ] **Step 2: Update uninit to delete new textures**

  Old `uninit` texture deletion (two blocks, one for EGL one for GLFW):
  ```c
  glDeleteTextures(1, &c->from);
  glDeleteTextures(1, &c->to);
  ```

  New (same change in both `#ifdef GL_TRANSITION_USING_EGL` and `#else` blocks):
  ```c
  glDeleteTextures(1, &c->from_y);
  glDeleteTextures(1, &c->from_u);
  glDeleteTextures(1, &c->from_v);
  glDeleteTextures(1, &c->to_y);
  glDeleteTextures(1, &c->to_u);
  glDeleteTextures(1, &c->to_v);
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add vf_gltransition.c
  git commit -m "refactor: replace from/to RGB textures with 6 YUV plane textures"
  ```

---

## Task 4: Update setup_tex for YUV420P

**Files:**
- Modify: `vf_gltransition.c`

Pre-allocate 6 textures (Y full-res, U/V half-res for each input). Use `GL_RED` format. Upload NULL data — actual frame data comes later via `glTexSubImage2D`.

- [ ] **Step 1: Replace setup_tex entirely**

  Remove the current `setup_tex` function (lines 230–264) and replace with:

  ```c
  static void setup_tex(AVFilterLink *fromLink)
  {
    AVFilterContext     *ctx = fromLink->dst;
    GLTransitionContext *c   = ctx->priv;
    const int w  = fromLink->w, h  = fromLink->h;
    const int hw = w / 2,       hh = h / 2;

    auto_alloc_tex(c, &c->from_y, GL_TEXTURE0,     w,  h,  "from_y", 0);
    auto_alloc_tex(c, &c->from_u, GL_TEXTURE0 + 1, hw, hh, "from_u", 1);
    auto_alloc_tex(c, &c->from_v, GL_TEXTURE0 + 2, hw, hh, "from_v", 2);
    auto_alloc_tex(c, &c->to_y,   GL_TEXTURE0 + 3, w,  h,  "to_y",   3);
    auto_alloc_tex(c, &c->to_u,   GL_TEXTURE0 + 4, hw, hh, "to_u",   4);
    auto_alloc_tex(c, &c->to_v,   GL_TEXTURE0 + 5, hw, hh, "to_v",   5);
  }
  ```

  And add the helper `auto_alloc_tex` just before `setup_tex`:

  ```c
  static void auto_alloc_tex(GLTransitionContext *c, GLuint *tex,
                              GLenum unit, int w, int h,
                              const char *uniform_name, int unit_idx)
  {
    glGenTextures(1, tex);
    glActiveTexture(unit);
    glBindTexture(GL_TEXTURE_2D, *tex);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, w, h, 0, GL_RED, GL_UNSIGNED_BYTE, NULL);
    glUniform1i(glGetUniformLocation(c->program, uniform_name), unit_idx);
  }
  ```

- [ ] **Step 2: Verify it compiles**

  ```bash
  cp vf_gltransition.c /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork && make -j$(nproc) 2>&1 | grep -E "error:|warning:" | head -20
  ```
  Expected: no errors in vf_gltransition.c.

- [ ] **Step 3: Commit**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  git add vf_gltransition.c
  git commit -m "feat: pre-allocate 6 YUV GL textures in setup_tex"
  ```

---

## Task 5: Add GLSL YUV preamble and update shader template

**Files:**
- Modify: `vf_gltransition.c`

Replace the RGB `getFromColor`/`getToColor` in `f_shader_template` with YUV sampler uniforms + BT.601 conversion preamble. Existing `.glsl` transition files are unaffected since they call `getFromColor`/`getToColor` which we redefine.

- [ ] **Step 1: Replace f_shader_template and add yuv_preamble constant**

  Remove the old `f_shader_template` (lines 62–82) and replace with:

  ```c
  static const GLchar *f_shader_template =
    "varying vec2 _uv;\n"
    "uniform float progress;\n"
    "uniform float ratio;\n"
    "uniform float _fromR;\n"
    "uniform float _toR;\n"
    "\n%s\n"   /* YUV preamble */
    "\n%s\n"   /* user transition source */
    "void main() {\n"
    "  gl_FragColor = transition(_uv);\n"
    "}\n";
  ```

  And add this constant just after `f_shader_template`:

  ```c
  static const GLchar *f_yuv_preamble =
    "uniform sampler2D from_y, from_u, from_v;\n"
    "uniform sampler2D to_y,   to_u,   to_v;\n"
    "\n"
    "vec4 yuv2rgb(float y, float u, float v) {\n"
    "  return vec4(\n"
    "    y + 1.402   * (v - 0.5),\n"
    "    y - 0.344   * (u - 0.5) - 0.714 * (v - 0.5),\n"
    "    y + 1.772   * (u - 0.5),\n"
    "    1.0\n"
    "  );\n"
    "}\n"
    "\n"
    "vec4 getFromColor(vec2 uv) {\n"
    "  vec2 f = vec2(uv.x, 1.0 - uv.y);\n"
    "  return yuv2rgb(\n"
    "    texture2D(from_y, f).r,\n"
    "    texture2D(from_u, f).r,\n"
    "    texture2D(from_v, f).r\n"
    "  );\n"
    "}\n"
    "\n"
    "vec4 getToColor(vec2 uv) {\n"
    "  vec2 f = vec2(uv.x, 1.0 - uv.y);\n"
    "  return yuv2rgb(\n"
    "    texture2D(to_y, f).r,\n"
    "    texture2D(to_u, f).r,\n"
    "    texture2D(to_v, f).r\n"
    "  );\n"
    "}\n";
  ```

- [ ] **Step 2: Update build_program to use two-format snprintf**

  Find this block in `build_program` (around line 190):
  ```c
  int len = strlen(f_shader_template) + strlen(transition_source);
  c->f_shader_source = av_calloc(len, sizeof(*c->f_shader_source));
  if (!c->f_shader_source) {
    return AVERROR(ENOMEM);
  }
  snprintf(c->f_shader_source, len * sizeof(*c->f_shader_source), f_shader_template, transition_source);
  ```

  Replace with:
  ```c
  int len = strlen(f_shader_template) + strlen(f_yuv_preamble) + strlen(transition_source);
  c->f_shader_source = av_calloc(len, sizeof(*c->f_shader_source));
  if (!c->f_shader_source) {
    return AVERROR(ENOMEM);
  }
  snprintf(c->f_shader_source, len * sizeof(*c->f_shader_source),
           f_shader_template, f_yuv_preamble, transition_source);
  ```

- [ ] **Step 3: Verify it compiles**

  ```bash
  cp vf_gltransition.c /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork && make -j$(nproc) 2>&1 | grep -E "error:" | head -20
  ```

- [ ] **Step 4: Commit**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  git add vf_gltransition.c
  git commit -m "feat: inject YUV->RGB GLSL preamble, update shader template for YUV420P"
  ```

---

## Task 6: Update apply_transition for YUV per-plane upload

**Files:**
- Modify: `vf_gltransition.c`

Replace the single-texture `glTexImage2D` upload per input with per-plane `glTexSubImage2D` uploads for both `from` and `to` frames.

- [ ] **Step 1: Replace frame upload block in apply_transition**

  Find this block in `apply_transition` (around lines 396–414):
  ```c
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, c->from);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, fromFrame->linesize[0] / 3);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, fromLink->w, fromLink->h, 0, PIXEL_FORMAT, GL_UNSIGNED_BYTE, fromFrame->data[0]);

  glActiveTexture(GL_TEXTURE0 + 1);
  glBindTexture(GL_TEXTURE_2D, c->to);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, toFrame->linesize[0] / 3);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, toLink->w, toLink->h, 0, PIXEL_FORMAT, GL_UNSIGNED_BYTE, toFrame->data[0]);

  glDrawArrays(GL_TRIANGLES, 0, 6);
  glPixelStorei(GL_PACK_ROW_LENGTH, outFrame->linesize[0] / 3);
  glReadPixels(0, 0, outLink->w, outLink->h, PIXEL_FORMAT, GL_UNSIGNED_BYTE, (GLvoid *)outFrame->data[0]);

  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  ```

  Replace with:
  ```c
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  /* upload from frame — Y plane */
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, c->from_y);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, fromFrame->linesize[0]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, fromLink->w, fromLink->h, GL_RED, GL_UNSIGNED_BYTE, fromFrame->data[0]);

  /* upload from frame — U plane */
  glActiveTexture(GL_TEXTURE0 + 1);
  glBindTexture(GL_TEXTURE_2D, c->from_u);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, fromFrame->linesize[1]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, fromLink->w/2, fromLink->h/2, GL_RED, GL_UNSIGNED_BYTE, fromFrame->data[1]);

  /* upload from frame — V plane */
  glActiveTexture(GL_TEXTURE0 + 2);
  glBindTexture(GL_TEXTURE_2D, c->from_v);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, fromFrame->linesize[2]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, fromLink->w/2, fromLink->h/2, GL_RED, GL_UNSIGNED_BYTE, fromFrame->data[2]);

  /* upload to frame — Y plane */
  glActiveTexture(GL_TEXTURE0 + 3);
  glBindTexture(GL_TEXTURE_2D, c->to_y);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, toFrame->linesize[0]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, toLink->w, toLink->h, GL_RED, GL_UNSIGNED_BYTE, toFrame->data[0]);

  /* upload to frame — U plane */
  glActiveTexture(GL_TEXTURE0 + 4);
  glBindTexture(GL_TEXTURE_2D, c->to_u);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, toFrame->linesize[1]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, toLink->w/2, toLink->h/2, GL_RED, GL_UNSIGNED_BYTE, toFrame->data[1]);

  /* upload to frame — V plane */
  glActiveTexture(GL_TEXTURE0 + 5);
  glBindTexture(GL_TEXTURE_2D, c->to_v);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, toFrame->linesize[2]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, toLink->w/2, toLink->h/2, GL_RED, GL_UNSIGNED_BYTE, toFrame->data[2]);

  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);

  glDrawArrays(GL_TRIANGLES, 0, 6);
  glPixelStorei(GL_PACK_ROW_LENGTH, outFrame->linesize[0] / 3);
  glReadPixels(0, 0, outLink->w, outLink->h, GL_RGB, GL_UNSIGNED_BYTE, (GLvoid *)outFrame->data[0]);

  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  ```

  Also remove the `#define PIXEL_FORMAT (GL_RGB)` line near the top of the file — it's no longer used.

- [ ] **Step 2: Verify compile + basic smoke test**

  ```bash
  cp vf_gltransition.c /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork && make -j$(nproc) 2>&1 | grep "error:"
  ```

  If build passes, run a quick smoke test:
  ```bash
  cd /path/to/ffmpeg-gl-transition
  ./ffmpeg -i media/0.mp4 -i media/1.mp4 -filter_complex gltransition -y /tmp/out_yuv.mp4 2>&1 | tail -5
  ffprobe /tmp/out_yuv.mp4 2>&1 | grep "Video:"
  ```
  Expected: no error, output contains a video stream.

- [ ] **Step 3: Commit**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  git add vf_gltransition.c
  git commit -m "feat: upload YUV420P planes via glTexSubImage2D, eliminate RGB conversion"
  ```

---

## Task 7: Add PBO double-buffered async readback

**Files:**
- Modify: `vf_gltransition.c`

Add two PBOs to overlap GPU→CPU pixel readback with rendering. Introduces 1-frame latency (acceptable for transitions). First frame output is zero-filled (black frame for 1/fps seconds, visually negligible).

- [ ] **Step 1: Add PBO fields to GLTransitionContext**

  In the `GLTransitionContext` struct, after `GLuint program;`, add:
  ```c
  GLuint        pbo[2];
  int           pbo_index;
  int           pbo_ready;
  ```

- [ ] **Step 2: Init PBOs in setup_gl**

  In `setup_gl`, after `setup_tex(inLink);`, add:
  ```c
  const size_t pbo_size = (size_t)inLink->w * inLink->h * 3;
  glGenBuffers(2, c->pbo);
  for (int i = 0; i < 2; i++) {
    glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[i]);
    glBufferData(GL_PIXEL_PACK_BUFFER, pbo_size, NULL, GL_STREAM_READ);
  }
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  c->pbo_index = 0;
  c->pbo_ready = 0;
  ```

- [ ] **Step 3: Replace glReadPixels with PBO double-buffer in apply_transition**

  Find the current readback block (just added in Task 6):
  ```c
  glDrawArrays(GL_TRIANGLES, 0, 6);
  glPixelStorei(GL_PACK_ROW_LENGTH, outFrame->linesize[0] / 3);
  glReadPixels(0, 0, outLink->w, outLink->h, GL_RGB, GL_UNSIGNED_BYTE, (GLvoid *)outFrame->data[0]);

  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  ```

  Replace with:
  ```c
  glDrawArrays(GL_TRIANGLES, 0, 6);

  /* async readback: kick off GPU→PBO DMA for current frame */
  glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[c->pbo_index]);
  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glReadPixels(0, 0, outLink->w, outLink->h, GL_RGB, GL_UNSIGNED_BYTE, 0);

  /* map previous PBO — contains the previous frame's rendered pixels */
  const int prev = 1 - c->pbo_index;
  if (c->pbo_ready) {
    glBindBuffer(GL_PIXEL_PACK_BUFFER, c->pbo[prev]);
    GLubyte *ptr = (GLubyte *)glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY);
    if (ptr) {
      memcpy(outFrame->data[0], ptr,
             (size_t)outLink->w * outLink->h * 3);
      glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
    }
  } else {
    memset(outFrame->data[0], 0, (size_t)outLink->w * outLink->h * 3);
  }

  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);

  c->pbo_index = prev;
  c->pbo_ready = 1;
  ```

- [ ] **Step 4: Delete PBOs in uninit**

  In `uninit`, in both the `#ifdef GL_TRANSITION_USING_EGL` and `#else` blocks, after the existing `glDeleteBuffers(1, &c->posBuf);` line, add:
  ```c
  glDeleteBuffers(2, c->pbo);
  ```

- [ ] **Step 5: Compile check**

  ```bash
  cp vf_gltransition.c /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork && make -j$(nproc) 2>&1 | grep "error:"
  ```
  Expected: no errors.

- [ ] **Step 6: Smoke test with crosswarp transition**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  ./ffmpeg -i media/0.mp4 -i media/1.mp4 \
    -filter_complex "gltransition=duration=1:source=./crosswarp.glsl" \
    -y /tmp/out_pbo.mp4 2>&1 | tail -5
  ffprobe /tmp/out_pbo.mp4 2>&1 | grep "Video:"
  ```
  Expected: valid video output, no GL errors in stderr.

- [ ] **Step 7: Commit**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  git add vf_gltransition.c
  git commit -m "feat: PBO double-buffered async readback, eliminate glReadPixels stall"
  ```

---

## Task 8: Push final vf_gltransition.c to fork

**Files:**
- Modify: fork `libavfilter/vf_gltransition.c`

- [ ] **Step 1: Copy final file to fork**

  ```bash
  cp /path/to/ffmpeg-gl-transition/vf_gltransition.c \
     /path/to/ffmpeg-fork/libavfilter/vf_gltransition.c
  cd /path/to/ffmpeg-fork
  git add libavfilter/vf_gltransition.c
  git commit -m "feat: update gltransition to FFmpeg 8.x API + YUV420P + PBO readback"
  git push origin gltransition
  ```

- [ ] **Step 2: Note fork commit SHA in Dockerfile (next task)**

  ```bash
  git rev-parse HEAD
  ```
  Copy this SHA — you'll use it in the Dockerfile.

---

## Task 9: Update Dockerfile and delete ffmpeg.diff

**Files:**
- Modify: `Dockerfile`
- Delete: `ffmpeg.diff`

- [ ] **Step 1: Replace Dockerfile content**

  Replace the current `Dockerfile` with:
  ```dockerfile
  FROM debian:bookworm

  WORKDIR /build

  RUN apt-get update -y && apt-get upgrade -y

  RUN apt-get install -y git gcc g++ make pkg-config \
      libglew-dev libegl-dev \
      nasm yasm libx264-dev libx265-dev libvpx-dev \
      libmp3lame-dev libopus-dev libfdk-aac-dev

  # Fork pinned to known-good commit — no patch file needed
  RUN git clone https://github.com/your-org/ffmpeg.git ffmpeg && \
      cd ffmpeg && git checkout <SHA-FROM-TASK-8>

  RUN git clone https://github.com/transitive-bullshit/ffmpeg-gl-transition.git

  RUN (cd ffmpeg; ./configure \
      --enable-libx264 --enable-libx265 --enable-libvpx \
      --enable-libfdk-aac --enable-libmp3lame --enable-libopus \
      --enable-nonfree --enable-gpl --enable-opengl \
      --enable-filter=gltransition \
      --extra-libs='-lGLEW -lEGL -ldl')

  RUN (cd ffmpeg; make -j$(nproc))
  RUN (cd ffmpeg; make install)

  RUN (cd ffmpeg-gl-transition; ln -s /usr/local/bin/ffmpeg .)
  RUN (cd ffmpeg-gl-transition; bash concat.sh)

  ENTRYPOINT /bin/bash
  ```

  Replace `<SHA-FROM-TASK-8>` with the actual commit SHA from Task 8 Step 2.

- [ ] **Step 2: Delete ffmpeg.diff**

  ```bash
  git rm ffmpeg.diff
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add Dockerfile
  git commit -m "chore: update Dockerfile to use FFmpeg fork, remove ffmpeg.diff"
  ```

---

## Task 10: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Building section**

  Replace the "Building ffmpeg" section with:
  ```markdown
  ## Building

  Clone the pre-patched FFmpeg fork and build:

  ```bash
  git clone https://github.com/your-org/ffmpeg.git ffmpeg
  cd ffmpeg
  ./configure --enable-libx264 --enable-gpl --enable-opengl \
              --enable-filter=gltransition --extra-libs='-lGLEW -lEGL -ldl'
  make -j$(nproc)
  ```

  No patch file needed — `vf_gltransition.c` is already in the fork.

  ### Mac OS
  Replace `-lEGL` with `-lglfw`:
  ```bash
  ./configure --enable-libx264 --enable-gpl --enable-opengl \
              --enable-filter=gltransition --extra-libs='-lGLEW -lglfw'
  ```
  ```

- [ ] **Step 2: Remove the "Building ffmpeg" diff/patch instructions from README**

  Delete any mention of `ffmpeg.diff`, `git apply`, and the old `cp ~/ffmpeg-gl-transition/vf_gltransition.c libavfilter/` instructions.

- [ ] **Step 3: Commit**

  ```bash
  git add README.md
  git commit -m "docs: update build instructions for FFmpeg fork workflow"
  ```

---

## Task 11: Integration test with concat.sh

- [ ] **Step 1: Run the full concat example**

  ```bash
  cd /path/to/ffmpeg-gl-transition
  ln -sf /usr/local/bin/ffmpeg ./ffmpeg  # or path to your built ffmpeg
  bash concat.sh
  ```
  Expected: `out.mp4` created with no errors.

- [ ] **Step 2: Verify output duration and streams**

  ```bash
  ffprobe out.mp4 2>&1 | grep -E "Duration|Video:"
  ```
  Expected: duration ~8s (3 clips × ~3s - 2 × 1s transitions = ~7–8s), single video stream.

- [ ] **Step 3: Visually inspect transitions**

  Open `out.mp4` in a media player and verify:
  - Two transitions occur (crosswarp and default fade)
  - No green/black/corrupt frames
  - Colors look correct (not tinted — would indicate YUV coefficient bug)

- [ ] **Step 4: Final commit tag**

  ```bash
  git tag v2.0.0
  git push origin master --tags
  ```

---

## Self-Review Notes

- **PIXEL_FORMAT macro** is removed in Task 6 — verify it's not referenced elsewhere before deleting
- **`outFrame->linesize[0] / 3`** was used for RGB24 row length; replaced with plain `0` for PBO path (PBO uses tightly packed output). If `outFrame->linesize[0] != outLink->w * 3`, the memcpy in Task 7 will copy the right pixel count but FFmpeg may expect padded rows — add a `GL_PACK_ROW_LENGTH` set if needed
- **Mac OS / GLFW path** is preserved via `#ifdef GL_TRANSITION_USING_EGL` throughout — no Mac-specific changes needed beyond what's already there
- **`f_default_transition_source`** is untouched and still works since the preamble provides `getFromColor`/`getToColor`
