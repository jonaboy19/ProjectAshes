shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
// Alpha-blended elemental shape (dark void, water body, dust, frost mist). See el_body.gdshaderinc.
#include "res://shaders/vfx_elements/el_body.gdshaderinc"
