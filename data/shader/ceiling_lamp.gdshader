shader_type canvas_item;
render_mode blend_mul;

// 吊顶灯【乘法层】—— 只负责"暗"。
// 光锥外乘 dark_color 压成靛蓝；光锥内乘 1，原图分毫不动。
//
// ⚠️ 这里的值必须 ≤ 1。2D 画布是 8 位定点混合，着色器输出会先被 clamp 到 [0,1]
//    再相乘，填 2.5 实际生效的是 1.0 —— 乘法做不出"比原图更亮"。
//    想要灯下【比原图更亮】是加法层的活，见 ceiling_lamp_add.gdshader。
//
// 形状计算和加法层共用，见 lamp_cone.gdshaderinc。

#include "res://data/shader/lamp_cone.gdshaderinc"

uniform vec3 dark_color = vec3(0.40, 0.42, 0.63);     // 没灯照到：压成靛蓝
uniform vec3 lamp_color = vec3(1.00, 1.00, 1.00);     // 一盏灯照到：什么都不做
uniform vec3 overlap_color = vec3(1.00, 0.99, 0.95);  // 两锥交叠：几乎不动，暖色交给加法层
uniform vec3 tube_color = vec3(1.00, 1.00, 1.00);     // 灯管本体：不压暗

void fragment() {
	float hits;
	float tube;
	float glow;   // 光晕只参与加法层，这里不用，但函数签名要收着
	lamp_shape(UV, hits, tube, glow);

	vec3 c = mix(dark_color, lamp_color, step(0.5, hits));
	c = mix(c, overlap_color, step(1.5, hits));
	c = mix(c, tube_color, tube);

	// 往纯白插值 = 淡入淡出。乘法混合下 alpha 不起作用，淡入必须在这儿做。
	COLOR = vec4(mix(vec3(1.0), c, amount), 1.0);
}
