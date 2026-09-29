shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled, shadows_disabled;
// Opaque cel-shaded solid with alpha-scissor dissolve (earth spikes, ice crystals, rocks).
#define SOLID_MODE
#include "res://shaders/vfx_elements/el_body.gdshaderinc"
