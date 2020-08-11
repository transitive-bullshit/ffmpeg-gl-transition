# ffmpeg - http://ffmpeg.org/download.html
#
# From https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
#
# https://hub.docker.com/r/jrottenberg/ffmpeg/
# https://github.com/jrottenberg/ffmpeg


FROM    ubuntu:18.04 AS base

WORKDIR /tmp/workdir

RUN     apt-get -yqq update && \
        apt-get install -yq --no-install-recommends ca-certificates expat libgomp1 libxcb-shape0 libxcb-xfixes0 libdrm2 libglew2.0 libglfw3 xvfb && \
        apt-get autoremove -y && \
        apt-get clean -y


FROM    base AS build

ENV     FFMPEG_VERSION=4.3.1 \
        AOM_VERSION=2.0.0 \
        FDKAAC_VERSION=2.0.1 \
        FONTCONFIG_VERSION=2.13.92 \
        FREETYPE_VERSION=2.10.2 \
        FRIBIDI_VERSION=1.0.10 \
        KVAZAAR_VERSION=2.0.0 \
        LAME_VERSION=3.100 \
        LIBASS_VERSION=0.14.0 \
        LIBVIDSTAB_VERSION=1.1.0 \
        XVID_VERSION=1.3.7 \
        OGG_VERSION=1.3.4 \
        OPENCOREAMR_VERSION=0.1.5 \
        OPUS_VERSION=1.3.1 \
        OPENJPEG_VERSION=2.3.1 \
        THEORA_VERSION=1.1.1 \
        VORBIS_VERSION=1.3.7 \
        VPX_VERSION=1.9.0 \
        WEBP_VERSION=1.1.0 \
        X265_VERSION=3.2.1 \
        LIBZMQ_VERSION=4.3.2 \
        SRC=/usr/local

ARG     MAKEFLAGS="-j2"
ARG     PKG_CONFIG_PATH="/opt/ffmpeg/share/pkgconfig:/opt/ffmpeg/lib/pkgconfig:/opt/ffmpeg/lib64/pkgconfig:/opt/ffmpeg/lib/x86_64-linux-gnu/pkgconfig"
ARG     PREFIX=/opt/ffmpeg
ARG     LD_LIBRARY_PATH="/opt/ffmpeg/lib:/opt/ffmpeg/lib64"
ARG     CFLAGS=-I${PREFIX}/include/

RUN     buildDeps="autoconf \
                automake \
                cmake \
                curl \
                bzip2 \
                libexpat1-dev \
                g++ \
                gcc \
                git \
                gperf \
                libtool \
                make \
                nasm \
                perl \
                pkg-config \
                python \
                libssl-dev \
                yasm \
                zlib1g-dev \
                libxcb-xfixes0-dev \
                libdrm-dev \
                libglew-dev \
                libglfw3-dev" && \
        apt-get -yqq update && \
        apt-get install -yq --no-install-recommends ${buildDeps}
## opencore-amr https://sourceforge.net/projects/opencore-amr/
RUN \
        DIR=/tmp/opencore-amr && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://versaweb.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-${OPENCOREAMR_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        ./configure --prefix=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## x264 https://code.videolan.org/videolan/x264
RUN \
        DIR=/tmp/x264 && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.gz | \
        tar -zx --strip-components=1 && \
        ./configure --prefix=${PREFIX} --enable-shared --enable-pic --disable-cli && \
        make && \
        make install && \
        rm -rf ${DIR}
## x265 http://x265.org/
RUN \
        DIR=/tmp/x265 && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://download.videolan.org/pub/videolan/x265/x265_${X265_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        cd build/linux && \
        sed -i "/-DEXTRA_LIB/ s/$/ -DCMAKE_INSTALL_PREFIX=\${PREFIX}/" multilib.sh && \
        sed -i "/^cmake/ s/$/ -DENABLE_CLI=OFF/" multilib.sh && \
        sed -i "/^cmake/ s/$/ -DBUILD_SHARED_LIBS=1/" multilib.sh && \
        ./multilib.sh && \
        make -C 8bit install && \
        rm -rf ${DIR}
## libogg https://www.xiph.org/ogg/
RUN \
        DIR=/tmp/ogg && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO http://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f libogg-${OGG_VERSION}.tar.gz && \
        ./configure --prefix=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libopus https://www.opus-codec.org/
