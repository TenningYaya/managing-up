// 吊顶灯的【形状计算】，被 ceiling_lamp（乘法层）和 ceiling_lamp_add（加法层）共用。
//
// 两层必须用完全相同的几何，否则光锥的暗边和亮边会错开一截。
// 所以参数和算法只写一份放在这儿，两个 shader 都 #include 它。
//
// 【灯的位置来自场景里的节点，不是常量】
// DayNight 每帧扫一遍 "ceiling_lamp" 分组，把每盏灯的实际位置和宽度塞进 lamps 数组。
// 所以你在编辑器里拖灯、缩放灯，光锥自动跟着走，不用改任何数字。
//
// 输出：
//   hits  = 这个点被几盏灯照到（0 / 1 / 2…）
//   glow  = 灯管周围的柔光（0~1）
//   depth = 这个点在照亮它的那盏灯【下方多远】，给加法层做纵向衰减用

const int MAX_LAMPS = 8;

uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.0;  // 0=白天无效果，1=全效果
uniform int lamp_n = 0;
// 每盏灯：x = 中心横坐标，y = 发光底边，z = 半宽，w = 灯图的高。都在 ruv 空间里。
uniform vec4 lamps[MAX_LAMPS];

uniform float spread : hint_range(0.0, 1.0, 0.01) = 0.46;   // 梯形往下张开多少。0 = 直筒
uniform float cone_len : hint_range(0.1, 20.0, 0.05) = 10.0; // 光打多远

// 光的上边界。ruv.y 小于它的地方【光锥一律不生效】，哪怕罩到了。
// 用来挡住窗户：室内的吊灯照不到室外，不设这条线的话光锥会把窗户"挖个洞"，
// 露出白天的玻璃贴图。0 = 参考矩形上沿 = 办公室天花板。
// 注意光晕【不受】这条线限制 —— 灯挂在窗前，一点光晕洒到玻璃上是对的，
// 而且正好填补灯底边到天花板线之间那段空隙。
uniform float light_top : hint_range(-1.0, 1.0, 0.01) = 0.0;


// 灯【自身】发亮的那一截，占灯图高度的比例，从底边往上算。
// 只算下面一截是因为你的图上半部分是锁链 —— 链条不该发光。
uniform float core_frac : hint_range(0.0, 1.0, 0.01) = 0.175;
// 灯芯是个【圆角矩形 + 柔边】，不是硬方块 —— 真光源的边界一定是糊的。
uniform float core_round : hint_range(0.0, 1.0, 0.01) = 0.8;   // 1 = 两头全圆（胶囊）
uniform float core_soft : hint_range(0.0, 0.3, 0.005) = 0.05;  // 柔边往外化开多少
uniform float core_power : hint_range(0.3, 4.0, 0.1) = 1.4;    // 柔边衰减曲线

// 把判定对齐到「大像素」网格。硬边斜线如果按屏幕像素走，台阶会比美术本身的像素还细，
// 看着像锯齿而不像设计。填美术放大倍率；1 = 不对齐。
uniform float block_px : hint_range(1.0, 16.0, 1.0) = 1.0;

// 遮罩铺得比办公区大很多（为了盖住整个画面），但灯的位置不该跟着变。
// 这两个描述「办公区参考矩形」在遮罩里占的位置，灯的计算全用换算后的 ruv。
uniform vec2 ref_min = vec2(0.0);
uniform vec2 ref_size = vec2(1.0);

// ── 灯周围的光晕 ──
// 和光锥是两回事：光锥是"照到哪儿"，光晕是"灯本身在发光"，四面八方都有。
// 灯是一条横线段，所以算的是到【线段】的距离 —— 光晕因此是胶囊形，跟着灯拉长。
uniform float glow_radius : hint_range(0.0, 2.0, 0.01) = 0.25;  // 扩散多远（参考矩形高度的倍数）
uniform float glow_power : hint_range(0.5, 4.0, 0.1) = 2.2;     // 衰减曲线。越大越集中在灯附近
uniform float glow_stretch : hint_range(1.0, 8.0, 0.1) = 1.0;   // >1 = 横向拉长成椭圆
// 0 = 平滑模糊（柔光晕）；≥2 = 量化成那么多圈硬边色阶（像素风的另一种画法）。
uniform float glow_steps : hint_range(0.0, 8.0, 1.0) = 0.0;
uniform float ref_aspect = 1.0;  // 参考矩形宽高比，用来把光晕修圆（不然会压成扁椭圆）

