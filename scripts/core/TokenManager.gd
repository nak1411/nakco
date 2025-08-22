class_name TokenManager
extends Node

const SAVE_FILE_PATH = "user://eve_tokens.dat"
const ENCRYPTION_PASSWORD = "eve_trader_tokens_v1"  # Change this to something unique

var stored_tokens: Dictionary = {}


func _ready():
	load_tokens()


func save_token_data(access_token: String, refresh_token: String, character_id: int, expires_at: int):
	var token_data = {"access_token": access_token, "refresh_token": refresh_token, "character_id": character_id, "expires_at": expires_at, "saved_at": Time.get_unix_time_from_system()}

	stored_tokens[str(character_id)] = token_data
	_save_to_file()
	print("Token data saved for character: ", character_id)


func get_token_data(character_id: int) -> Dictionary:
	var char_key = str(character_id)
	if stored_tokens.has(char_key):
		var token_data = stored_tokens[char_key]

		# Check if token is expired
		var current_time = Time.get_unix_time_from_system()
		if current_time < token_data.get("expires_at", 0):
			print("Valid token found for character: ", character_id)
			return token_data
		else:
			print("Token expired for character: ", character_id)
			# Try to refresh the token
			return {}

	print("No valid token found for character: ", character_id)
	return {}


func get_all_saved_characters() -> Array:
	var characters = []
	for char_id in stored_tokens.keys():
		var token_data = stored_tokens[char_id]
		characters.append({"character_id": int(char_id), "saved_at": token_data.get("saved_at", 0), "expires_at": token_data.get("expires_at", 0)})
	return characters


func remove_character_tokens(character_id: int):
	var char_key = str(character_id)
	if stored_tokens.has(char_key):
		stored_tokens.erase(char_key)
		_save_to_file()
		print("Removed token data for character: ", character_id)


func clear_all_tokens():
	stored_tokens.clear()
	_save_to_file()
	print("All token data cleared")


func _save_to_file():
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		print("Failed to open save file for writing")
		return

	var json_string = JSON.stringify(stored_tokens)
	file.store_string(json_string)
	file.close()


func load_tokens():
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("No saved tokens file found")
		return

	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		print("Failed to open save file for reading")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("Failed to parse saved tokens")
		return

	stored_tokens = json.data
	print("Loaded tokens for ", stored_tokens.size(), " characters")


func is_token_valid(character_id: int) -> bool:
	var token_data = get_token_data(character_id)
	return not token_data.is_empty()
