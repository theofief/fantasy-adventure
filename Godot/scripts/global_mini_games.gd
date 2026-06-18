extends Node

signal mini_games_changed(state: Dictionary)

const DEFAULT_KEYS := ["coin", "memory", "harvest"]

var best_scores: Dictionary = {
	"coin": 0,
	"memory": 0,
	"harvest": 0,
}
var runs_played: Dictionary = {
	"coin": 0,
	"memory": 0,
	"harvest": 0,
}
var total_coins_earned: int = 0
var last_played: Dictionary = {}


func apply_state(state: Variant) -> void:
	if typeof(state) != TYPE_DICTIONARY:
		return

	var state_dict := state as Dictionary
	_merge_int_dictionary(best_scores, state_dict.get("bestScores", {}))
	_merge_int_dictionary(runs_played, state_dict.get("runsPlayed", {}))
	total_coins_earned = max(0, int(state_dict.get("totalCoinsEarned", total_coins_earned)))

	var saved_last_played: Variant = state_dict.get("lastPlayed", {})
	if typeof(saved_last_played) == TYPE_DICTIONARY:
		last_played = (saved_last_played as Dictionary).duplicate(true)

	emit_signal("mini_games_changed", get_state())


func get_state() -> Dictionary:
	return {
		"schemaVersion": 1,
		"bestScores": best_scores.duplicate(true),
		"runsPlayed": runs_played.duplicate(true),
		"totalCoinsEarned": total_coins_earned,
		"lastPlayed": last_played.duplicate(true),
	}


func reset_progress(sync_save := true) -> void:
	for key in DEFAULT_KEYS:
		best_scores[key] = 0
		runs_played[key] = 0
	total_coins_earned = 0
	last_played.clear()
	_emit_changed(sync_save)


func get_best_score(score_key: String) -> int:
	return int(best_scores.get(score_key, 0))


func add_coins_earned(amount: int, sync_save := true) -> void:
	if amount <= 0:
		return
	total_coins_earned += amount
	_emit_changed(sync_save)


func record_result(score_key: String, score: int) -> void:
	if not best_scores.has(score_key):
		best_scores[score_key] = 0
	if not runs_played.has(score_key):
		runs_played[score_key] = 0

	best_scores[score_key] = max(int(best_scores[score_key]), score)
	runs_played[score_key] = int(runs_played[score_key]) + 1
	last_played[score_key] = {
		"score": score,
		"playedAtUnixMs": int(Time.get_unix_time_from_system() * 1000.0),
		"playedAtIso": Time.get_datetime_string_from_system(true),
	}
	_emit_changed(true)


func _merge_int_dictionary(target: Dictionary, source: Variant) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	var source_dict := source as Dictionary
	for key in DEFAULT_KEYS:
		target[key] = max(0, int(source_dict.get(key, target.get(key, 0))))


func _emit_changed(sync_save: bool) -> void:
	emit_signal("mini_games_changed", get_state())
	if sync_save and AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()
