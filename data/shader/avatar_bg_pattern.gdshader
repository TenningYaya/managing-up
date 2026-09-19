shader_type canvas_item;

// 头像纯色底 + 硬边纹理。按稀有度切换花样，夹在纯色底和角色立绘之间。
//   pattern_type: 0 = 无 / 1 = 坐标纸网格(R) / 2 = 45°斜纹(SR) / 3 = 放射线(SSR)
//
// ⚠️ 全程硬切（阈值判断），不用 smoothstep：像素美术里出现平滑过渡会立刻出戏。
// ⚠️ cell_size / line_width 单位是【屏幕像素】，靠 fwidth(UV) 反推节点实际尺寸，
//    所以同一套参数在 75×75 的卡片头像和 100×100 的面板立绘上粗细一致，不会一个粗一个细。

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // 底色
uniform vec4 pattern_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // 纹理色（建议用底色调深一档，别用纯黑）
uniform float pattern_alpha : hint_range(0.0, 1.0, 0.01) = 0.15;      // 纹理强度，从 0 往上拉到顺眼为止
uniform int pattern_type : hint_range(0, 3) = 0;

uniform float cell_size : hint_range(2.0, 32.0, 1.0) = 8.0;    // 纹理周期
uniform float line_width : hint_range(1.0, 8.0, 1.0) = 1.0;    // 线宽

uniform float ray_count : hint_range(4.0, 48.0, 2.0) = 14.0;   // 放射线条数（取偶数才均匀）
// 放射中心，UV 空间：(0.5, 0.5) = 头像正中心。
// ⚠️ 别把它挪到节点外（比如 y>1）——那样节点只覆盖整圈里很小一段角度，
//    画面里只装得下一两个扇形，看起来就是一个大三角形而不是放射线。
uniform vec2 ray_origin = vec2(0.5, 0.5);
uniform float ray_rotation : hint_range(0.0, 360.0, 1.0) = 0.0;  // 整体旋转，避免扇形边缘正好压在水平/垂直线上

void fragment() {
	// 节点的屏幕像素尺寸：fwidth(UV) 是 UV 的每像素变化量，取倒数即可反推
	vec2 node_px = vec2(1.0) / fwidth(UV);
	vec2 pos = UV * node_px;

	float on = 0.0;

	if (pattern_type == 1) {
		// 坐标纸网格：横竖等距硬线
		vec2 g = mod(pos, cell_size);
		on = (g.x < line_width || g.y < line_width) ? 1.0 : 0.0;

	} else if (pattern_type == 2) {
		// 45° 斜纹：x+y 等值线即为对角线
		on = mod(pos.x + pos.y, cell_size) < line_width ? 1.0 : 0.0;

	} else if (pattern_type == 3) {
		// 放射线：按角度量化成硬扇形、奇偶交替。
		// 画"扇形"而不是"线"，所以无论缩放到多大都不会抖、不会断。
		vec2 v = pos - ray_origin * node_px;
		float ang = atan(v.y, v.x) + radians(ray_rotation);
		float k = floor((ang / 6.2831853 + 0.5) * ray_count);
		on = mod(k, 2.0) < 1.0 ? 1.0 : 0.0;
	}

	vec3 rgb = mix(base_color.rgb, pattern_color.rgb, on * pattern_alpha);
	COLOR = vec4(rgb, base_color.a);
}
