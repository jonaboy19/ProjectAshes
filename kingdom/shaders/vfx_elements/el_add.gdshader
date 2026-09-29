shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;
// Additive elemental shape (fire, light, lightning, wind, energy). See el_body.gdshaderinc.
#include "res://shaders/vfx_elements/el_body.gdshaderinc"
