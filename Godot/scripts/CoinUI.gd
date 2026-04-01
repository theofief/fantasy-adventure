extends Label

func _ready(): # coin supérieur gauche
	text = "%d" % GlobalCoins.coins
	GlobalCoins.connect("coins_changed", Callable(self, "_on_coins_changed"))

func _on_coins_changed(new_amount: int) -> void:
	text = "%d" % new_amount