RUN \
        DIR=/tmp/opus && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://archive.mozilla.org/pub/opus/opus-${OPUS_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f opus-${OPUS_VERSION}.tar.gz && \
        autoreconf -fiv && \
        ./configure --prefix=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libvorbis https://xiph.org/vorbis/
RUN \
        DIR=/tmp/vorbis && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO http://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f libvorbis-${VORBIS_VERSION}.tar.gz && \
        ./configure --prefix=${PREFIX} --with-ogg=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libtheora http://www.theora.org/
RUN \
        DIR=/tmp/theora && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO http://downloads.xiph.org/releases/theora/libtheora-${THEORA_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f libtheora-${THEORA_VERSION}.tar.gz && \
        ./configure --prefix=${PREFIX} --with-ogg=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libvpx https://www.webmproject.org/code/
RUN \
        DIR=/tmp/vpx && \
        git clone --branch v${VPX_VERSION} --depth 1 https://chromium.googlesource.com/webm/libvpx ${DIR} && \
        cd ${DIR} && \
        ./configure --prefix=${PREFIX} --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth --enable-pic --enable-shared \
        --disable-debug --disable-examples --disable-docs --disable-install-bins && \
        make && \
        make install && \
        rm -rf ${DIR}
## libwebp https://developers.google.com/speed/webp/
RUN \
        DIR=/tmp/vebp && \
        git clone --branch v${WEBP_VERSION} --depth 1 https://chromium.googlesource.com/webm/libwebp ${DIR} && \
        cd ${DIR} && \
        ./autogen.sh && \
        ./configure --prefix=${PREFIX} --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libmp3lame http://lame.sourceforge.net/
RUN \
        DIR=/tmp/lame && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://versaweb.dl.sourceforge.net/project/lame/lame/$(echo ${LAME_VERSION} | sed -e 's/[^0-9]*\([0-9]*\)[.]\([0-9]*\)[.]\([0-9]*\)\([0-9A-Za-z-]*\)/\1.\2/')/lame-${LAME_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        ./configure --prefix=${PREFIX} --bindir=${PREFIX}/bin --enable-shared --enable-nasm --disable-frontend && \
        make && \
        make install && \
        rm -rf ${DIR}
## xvid https://labs.xvid.com/source/#Release
RUN \
        DIR=/tmp/xvid && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO http://downloads.xvid.com/downloads/xvidcore-${XVID_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f xvidcore-${XVID_VERSION}.tar.gz && \
        cd build/generic && \
        ./configure --prefix=${PREFIX} --bindir=${PREFIX}/bin && \
        make && \
        make install && \
        rm -rf ${DIR}
## fdk-aac https://github.com/mstorsjo/fdk-aac
RUN \
        DIR=/tmp/fdk-aac && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://github.com/mstorsjo/fdk-aac/archive/v${FDKAAC_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        autoreconf -fiv && \
        ./configure --prefix=${PREFIX} --enable-shared --datadir=${DIR} && \
        make && \
        make install && \
        rm -rf ${DIR}
## openjpeg https://github.com/uclouvain/openjpeg
RUN \
        DIR=/tmp/openjpeg && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sL https://github.com/uclouvain/openjpeg/archive/v${OPENJPEG_VERSION}.tar.gz | \
        tar -zx --strip-components=1 && \
        cmake -DBUILD_THIRDPARTY:BOOL=ON -DCMAKE_INSTALL_PREFIX=${PREFIX} . && \
        make && \
        make install && \
        rm -rf ${DIR}
## freetype https://www.freetype.org/
RUN \
        DIR=/tmp/freetype && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f freetype-${FREETYPE_VERSION}.tar.gz && \
        ./configure --prefix=${PREFIX} --disable-static --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libvstab https://github.com/georgmartius/vid.stab
RUN \
        DIR=/tmp/vid.stab && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://github.com/georgmartius/vid.stab/archive/v${LIBVIDSTAB_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f v${LIBVIDSTAB_VERSION}.tar.gz && \
        cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} . && \
        make && \
        make install && \
        rm -rf ${DIR}
## fridibi https://github.com/fribidi/fribidi/
RUN \
        DIR=/tmp/fribidi && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://github.com/fribidi/fribidi/archive/v${FRIBIDI_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f v${FRIBIDI_VERSION}.tar.gz && \
        ./autogen.sh && \
        ./configure --prefix=${PREFIX} --disable-static --enable-shared && \
        make -j1 && \
        make install && \
        rm -rf ${DIR}
