shader_type canvas_item;
render_mode blend_add;

// 吊顶灯【加法层】—— 只负责"亮"。盖在乘法层上面。
//
// 为什么需要它：乘法最多只能做到"原图亮度"，做不出【比原图更亮】，
// 所以灯底下看着只是"白天的颜色"，没有被照亮的感觉。加法能补上这一截。
//
// 为什么不会发灰：它【只在光锥和光晕内出数】，其余地方加 0，
// 暗的地方照样实打实地暗。早先那版糊满全屏，把暗部一起抬亮，黑场就没了。
//
// 数值很小就够。0.10 已经是很明显的"被照亮"，上到 0.3 就开始过曝糊成一片。
// 形状计算和乘法层共用，见 lamp_cone.gdshaderinc。

#include "res://data/shader/lamp_cone.gdshaderinc"

uniform vec3 lit_add = vec3(0.05, 0.06, 0.11);        // 一盏灯照到：加一点光
uniform vec3 overlap_add = vec3(0.20, 0.20, 0.17);    // 两锥交叠：更亮的淡黄
// 灯周围的光晕。它四面八方扩散，光锥之外也有 —— 那正是"雾状"的来源：
// 暗区被加上一点点光，就成了灯周围的朦胧感。
uniform vec3 glow_add = vec3(0.14, 0.125, 0.085);

// 灯芯：灯管自身的强光，整套里最亮的一处。它是光源，得比它照亮的东西更亮。
uniform vec3 core_add = vec3(0.45, 0.42, 0.33);

// ── 纵向衰减 ──
// 光越往下越弱。只作用在【加法层】—— 乘法层照旧灯下乘 1，
// 所以灯下仍然是正常亮度，衰减掉的只是额外叠上去的那层光。
// 好处：衰减再狠也不会把桌椅人物压暗，只是"光没那么浓"。
// fade_dist 单位是参考矩形高度：1.0 = 从灯一路衰减到办公区底部。
uniform float fade_dist : hint_range(0.05, 3.0, 0.01) = 1.0;
uniform float fade_min : hint_range(0.0, 1.0, 0.01) = 0.0;    // 最远处还剩多少
uniform float fade_power : hint_range(0.3, 4.0, 0.1) = 1.0;   // 曲线。>1 顶部亮区更集中

void fragment() {
	float hits;
	float glow;
	float depth;
	float core;
	vec2 rc;    // 夜幕渐变是乘法层的活，这里收着不管
	lamp_shape(UV, hits, glow, depth, core, rc);

	// depth = 在照亮它的那盏灯下方多远。没被照到时是个极大值，clamp 之后直接到底。
	float fd = clamp(depth / max(fade_dist, 0.0001), 0.0, 1.0);
	float fade = mix(1.0, fade_min, pow(fd, fade_power));

	vec3 c = lit_add * fade * step(0.5, hits);
	c = max(c, overlap_add * fade * step(1.5, hits));
	// 光晕和灯芯都取 max 而不是相加：相加会在灯附近直接爆掉
	c = max(c, glow_add * glow);
	c = max(c, core_add * core);

	// 加法混合是 src.rgb × src.a 加上去，所以 alpha 直接当淡入系数用
	COLOR = vec4(c, amount);
}
