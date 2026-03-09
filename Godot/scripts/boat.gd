extends CharacterBody2D

@onready var speed_car = $"."
@onready var car_collision___rotation_node = $CollisionShape2D
@onready var enter_hint_label = $Label

const SPEED = 200.0

var activePlayer = false
var player_ref: Node = null # ✅ référence au player

func _ready():
	enter_hint_label.visible = false


func _input(event):
	if event.is_action_pressed("ui_interact") and enter_hint_label.visible and not activePlayer:
		_control_car()
	elif event.is_action_pressed("ui_interact") and activePlayer:
		_leave_car()


func _control_car():
	player_ref = get_tree().get_first_node_in_group("player")
	if player_ref == null:
		return

	activePlayer = true
	player_ref.hide() # ✅ au lieu de queue_free()
	enter_hint_label.hide()


func _leave_car():
	if player_ref == null:
		return

	activePlayer = false
	player_ref.global_position = global_position
	player_ref.show() # ✅
	player_ref = null


func _physics_process(delta):
	if not activePlayer:
		return
	
	var direction = Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")

	if direction != Vector2.ZERO:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

	_set_animation()
	move_and_slide()


func _set_animation():
	if velocity == Vector2.ZERO:
		return

	if velocity.y < 0 and velocity.x < 0:
		speed_car.play("up_left")
		car_collision___rotation_node.rotation_degrees = -45
	elif velocity.y < 0 and velocity.x > 0:
		speed_car.play("up_right")
		car_collision___rotation_node.rotation_degrees = 45
	elif velocity.y > 0 and velocity.x < 0:
		speed_car.play("down_left")
		car_collision___rotation_node.rotation_degrees = -135
	elif velocity.y > 0 and velocity.x > 0:
		speed_car.play("down_right")
		car_collision___rotation_node.rotation_degrees = 135
	elif velocity.x < 0:
		speed_car.play("left")
		car_collision___rotation_node.rotation_degrees = -90
	elif velocity.x > 0:
		speed_car.play("right")
		car_collision___rotation_node.rotation_degrees = 90
	elif velocity.y < 0:
		speed_car.play("up")
		car_collision___rotation_node.rotation_degrees = 0
	elif velocity.y > 0:
		speed_car.play("down")
		car_collision___rotation_node.rotation_degrees = 180


func _on_area_2d_body_entered(body):
	if body.is_in_group("player"):
		enter_hint_label.show()


func _on_area_2d_body_exited(body):
	if body.is_in_group("player"):
		enter_hint_label.hide()
