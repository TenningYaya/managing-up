shader_type canvas_item;

// 窗外天空的昼夜叠色。
// ⚠️ 为什么不用 modulate：modulate 是【乘法】，只能把颜色压暗，
//    没法给蓝天"加"上原本没有的颜色。这里用 mix() 做叠色，想染成什么色都行。
//
// 参数由 DayNight 单例每帧写入：
//   tint_color     = Gradient 的 RGB（叠什么颜色）
//   tint_strength  = Gradient 的 Alpha（叠多强，0=完全原图，1=完全被染色）
//   sky_compensate = 1 / CanvasModulate 的颜色。
//                    作用是【把室内的压暗除掉】，这样你调亮室内时窗外不会跟着亮，
//                    两个旋钮互不干扰。不想要这个行为就在 DayNight 里关 COMPENSATE_SKY。

uniform vec4 tint_color : source_color = vec4(0.12, 0.16, 0.34, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 sky_compensate = vec3(1.0);

void fragment() {
	// COLOR 进来时已经是「贴图颜色 × 节点 modulate」，
	// 所以直接在它上面加工就行，不用再 texture() 一次，也不需要 MODULATE。
	COLOR.rgb = mix(COLOR.rgb, tint_color.rgb, tint_strength) * sky_compensate;
}
