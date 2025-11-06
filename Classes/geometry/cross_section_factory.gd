class_name CrossSectionFactory
extends RefCounted

static func get_cross_section_func(type: String, thickness_modifier: float, dimensions: Dictionary) -> Callable:
	match dimensions.type:
		"box":
			return _box_cross_section.bindv([dimensions.width, dimensions.height, thickness_modifier])
		"circle":
			return _circle_cross_section.bindv([dimensions.radius, thickness_modifier])
		"equals":
			return _equals_cross_section.bindv([thickness_modifier])
		"multipole":
			return _multipole_cross_section.bindv([
				dimensions.num_poles, dimensions.pole_width,
				dimensions.pole_height, dimensions.pole_radius, thickness_modifier
			])
	return _box_cross_section.bindv([0.3, 0.3, thickness_modifier])


static func _box_cross_section(width: float, height: float, thickness_modifier: float, offset: Vector2 = Vector2.ZERO) -> Array[Array]:
	var w := width * thickness_modifier
	var h := height * thickness_modifier
	return [[
		Vector2(-w, -h) + offset,
		Vector2(w, -h) + offset,
		Vector2(w, h) + offset,
		Vector2(-w, h) + offset
	]]


static func _equals_cross_section(thickness_modifier: float) -> Array[Array]:
	var w := 0.3 * thickness_modifier
	var h := 0.1 * thickness_modifier
	var gap := 0.4 * thickness_modifier
	return [
		_box_cross_section(w, h, 1.0, Vector2(0, gap / 2))[0],
		_box_cross_section(w, h, 1.0, Vector2(0, -gap / 2))[0]
	]


static func _circle_cross_section(radius: float, thickness_modifier: float, sides: int = 20) -> Array[Array]:
	var pts: Array[Vector2] = []
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius * thickness_modifier)
	return [pts]


static func _multipole_cross_section(num_poles: int, width: float, height: float, radius: float, thickness_modifier: float) -> Array[Array]:
	var polys: Array[Array] = []
	for i in num_poles:
		var angle := TAU * float(i) / num_poles + TAU / (2 * num_poles)
		var offset := Vector2(cos(angle), sin(angle)) * radius * thickness_modifier
		var w := width * thickness_modifier
		var h := height * thickness_modifier
		var poly: Array[Vector2] = [
			Vector2(-w, -h),
			Vector2(w, -h),
			Vector2(w, h),
			Vector2(-w, h)
		]
		var rotation_angle := angle + PI / 2
		var rotated_poly: Array = poly.map(func(p): return p.rotated(rotation_angle))
		rotated_poly = rotated_poly.map(func(p): return p + offset)
		polys.append(rotated_poly)
	return polys
