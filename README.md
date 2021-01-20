# ffmpeg-gl-transition

> FFmpeg filter for applying GLSL transitions between video streams ([gl-transitions](https://gl-transitions.com/)).

![](https://raw.githubusercontent.com/transitive-bullshit/ffmpeg-gl-transition/master/media/crosswarp.gif)

*(example [crosswarp](https://gl-transitions.com/editor/crosswarp) transition)*

## Note

If you want an easier solution, I recommend checking out [ffmpeg-concat](https://github.com/transitive-bullshit/ffmpeg-concat), an npm module and CLI that allows you to concat a list of videos together using a standard build of ffmpeg along with the same sexy OpenGL transitions.

## Intro

[FFmpeg](http://ffmpeg.org/) is the defacto standard in command-line video editing, but it is really difficult to concatenate videos together using non-trivial transitions. Here are some [convoluted](https://superuser.com/questions/778762/crossfade-between-2-videos-using-ffmpeg) [examples](https://video.stackexchange.com/questions/17502/concate-two-video-file-with-fade-effect-with-ffmpeg-in-linux) of a simple cross-fade between two videos. FFmpeg filter graphs are extremely powerful, but for implementing transitions, they are just too complicated and error-prone.

[GL Transitions](https://gl-transitions.com/), on the other hand, is a great open source initiative spearheaded by [Gaëtan Renaudeau](https://github.com/gre) that is aimed at using GLSL to establish a universal [collection](https://gl-transitions.com/gallery) of transitions. Its extremely simple spec makes it really easy to customize existing transitions or write your own as opposed to struggling with complex ffmpeg filter graphs.

**This library is an ffmpeg extension that makes it easy to use gl-transitions in ffmpeg filter graphs.**


## Building

Since this library exports a native ffmpeg filter, you are required to build ffmpeg from source. Don't worry, though -- it's surprisingly straightforward.

### Dependencies

First, you need to install a few dependencies. Mac OS is very straightforward. On Linux and Windows, there are two options, either using EGL or not using EGL. The main advantage of using EGL is that it is easier to run in headless environments.

#### Mac OS

**GLEW + glfw3**

```
brew install glew glfw
```

Mac OS users should follow instructions for **not** using EGL.

#### Linux with EGL

We default to EGL rather than GLX on Linux to make it easier to run headless, so xvfb is no longer needed.

**glvnd1.0**
[building from source](https://github.com/NVIDIA/libglvnd)

**mesaGL>=1.7 mesaGLU>=1.7**

```base
yum install mesa-libGLU mesa-libGLU-devel
```

**GLEW >=2.0**
[building from source](http://glew.sourceforge.net/)

#### Linux without EGL

If you don't want to use EGL, just comment out this line in `vf_gltransition.c`

```c
#ifndef __APPLE__
# define GL_TRANSITION_USING_EGL // remove this line if you don't want to use EGL
#endif
```

**GLEW**

```bash
yum install glew glew-devel
```

**glfw**
[building from source](http://www.glfw.org/)

On headless environments without EGL, you'll also need to install `xvfb`.

```bash
pkg install xorg-vfbserver (FreeBSD)
apt install xvfb (Ubuntu)

Xvfb :1 -screen 0 1280x1024x16
export DISPLAY=:99
```

### Building ffmpeg

```bash
git clone http://source.ffmpeg.org/git/ffmpeg.git ffmpeg
cd ffmpeg

cp ~/ffmpeg-gl-transition/vf_gltransition.c libavfilter/
git apply ~/ffmpeg-gl-transition/ffmpeg.diff

```

Non-EGL:
```base
./configure --enable-libx264 --enable-gpl --enable-opengl \
            --enable-filter=gltransition --extra-libs='-lGLEW -lglfw'
make
```

EGL:
```base
./configure ... --extra-libs='-lGLEW -lEGL'
make
```

Notes:
- See the official ffmpeg [compilation guide](https://trac.ffmpeg.org/wiki/CompilationGuide) for help building ffmpeg on your platform. I've thoroughly tested this filter on macOS Sierra ([macOS compilation guide](https://trac.ffmpeg.org/wiki/CompilationGuide/macOS)).
- Depending on your platform, there may be slight variations in how [GLEW](http://glew.sourceforge.net/) and [glfw](http://www.glfw.org/) are named (with regard to `--extra-libs`, above), e.g. `-lglew` or `-lglfw3` - check `pkg-config`.
- The above example builds a minimal ffmpeg binary with libx264, but there's nothing codec-specific about the filter itself, so feel free to add or remove any of ffmpeg's bells and whistles.

Here's an example of a more full-featured build configuration:

```bash
./configure --prefix=/usr/local --enable-gpl --enable-nonfree --enable-libass \
  --enable-libfdk-aac --enable-libfreetype --enable-libmp3lame --enable-libtheora \
  --enable-libvorbis --enable-libvpx --enable-libx264 --enable-libx265 \
  --enable-libopus --enable-libxvid \
  --enable-opengl --enable-filter=gltransition --extra-libs='-lGLEW -lglfw'
```

You can verify that the `gltransition` filter is available via:

```bash
./ffmpeg -v 0 -filters | grep gltransition
```

## Usage

Default Options:
```bash
./ffmpeg -i media/0.mp4 -i media/1.mp4 -filter_complex gltransition -y out.mp4
```

Custom Options:
```bash
./ffmpeg -i media/0.mp4 -i media/1.mp4 -filter_complex "gltransition=duration=4:offset=1.5:source=crosswarp.glsl" -y out.mp4
```

Params:
- **duration** (optional *float*; default=1) length in seconds for the transition to last. Any frames outputted after this point will pass through the second video stream untouched.
- **offset** (optional *float*; default=0) length in seconds to wait before beginning the transition. Any frames outputted before this point will pass through the first video stream untouched.
- **source** (optional *string*; defaults to a basic crossfade transition) path to the gl-transition source file. This text file must be a valid gl-transition filter, exposing a `transition` function. See [here](https://github.com/gl-transitions/gl-transitions/tree/master/transitions) for a list of glsl source transitions or the [gallery](https://gl-transitions.com/gallery) for a visual list of examples.

Note that both `duration` and `offset` are relative to the start of this filter invocation, not global time values.

## Examples

See [concat.sh](https://github.com/transitive-bullshit/ffmpeg-gl-transition/blob/master/concat.sh) for a more complex example of concatenating three mp4s together with unique transitions between them.

For any non-trivial concatenation, you'll likely want to make a filter chain comprised of [split](https://ffmpeg.org/ffmpeg-filters.html#split_002c-asplit), [trim](https://ffmpeg.org/ffmpeg-filters.html#trim) + [setpts](https://ffmpeg.org/ffmpeg-filters.html#setpts_002c-asetpts), and [concat](https://ffmpeg.org/ffmpeg-filters.html#concat) (with the `v` for video option) filters in addition to the [gltransition](https://github.com/transitive-bullshit/ffmpeg-gl-transition) filter itself. If you want to concat audio streams in the same pass, you'll need to additionally make use of the [asplit](https://ffmpeg.org/ffmpeg-filters.html#split_002c-asplit), [atrim](https://ffmpeg.org/ffmpeg-filters.html#atrim) + [asetpts](https://ffmpeg.org/ffmpeg-filters.html#setpts_002c-asetpts), and [concat](https://ffmpeg.org/ffmpeg-filters.html#concat) (with the `a` for audio option) filters.

There is no limit to the number of video streams you can concat together in one filter graph, but beyond a couple of streams, you'll likely want to write a wrapper script as the required stream preprocessing gets unwieldly very fast.  See [here](https://github.com/transitive-bullshit/ffmpeg-gl-transition/issues/2#issuecomment-352163624) for a more understandable example of concatenating two, 5-second videos together with a 1s fade inbetween. See [here](https://github.com/transitive-bullshit/ffmpeg-gl-transition/issues/4#issue-284723457) for a more complex example including audio stream concatenation.

## Todo

- simplify filter graph required to achieve multi-file concat in concat.sh
- **support default values for gl-transition uniforms**
  - this is the reason a lot of gl-transitions currently appear to not function properly
- remove restriction that both inputs be the same size
- support general gl-transition uniforms
- add gl-transition logic for aspect ratios and resize mode
- transpile webgl glsl to opengl glsl via angle

## Related

- [ffmpeg-concat](https://github.com/transitive-bullshit/ffmpeg-concat) - Concats a list of videos together using ffmpeg with sexy OpenGL transitions. This module and CLI are easier to use than the lower-level custom filter provided by this library.
- Excellent [example](https://github.com/nervous-systems/ffmpeg-opengl) ffmpeg filter for applying a GLSL shader to each frame of a video stream. Related blog [post](https://nervous.io/ffmpeg/opengl/2017/01/31/ffmpeg-opengl/) and follow-up [post](https://nervous.io/ffmpeg/opengl/2017/05/15/ffmpeg-pbo-yuv/).
- [gl-transitions](https://gl-transitions.com/) and original github [issue](https://github.com/gre/transitions.glsl.io/issues/56).
- Similar [project](https://github.com/rectalogic/shad0r) that attempts to use [frei0r](https://www.dyne.org/software/frei0r/) and [MLT](https://www.mltframework.org/) instead of extending ffmpeg directly.
- FFmpeg filter [guide](https://raw.githubusercontent.com/FFmpeg/FFmpeg/master/doc/writing_filters.txt).
- [awesome-ffmpeg](https://github.com/transitive-bullshit/awesome-ffmpeg) - A curated list of awesome ffmpeg resources with a focus on JavaScript.

## License

MIT © [Travis Fischer](https://transitivebullsh.it)

Support my open source work by <a href="https://twitter.com/transitive_bs">following me on twitter <img src="https://storage.googleapis.com/saasify-assets/twitter-logo.svg" alt="twitter" height="24px" align="center"></a>