// core = 灯管自身的发光：底边贴着灯、圆角柔边的一块。
// 灯罩和锁链不做任何豁免 —— 它们跟着夜色一起暗，只有灯管在发光。
// rc   = 换算后的坐标（x 0~1 = 办公区左右沿，y 0 = 天花板、1 = 下沿），夜幕渐变要用
void lamp_shape(vec2 uv_in, out float hits, out float glow, out float depth,
		out float core, out vec2 rc) {
	vec2 node_px = vec2(1.0) / fwidth(uv_in);

	vec2 uv = uv_in;
	if (block_px > 1.5) {
		vec2 cells = max(node_px / block_px, vec2(1.0));
		uv = (floor(uv_in * cells) + 0.5) / cells;
	}

	// 换算到「办公区参考矩形」的坐标系：遮罩铺多大，灯的位置都不动
	vec2 ruv = (uv - ref_min) / max(ref_size, vec2(0.0001));
	rc = ruv;

	hits = 0.0;
	glow = 0.0;
	core = 0.0;

	depth = 1e9;   // 没被任何灯照到时保持极大值，加法层据此判定"无光"

	// 循环上界必须是常量 —— 有些驱动不接受 uniform 当上界
	for (int i = 0; i < MAX_LAMPS; i++) {
		if (i >= lamp_n) { break; }

		float cx = lamps[i].x;
		float ly = lamps[i].y;    // 发光底边
		float hw = lamps[i].z;    // 半宽
		float dx = abs(ruv.x - cx);

		// 梯形：t 从灯口 0 到光尽头 1，半宽随 t 线性张开。全程 step，没有过渡带。
		float t = (ruv.y - ly) / cone_len;
		float half_w = hw + spread * clamp(t, 0.0, 1.0);
		// 累加而不是取 max：这样才知道被【几盏】灯照到，重叠处才能单独上色
		// 纵向范围：灯口以下、射程以内、天花板线以下。这三条保持硬边。
		float vspan = step(0.0, t) * step(t, 1.0) * step(light_top, ruv.y);
		float inside = step(dx, half_w) * vspan;
		hits += inside;

		// 记下离照亮它的那盏灯有多远（取最近的一盏），给纵向衰减用
		depth = min(depth, mix(1e9, ruv.y - ly, inside));

		// 到灯这条【线段】的距离：横向先减掉灯自身长度，超出两端才开始算，
		// 这样光晕是个胶囊形（跟着灯拉长），而不是一个圆点。
		// ref_aspect 把横向修成等比，再除 glow_stretch 重新拉长成椭圆。
		float gdx = max(dx - hw, 0.0) * ref_aspect / max(glow_stretch, 0.001);
		float gd = length(vec2(gdx, ruv.y - ly));
		float g = pow(clamp(1.0 - gd / max(glow_radius, 0.0001), 0.0, 1.0), glow_power);
		if (glow_steps >= 1.5) {
			g = ceil(g * glow_steps) / glow_steps;   // 想要硬边色阶时才量化
		}
		glow = max(glow, g);

		// 灯管自身的发光：底边贴着 ly 的一个【圆角矩形】，边缘柔化。
		// 在等比空间里算（x 乘 ref_aspect），不然圆角会被办公区的宽高比压扁。
		float hy = lamps[i].w * core_frac * 0.5;
		float cy = ly - hy;                       // 矩形中心，底边正好落在 ly
		float hx = hw * ref_aspect;
		float rad = min(hx, hy) * core_round;     // 圆角半径跟着灯的大小走
		vec2 q = vec2(abs(ruv.x - cx) * ref_aspect, abs(ruv.y - cy)) - vec2(hx, hy) + vec2(rad);
		float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad;
		// sd <= 0 在矩形内（实心），往外在 core_soft 距离内渐弱到 0
		core = max(core, pow(clamp(1.0 - sd / max(core_soft, 0.0001), 0.0, 1.0), core_power));
	}

}
