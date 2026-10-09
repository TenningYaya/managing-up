shader_type canvas_item;
render_mode blend_add;

// 吊顶灯【加法层】—— 只负责"亮"。盖在乘法层上面。
//
// 为什么需要它：乘法最多只能做到"原图亮度"，做不出【比原图更亮】，
// 所以灯底下看着只是"白天的颜色"，没有被照亮的感觉。加法能补上这一截。
//
// 为什么这次不会像以前那样发灰：以前的加法层糊满全屏，把暗部一起抬亮，
// 黑场就没了。现在它【只在光锥内】出数，锥外加 0，暗的地方照样实打实地暗。
//
// 数值很小就够。0.10 已经是很明显的"被照亮"，上到 0.3 就开始过曝糊成一片。
// 形状计算和乘法层共用，见 lamp_cone.gdshaderinc。

#include "res://data/shader/lamp_cone.gdshaderinc"

uniform vec3 lit_add = vec3(0.10, 0.085, 0.050);      // 一盏灯照到：加一点暖光
uniform vec3 overlap_add = vec3(0.22, 0.200, 0.120);  // 两锥交叠：更亮的淡黄
uniform vec3 tube_add = vec3(0.55, 0.520, 0.400);     // 灯管本体：直接打到发白
// 灯管周围的光晕（最内圈的量）。它四面八方扩散，光锥之外也有 —— 那正是"雾状"的来源：
// 暗区被加上一点点光，就成了灯周围的朦胧感。
uniform vec3 glow_add = vec3(0.14, 0.125, 0.085);

void fragment() {
	float hits;
	float tube;
	float glow;
	lamp_shape(UV, hits, tube, glow);

	vec3 c = vec3(0.0);                          // 没灯照到：一点都不加
	c = mix(c, lit_add, step(0.5, hits));
	c = mix(c, overlap_add, step(1.5, hits));
	// 光晕取 max 而不是相加：相加会在灯管附近直接爆掉
	c = max(c, glow_add * glow);
	c = mix(c, tube_add, tube);

	// 加法混合是 src.rgb × src.a 加上去，所以 alpha 直接当淡入系数用
	COLOR = vec4(c, amount);
}
