RE:LÖVisual
===========

Attempt to rewrite LÖVElyzer to 11.0, and this time for real, support of video output.

External Libraries
------------------

These libraries is used to make RE:LÖVisual:

* LÖVE 11.1 - zLib license

* FFTW 3 - GPLv2 (or later) license (Windows uses FFTW 3.3.5; DLL renamed from `libfftw3-3` to `fftw3`)

* FFTW 3 FFI binding - 3-clause BSD license

* FFmpeg 3.3.3 - GPLv3 or later (see notice below).

FFmpeg Notice
-------------

Although FFmpeg can be compiled with LGPLv2.1 license, the libavformat and the libavcodec **MUST** be built
with `matroska` muxer and `libx264rgb` encoder respectively, which means requires FFmpeg to be compiled as
GPL.

License
-------

GPLv3
