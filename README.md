# ffmpeg-gl-transition

> FFmpeg filter for applying GLSL transitions between video streams ([gl-transitions](https://gl-transitions.com/)).

![](https://raw.githubusercontent.com/transitive-bullshit/ffmpeg-gl-transition/master/test/crosswarp.gif)

## Intro

[FFmpeg](http://ffmpeg.org/) is the defacto standard in command-line video editing, but it is really difficult to concatenate videos together using non-trivial transitions. Here are some [convoluted](https://superuser.com/questions/778762/crossfade-between-2-videos-using-ffmpeg) [examples](https://video.stackexchange.com/questions/17502/concate-two-video-file-with-fade-effect-with-ffmpeg-in-linux) of a simple cross-fade between two videos. FFmpeg filter graphs are extremely powerful, but for implementing transitions, they are overly complicated and error-prone.

On the other hand, [GL Transitions](https://gl-transitions.com/) is a great open source initiative spearheaded by [Gaëtan Renaudeau](https://github.com/gre) that is aimed at using GLSL to establish a universal [collection](https://gl-transitions.com/gallery) of transitions.

**This library is an ffmpeg extension that makes it easy to use gl-transitions in ffmpeg filter graphs.**

## Building

Since this library exports a new, native ffmpeg filter, you are required to build ffmpeg from source.

```bash
git clone http://source.ffmpeg.org/git/ffmpeg.git ffmpeg
cd ffmpeg

ln -s ~/ffmpeg-gl-transition/vf_gltransition.c libavfilter/
git apply ~/ffmpeg-gl-transition/ffmpeg.diff

./configure --enable-libx264 --enable-gpl --enable-opengl \
            --enable-filter=gltransition --extra-libs='-lGLEW -lglfw'
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

Basic:
```bash
./ffmpeg -i test/0.mp4 -i test/1.mp4 -filter_complex gltransition -y test/out.mp4
```

Advanced:
```bash
./ffmpeg -i test/0.mp4 -i test/1.mp4 -filter_complex "gltransition=duration=4:offset=1.5:source=crosswarp.glsl" -y test/out.mp4
```

Params:
- **duration** (optional *float*; default=1) length in seconds for the transition to last. Any frames after this duration will pass through the second input.
- **offset** (optional *float*; default=0) length in seconds to wait before beginning the transition. Any frames before this offset will pass through the first input.
- **source** (optional *string*; defaults to a basic crossfade transition) path to the gl-transition source file. This text file must be a valid gl-transition filter, exposing a `transition` function. See [here](https://github.com/gl-transitions/gl-transitions/tree/master/transitions) for a list of glsl source transitions or the [gallery](https://gl-transitions.com/gallery) for a visual list of examples.

Note that ffmpeg filters separate their parameters with colons.

## Todo

- add more examples to repo
- **support default values for gl-transition uniforms**
  - this is the reason a lot of gl-transitions currently appear to not function properly
- support general gl-transition uniforms
- remove restriction that both inputs be the same size
- add gl-transition logic for aspect ratios and resize mode
- transpile webgl glsl to opengl glsl via angle

## Related

- Excellent [example](https://github.com/nervous-systems/ffmpeg-opengl) ffmpeg filter for applying a GLSL shader to each frame of a video stream. Related blog [post](https://nervous.io/ffmpeg/opengl/2017/01/31/ffmpeg-opengl/) and follow-up [post](https://nervous.io/ffmpeg/opengl/2017/05/15/ffmpeg-pbo-yuv/).
- [gl-transitions](https://gl-transitions.com/)
- Original gl-transitions github [issue](https://github.com/gre/transitions.glsl.io/issues/56).
- Similar [project](https://github.com/rectalogic/shad0r) that attempts to use [frei0r](https://www.dyne.org/software/frei0r/) and [MLT](https://www.mltframework.org/) instead of extending ffmpeg directly.
- FFmpeg filter [guide](https://raw.githubusercontent.com/FFmpeg/FFmpeg/master/doc/writing_filters.txt).

## License

MIT © [Travis Fischer](https://github.com/transitive-bullshit)
