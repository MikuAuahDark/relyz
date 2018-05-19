RE:LÖVisual
===========

Attempt to rewrite LÖVElyzer to 11.0, and this time for real, support of video output.

External Libraries
------------------

These libraries is used to make RE:LÖVisual. Fields marked with asterisk are bundled. The rest are mandatory!

* LÖVE 11.1 - zLib license

* FFTW 3 - GPLv2 (or later) license (Windows uses FFTW 3.3.5; DLL renamed from `libfftw3-3` to `fftw3`)

* FFTW 3 FFI binding - 3-clause BSD license \*

* FFmpeg 3.3.3 - GPLv3 or later (see notice below).

Usage
-----

Call `love relyz -help` fore usage details.

Difference between LÖVElyzer
----------------------------

* RE:LÖVisual always work in 16:9 screen ratio, whilst LÖVElyzer depends on AquaShine letterbox.

* RE:LÖVisual requires FFmpeg C API (libav) for audio decoding, whist LÖVElyzer can use FFmpeg CLI or default
LÖVE audio API (`love.audio`) as fallback.

* All visualizer must always assume 1280x720 screen in RE:LÖVisual, whilst in LÖVElyzer, this depends on
user setting.

* RE:LÖVisual can open stereo mix (what you hear) as visualizer input, LÖVElyzer does not.

FFmpeg Notice
-------------

FFmpeg 4.0 is not supported at the moment. Plan to support it is coming soon!

Although FFmpeg can be compiled with LGPLv2.1 license, libavcodec **MUST** be built with
`libx264rgb` encoder respectively, which means requires FFmpeg to be compiled with `libx264` and as GPL.

RE:LÖVisual also requires at least one AAC encoder to be present and `matroska` muxer. It's usually default
but may not, depending on your build options.

License
-------

GPLv3
