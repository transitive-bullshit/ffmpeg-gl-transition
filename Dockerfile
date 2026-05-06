# Build ffmpeg-gl-transition using a pre-patched FFmpeg fork.
# The fork is based on the n8.0 tag and includes vf_gltransition directly.

FROM debian:bookworm

WORKDIR /build

RUN apt-get update -y && apt-get upgrade -y

RUN apt-get install -y git gcc g++ make pkg-config \
    libglew-dev libegl-dev \
    nasm yasm libx264-dev libx265-dev libvpx-dev \
    libmp3lame-dev libopus-dev libfdk-aac-dev

# Clone the pre-patched FFmpeg fork (pin to a specific commit for reproducibility)
# Replace YOUR_ORG and YOUR_COMMIT_SHA with the actual fork org and commit SHA
RUN git clone https://github.com/lucemia/ffmpeg-source.git ffmpeg && \
    cd ffmpeg && git checkout d64ae77b3236a692ebd1ee94863f38dec417a97b

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
