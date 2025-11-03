extends Camera3D

@export var rotation_speed: float = 0.003
@export var movement_smoothing: float = 0.15
@export var rotation_smoothing: float = 0.15

var _initial_position: Vector3 = position
var _initial_rotation: Vector3 = rotation
var _direction: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _acceleration: float = 30.0
var _deceleration: float = -10.0
var _vel_multiplier: float = 4.0

var _key_state: Dictionary = {
	"move_forward": false,
	"move_backward": false,
	"move_left": false,
	"move_right": false,
	"move_up": false,
	"move_down": false,
}

var _freelook_enabled: bool = false

var euler_rotation: Vector3 = rotation
var target_euler: Vector3 = rotation

func _unhandled_input(event: InputEvent) -> void:
	if _freelook_enabled and event is InputEventMouseMotion:
		var mouse_delta: Vector2 = event.relative
		target_euler.x -= mouse_delta.y * rotation_speed
		target_euler.y -= mouse_delta.x * rotation_speed
		target_euler.x = clamp(target_euler.x, -PI/2, PI/2)

	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_freelook_enabled = !_freelook_enabled
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _freelook_enabled else Input.MOUSE_MODE_VISIBLE)
			MOUSE_BUTTON_WHEEL_UP:
				_vel_multiplier *= 1.1
			MOUSE_BUTTON_WHEEL_DOWN:
				_vel_multiplier = max(_vel_multiplier / 1.1, 0.2)
	
	elif event is InputEventKey and not event.is_echo():
		if event.keycode in _key_state:
			_key_state[event.keycode] = event.pressed


func _process(delta: float) -> void:
	update_key_state()
	update_movement(delta)
	update_rotation(delta)


func update_key_state() -> void:
	for action in _key_state.keys():
		_key_state[action] = Input.is_action_pressed(action)


func update_movement(delta: float) -> void:
	_direction = Vector3(
		float(_key_state["move_right"]) - float(_key_state["move_left"]),
		float(_key_state["move_up"]) - float(_key_state["move_down"]),
		float(_key_state["move_backward"]) - float(_key_state["move_forward"])
	)
	
	var offset: Vector3 = _direction.normalized() * _acceleration * _vel_multiplier * delta \
		+ _velocity.normalized() * _deceleration * _vel_multiplier * delta
	
	if _direction == Vector3.ZERO and offset.length_squared() > _velocity.length_squared():
		_velocity = Vector3.ZERO
	else:
		var target_velocity: Vector3
		target_velocity.x = clamp(_velocity.x + offset.x, -_vel_multiplier, _vel_multiplier)
		target_velocity.y = clamp(_velocity.y + offset.y, -_vel_multiplier, _vel_multiplier)
		target_velocity.z = clamp(_velocity.z + offset.z, -_vel_multiplier, _vel_multiplier)
		
		_velocity = _velocity.lerp(target_velocity, 1.0 - pow(1.0 - movement_smoothing, delta * 60.0))
		
		translate(_velocity * delta)


func update_rotation(delta: float) -> void:
	euler_rotation = euler_rotation.lerp(target_euler, 1.0 - pow(1.0 - rotation_smoothing, delta * 60.0))
	rotation.x = euler_rotation.x
	rotation.y = euler_rotation.y
	rotation.z = euler_rotation.z


func reset_position() -> void:
	position = _initial_position
	rotation = _initial_rotation
	euler_rotation = _initial_rotation
	target_euler = _initial_rotation
	_vel_multiplier = 4.0
