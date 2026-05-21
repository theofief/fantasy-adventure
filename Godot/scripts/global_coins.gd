extends Node

var coins: int = 0
signal coins_changed(new_amount)

func add_coin(amount: int):
	coins += amount
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()

func remove_coin(amount: int):
	coins -= amount
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()

func reset_coin():
	coins = 0
	print("Total coins:", coins)
	emit_signal("coins_changed", coins)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()
