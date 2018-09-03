-- Live Simulator: 2 Extensions Lua binding
-- Part of Live Simulator: 2 Extensions
-- See copyright notice in LS2X main.cpp

assert(jit and jit.status(), "JIT compiler must be enabled")

local ls2x = {}
local lib = require("ls2xlib")
local ffi = require("ffi")

-- audiomix
if lib.features.audiomix then
	local audiomix = {}
	ls2x.audiomix = audiomix

	audiomix.resample = ffi.cast("void(*)(const short*, short*, size_t, size_t, int)", lib.rawptr.resample)
	audiomix.startSession = ffi.cast("bool(*)(int, size_t)", lib.rawptr.startAudioMixSession)
	audiomix.mixSample = ffi.cast("bool(*)(const short *, size_t, int)", lib.rawptr.mixSample)
	audiomix.getSample = ffi.cast("const short*(*)()", lib.rawptr.getAudioMixPointer)
	audiomix.endSession = ffi.cast("void(*)()", lib.rawptr.endAudioMixSession)
end

-- fft
if lib.features.fft then
	local fft = {}
	local scalarType = ffi.string(ffi.cast("const char*(*)()", lib.rawptr.scalarType)())
	ls2x.fft = fft
	ffi.cdef("typedef "..scalarType.." kiss_fft_scalar;")
	fft.fftr1 = ffi.cast("void(*)(const short *, kiss_fft_scalar *, kiss_fft_scalar *, size_t)", lib.rawptr.fftr1)
	fft.fftr2 = ffi.cast("void(*)(const short *, kiss_fft_scalar *, size_t, bool)", lib.rawptr.fftr2)
end

-- libav
if lib.features.venc then
	local venc = {}
	ls2x.venc = venc
	
	venc.startSession = ffi.cast("bool(*)(const char *, int, int, int, int)", lib.rawptr.startEncodingSession)
	venc.supply = ffi.cast("bool(*)(const void *, short *, size_t)", lib.rawptr.supplyEncoder)
	venc.endSession = ffi.cast("void(*)()", lib.rawptr.endEncodingSession)
end

return ls2x
