# Third-party software

Release builds of Cinema bundle **mpv** and the libraries it links against, copied unmodified from
Homebrew's bottles (macOS arm64). They keep their own licences, listed below. Cinema's own code is MIT
(see `LICENSE`); the bundled components are separate programs and libraries that Cinema runs, not part
of Cinema's source.

**GPL notice.** mpv and FFmpeg as built by Homebrew are licensed under the GPL (FFmpeg is built with
`--enable-gpl`). The corresponding source code for every component is available from its upstream
project (links below) and from Homebrew's formula for the exact version listed
(`brew info <name>` / `brew fetch --build-from-source <name>`). If you need a copy of the exact sources
used for a Cinema release, open an issue and it will be provided.

| Component | Version | Licence | Files |
|---|---|---|---|
| [brotli](https://github.com/google/brotli) | 1.2.0 | MIT | libbrotlicommon.1.2.0.dylib, libbrotlidec.1.2.0.dylib |
| [dav1d](https://code.videolan.org/videolan/dav1d) | 1.5.4 | BSD-2-Clause | libdav1d.7.dylib |
| [ffmpeg](https://ffmpeg.org/) | 9.0.2 | GPL-3.0-or-later | libavcodec.63.1.102.dylib, libavdevice.63.1.102.dylib, libavfilter.12.1.102.dylib, libavformat.63.1.102.dylib, libavutil.61.1.102.dylib, libswresample.7.1.102.dylib, libswscale.10.1.102.dylib |
| [fontconfig](https://wiki.freedesktop.org/www/Software/fontconfig/) | 2.18.3 | HPND-sell-variant AND Unicode-3.0 AND MIT-Modern-Variant AND MIT AND LicenseRef-Homebrew-public-domain | libfontconfig.1.dylib |
| [freetype](https://www.freetype.org/) | 2.15.0 | FTL | libfreetype.6.dylib |
| [fribidi](https://github.com/fribidi/fribidi) | 1.0.17 | GPL-2.0-or-later AND LGPL-2.1-or-later | libfribidi.0.dylib |
| [gettext](https://www.gnu.org/software/gettext/) | 1.0 | GPL-3.0-or-later AND LGPL-2.1-or-later | libintl.8.dylib |
| [glib](https://docs.gtk.org/glib/) | 2.90.1 | LGPL-2.1-or-later | libglib-2.0.0.dylib |
| [graphite2](https://graphite.sil.org/) | 1.3.15 | MIT OR MPL-2.0 OR LGPL-2.1-or-later OR GPL-2.0-or-later | libgraphite2.3.3.1.dylib |
| [harfbuzz](https://github.com/harfbuzz/harfbuzz) | 14.6.0 | MIT | libharfbuzz.0.dylib |
| [jpeg-turbo](https://www.libjpeg-turbo.org/) | 3.2.0 | IJG AND Zlib AND BSD-3-Clause | libjpeg.8.3.2.dylib |
| [lame](https://lame.sourceforge.io/) | 4.0 | LGPL-2.0-or-later | libmp3lame.0.dylib |
| [libarchive](https://www.libarchive.org) | 3.8.10 | BSD-2-Clause | libarchive.13.dylib |
| [libass](https://github.com/libass/libass) | 0.17.5 | ISC | libass.9.dylib |
| [libb2](https://blake2.net/) | 0.98.1 | CC0-1.0 | libb2.1.dylib |
| [libbluray](https://www.videolan.org/developers/libbluray.html) | 1.5.0 | LGPL-2.1-or-later | libbluray.4.dylib |
| [libplacebo](https://code.videolan.org/videolan/libplacebo) | 7.360.1 | LGPL-2.1-or-later | libplacebo.360.dylib |
| [libpng](https://www.libpng.org/pub/png/libpng.html) | 1.6.59 | libpng-2.0 | libpng16.16.dylib |
| [libsamplerate](https://github.com/libsndfile/libsamplerate) | 0.2.2 | BSD-2-Clause | libsamplerate.0.2.2.dylib |
| [libudfread](https://code.videolan.org/videolan/libudfread) | 1.2.0 | LGPL-2.1-or-later | libudfread.3.dylib |
| [libunibreak](https://github.com/adah1972/libunibreak) | 8.0 | Zlib | libunibreak.8.dylib |
| [libvmaf](https://github.com/Netflix/vmaf) | 3.2.1 | BSD-2-Clause-Patent | libvmaf.3.dylib |
| [libvpx](https://www.webmproject.org/code/) | 1.17.0 | BSD-3-Clause | libvpx.12.dylib |
| [little-cms2](https://www.littlecms.com/) | 2.19.1 | MIT | liblcms2.2.dylib |
| [luajit](https://luajit.org/luajit.html) | 2.1.1791988261 | MIT | libluajit-5.1.2.1.1791988261.dylib |
| [lz4](https://lz4.github.io/lz4/) | 1.10.0 | BSD-2-Clause | liblz4.1.10.0.dylib |
| [molten-vk](https://github.com/KhronosGroup/MoltenVK) | 1.4.2 | Apache-2.0 | libMoltenVK.dylib |
| [mpg123](https://www.mpg123.de/) | 1.33.7 | LGPL-2.1-only | libmpg123.0.dylib |
| [mpv](https://mpv.io) | 0.41.0 | GPL-2.0-or-later AND LGPL-2.1-or-later | mpv (executable) |
| [mujs](https://www.mujs.com/) | 1.3.10 | ISC | libmujs.dylib |
| [openssl@4](https://openssl-library.org) | 4.0.3 | Apache-2.0 | libcrypto.4.dylib, libssl.4.dylib |
| [opus](https://www.opus-codec.org/) | 1.6.1 | BSD-3-Clause | libopus.0.dylib |
| [pcre2](https://www.pcre.org/) | 10.49 | BSD-3-Clause | libpcre2-8.0.dylib |
| [rubberband](https://breakfastquay.com/rubberband/) | 4.0.0 | GPL-2.0-or-later | librubberband.3.dylib |
| [shaderc](https://github.com/google/shaderc) | 2026.4 | Apache-2.0 | libshaderc_shared.1.dylib |
| [svt-av1](https://gitlab.com/AOMediaCodec/SVT-AV1) | 4.2.0 | BSD-3-Clause | libSvtAv1Enc.4.2.0.dylib |
| [uchardet](https://www.freedesktop.org/wiki/Software/uchardet/) | 0.0.8 | MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later | libuchardet.0.0.8.dylib |
| [vulkan-loader](https://github.com/KhronosGroup/Vulkan-Loader) | 1.4.363.0 | Apache-2.0 | libvulkan.1.4.363.dylib |
| [x264](https://www.videolan.org/developers/x264.html) | r3222 | GPL-2.0-or-later | libx264.165.dylib |
| [x265](https://github.com/Multicorewareinc/x265) | 4.3 | GPL-2.0-or-later | libx265.217.dylib |
| [xz](https://tukaani.org/xz/) | 5.8.4 | 0BSD AND GPL-2.0-or-later | liblzma.5.dylib |
| [zimg](https://github.com/sekrit-twc/zimg) | 3.0.6 | WTFPL | libzimg.2.dylib |
| [zstd](https://facebook.github.io/zstd/) | 1.5.7 | (BSD-3-Clause OR GPL-2.0-only) AND BSD-2-Clause AND MIT | libzstd.1.5.7.dylib |
