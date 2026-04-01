extends Node

var coins: int = 0
signal coins_changed(new_amount)

func add_coin(amount: int):
	coins += amount
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)

func remove_coin(amount: int):
	coins -= amount
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)

func reset_coin():
	coins = 0
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)
