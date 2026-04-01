extends Node

var hp: int = 3
var max_hp: int = 3

signal hp_changed(new_amount)

func remove_hp(amount: int):
	hp -= amount

	if hp <= 0:
		GlobalCoins.reset_coin()
		hp = max_hp

	print("Total hp:", hp)
	emit_signal("hp_changed", hp)
