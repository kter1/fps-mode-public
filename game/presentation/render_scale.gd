class_name RenderScale
extends RefCounted

# Internal 3D heights for the Low / Medium / High presets.
const HEIGHTS := [810,1080,1440]

# A view renders at the screen's real pixel size. The preset only sets the internal 3D
# resolution, which FSR upscales (or supersamples on small windows) instead of
# stretching a fixed-size picture across a 4K display. reference_height is the full
# window height, so split-screen panes together cost about one preset frame.
static func fit(view: SubViewport, output: Vector2i, reference_height: float, quality: int, native: bool) -> void:
	view.size=Vector2i(maxi(1,output.x),maxi(1,output.y))
	var scale:=1.0 if native else clampf(HEIGHTS[clampi(quality,0,2)]/maxf(1.0,reference_height),.25,2.0)
	view.scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR if scale<.99 else Viewport.SCALING_3D_MODE_BILINEAR
	view.scaling_3d_scale=scale

static func internal_size(view: SubViewport) -> Vector2i:
	return Vector2i(Vector2(view.size)*view.scaling_3d_scale)
