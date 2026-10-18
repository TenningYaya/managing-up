shader_type canvas_item;
render_mode blend_mul;

// 吊顶灯【乘法层】—— 只负责"暗"。
// 光锥外按高度渐变压暗（靠窗蓝、屋里淡）；光锥内乘 1，原图分毫不动。
//
// ⚠️ 这里的值必须 ≤ 1。2D 画布是 8 位定点混合，着色器输出会先被 clamp 到 [0,1]
//    再相乘，填 2.5 实际生效的是 1.0 —— 乘法做不出"比原图更亮"。
//    灯下【比原图更亮】是加法层的活，见 ceiling_lamp_add.gdshader。
//
// 形状计算和加法层共用，见 lamp_cone.gdshaderinc。

#include "res://data/shader/lamp_cone.gdshaderinc"

// ── 夜幕是【纵向渐变】的，不是一个固定颜色 ──
// 夜色是从窗户渗进来的：靠窗那头最蓝最暗，越往屋里越淡，底部几乎不压暗。
// 好处是不用专门去画两锥之间那块楔形 —— 它露出来的就是这条渐变，
// 天然"下面亮、往上渐渐发蓝"，正是要的效果。
uniform vec3 dark_top = vec3(0.534, 0.616, 0.798);   // 贴着窗户那头
uniform vec3 dark_bottom = vec3(0.97, 0.98, 1.0);    // 屋子深处，几乎不压暗
// 蓝色【最深】的那条线在哪。0 = 天花板，正数往下挪，负数往上提（进玻璃带）。
uniform float dark_start : hint_range(-1.0, 2.0, 0.01) = 0.0;
uniform float dark_span : hint_range(0.05, 3.0, 0.05) = 1.0;  // 从那条线往下渐变多高
// 曲线。⚠️ >1 = 蓝的范围【变大】（我之前注释写反了）；<1 = 蓝的范围变小。
uniform float dark_power : hint_range(0.3, 4.0, 0.1) = 1.0;

// 调试：把夜幕渐变直接画成 绿→红 的色带，看清那两条线到底在哪。
//   纯绿 = 全蓝区（g=0）   纯红 = 全白区（g=1）   中间 = 过渡带
uniform bool debug_gradient = false;
uniform vec3 lamp_color = vec3(1.00, 1.00, 1.00);     // 一盏灯照到：什么都不做
uniform vec3 overlap_color = vec3(1.00, 0.99, 0.95);  // 两锥交叠：几乎不动，暖色交给加法层

void fragment() {
	float hits;
	float glow;
	float depth;   // 这两个只给加法层用，这里收着不管
	float core;    // 灯芯只参与加法层，这里收着不管
	vec2 rc;       // 换算后的坐标：x 0~1 = 办公区左右沿，y 0 = 天花板
	lamp_shape(UV, hits, glow, depth, core, rc);

	// 只有【屋里】才做"越往下越亮"的渐变。
	// 办公区左右之外、以及天花板以上（窗外），都是室外 —— 那儿恒为全夜色，
	// 不然两侧的室外和窗户会跟着屋里一起变白，大晚上看着像白天。
	float indoors = step(0.0, rc.x) * step(rc.x, 1.0) * step(light_top, rc.y);
	float g = indoors * pow(clamp((rc.y - dark_start) / max(dark_span, 0.0001), 0.0, 1.0), dark_power);
	vec3 c = mix(mix(dark_top, dark_bottom, g), lamp_color, step(0.5, hits));
	c = mix(c, overlap_color, step(1.5, hits));

	if (debug_gradient) {
		c = vec3(g, 1.0 - g, 0.0);
	}

	// 往纯白插值 = 淡入淡出。乘法混合下 alpha 不起作用，淡入必须在这儿做。
	COLOR = vec4(mix(vec3(1.0), c, amount), 1.0);
}