## fontconfig https://www.freedesktop.org/wiki/Software/fontconfig/
RUN \
        DIR=/tmp/fontconfig && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f fontconfig-${FONTCONFIG_VERSION}.tar.gz && \
        ./configure --prefix=${PREFIX} --disable-static --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## libass https://github.com/libass/libass
RUN \
        DIR=/tmp/libass && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://github.com/libass/libass/archive/${LIBASS_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f ${LIBASS_VERSION}.tar.gz && \
        ./autogen.sh && \
        ./configure --prefix=${PREFIX} --disable-static --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}
## kvazaar https://github.com/ultravideo/kvazaar
RUN \
        DIR=/tmp/kvazaar && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://github.com/ultravideo/kvazaar/archive/v${KVAZAAR_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f v${KVAZAAR_VERSION}.tar.gz && \
        ./autogen.sh && \
        ./configure --prefix=${PREFIX} --disable-static --enable-shared && \
        make && \
        make install && \
        rm -rf ${DIR}

RUN \
        DIR=/tmp/aom && \
        git clone --branch v${AOM_VERSION} --depth 1 https://aomedia.googlesource.com/aom ${DIR} && \
        cd ${DIR} && \
        rm -rf CMakeCache.txt CMakeFiles && \
        mkdir -p ./aom_build && \
        cd ./aom_build && \
        cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} -DBUILD_SHARED_LIBS=1 .. && \
        make && \
        make install && \
        rm -rf ${DIR}
## libzmq https://github.com/zeromq/libzmq/
RUN \
        DIR=/tmp/libzmq && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://github.com/zeromq/libzmq/archive/v${LIBZMQ_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f v${LIBZMQ_VERSION}.tar.gz && \
        ./autogen.sh && \
        ./configure --prefix=${PREFIX} && \
        make && \
        make check && \
        make install && \
        rm -rf ${DIR}
## ffmpeg https://ffmpeg.org/
RUN \
        DIR=/tmp/ffmpeg && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        curl -sLO https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
        tar -zx --strip-components=1 -f ffmpeg-${FFMPEG_VERSION}.tar.gz
## ffmpeg-gl-transition
COPY ./vf_gltransition.c /tmp/ffmpeg/libavfilter/
COPY ./ffmpeg.diff /tmp/ffmpeg/
RUN \
        DIR=/tmp/ffmpeg && \
        cd ${DIR} && \
        git apply ${DIR}/ffmpeg.diff

RUN \
        DIR=/tmp/ffmpeg && \
        cd ${DIR} && \
        ./configure \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
        --disable-static \
        --enable-gpl \
        --enable-version3 \
        --enable-nonfree \
        --enable-shared \
        --enable-avresample \
        --enable-libopencore-amrnb \
        --enable-libopencore-amrwb \
        --enable-libass \
        --enable-fontconfig \
        --enable-libfreetype \
        --enable-libfribidi \
        --enable-libvidstab \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libtheora \
        --enable-libvorbis \
        --enable-libvpx \
        --enable-libwebp \
        --enable-libxcb \
        --enable-libxvid \
        --enable-libx264 \
        --enable-libx265 \
        --enable-openssl \
        --enable-libfdk_aac \
        --enable-postproc \
        --enable-pthreads \
        --enable-small \
        --enable-libzmq \
        --enable-libopenjpeg \
        --enable-libkvazaar \
        --enable-libaom \
        --enable-libdrm \
        --enable-opengl \
        --enable-filter=gltransition \
        --extra-libs="-lGLEW -lglfw -ldl -lpthread" \
        --prefix=${PREFIX} \
        --extra-cflags=-I${PREFIX}/include \
        --extra-ldflags=-L${PREFIX}/lib && \
        make && \
        make install && \
        make tools/zmqsend && cp tools/zmqsend ${PREFIX}/bin/ && \
        make distclean && \
        hash -r && \
        cd tools && \
        make qt-faststart && cp qt-faststart ${PREFIX}/bin/

## cleanup
RUN \
        ldd ${PREFIX}/bin/ffmpeg | grep opt/ffmpeg | cut -d ' ' -f 3 | xargs -i cp {} /usr/local/lib/ && \
        cp ${PREFIX}/bin/* /usr/local/bin/ && \
        cp -r ${PREFIX}/share/ffmpeg /usr/local/share/ && \
        LD_LIBRARY_PATH=/usr/local/lib ffmpeg -buildconf


FROM        base AS release

ENV         LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64

CMD         ["--help"]
ENTRYPOINT  ["ffmpeg"]

COPY --from=build /usr/local /usr/local/
