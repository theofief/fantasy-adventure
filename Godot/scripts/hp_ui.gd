extends Label

func _ready():
	update_hearts(GlobalHp.hp)
	GlobalHp.connect("hp_changed", Callable(self, "_on_hp_changed"))

func _on_hp_changed(new_amount: int) -> void:
	update_hearts(new_amount)

func update_hearts(amount: int):
	text = "♥️".repeat(amount)
