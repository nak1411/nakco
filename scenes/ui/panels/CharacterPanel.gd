extends Control

signal character_login_success(character_data: Dictionary)
signal character_logout

@onready var login_button = $VBoxContainer/LoginContainer/LoginButton
@onready var logout_button = $VBoxContainer/CharacterInfo/LogoutButton
@onready var status_label = $VBoxContainer/LoginContainer/StatusLabel
@onready var character_info = $VBoxContainer/CharacterInfo
@onready var login_container = $VBoxContainer/LoginContainer
@onready var character_name_label = $VBoxContainer/CharacterInfo/CharacterNameLabel
@onready var balance_label = $VBoxContainer/CharacterInfo/BalanceLabel
@onready var location_label = $VBoxContainer/CharacterInfo/LocationLabel
@onready var skills_container = $VBoxContainer/CharacterInfo/SkillsContainer

var character_api: CharacterAPI
var current_character: Dictionary = {}


func _ready():
	print("CharacterPanel _ready() called")

	# Verify all nodes exist
	if not login_button:
		print("ERROR: login_button not found")
		return
	if not status_label:
		print("ERROR: status_label not found")
		return

	print("CharacterPanel nodes found successfully")

	login_button.pressed.connect(_on_login_pressed)
	logout_button.pressed.connect(_on_logout_pressed)

	character_api = CharacterAPI.new()
	add_child(character_api)
	character_api.login_success.connect(_on_login_success)
	character_api.login_failed.connect(_on_login_failed)
	character_api.character_data_updated.connect(_on_character_data_updated)

	print("CharacterPanel setup complete")

	# Try auto-login first
	_try_auto_login()


func _try_auto_login():
	status_label.text = "Checking for saved login..."
	login_button.disabled = true

	if character_api.try_auto_login():
		print("Auto-login successful")
	else:
		print("Auto-login failed, manual login required")
		status_label.text = "Click Login to authenticate with EVE"
		login_button.disabled = false


func _on_login_pressed():
	print("Login button pressed!")
	status_label.text = "Initiating EVE SSO login..."
	login_button.disabled = true
	character_api.start_login()


func _on_logout_pressed():
	print("Logout button pressed!")
	current_character.clear()
	character_api.logout()
	_show_login_ui()
	character_logout.emit()


func _on_login_success(character_data: Dictionary):
	print("Login success received: ", character_data)
	current_character = character_data
	_show_character_ui()
	status_label.text = "Login successful (saved for next time)"
	login_button.disabled = false
	character_login_success.emit(character_data)


func _on_login_failed(error: String):
	print("Login failed: ", error)
	status_label.text = "Login failed: " + error
	login_button.disabled = false


func _on_character_data_updated(data: Dictionary):
	print("Character data updated: ", data)
	_update_character_display(data)


func _show_login_ui():
	login_container.visible = true
	character_info.visible = false
	status_label.text = "Click Login to authenticate with EVE"


func _show_character_ui():
	login_container.visible = false
	character_info.visible = true
	_update_character_display(current_character)


func _update_character_display(data: Dictionary):
	if data.has("name"):
		character_name_label.text = "Character: " + data.name
	if data.has("balance"):
		balance_label.text = "Balance: " + _format_isk(data.balance)
	if data.has("location"):
		location_label.text = "Location: " + data.location
	if data.has("skills"):
		_update_skills_display(data.skills)


func _format_isk(amount: float) -> String:
	if amount >= 1000000000:
		return "%.2f B ISK" % (amount / 1000000000.0)
	elif amount >= 1000000:
		return "%.2f M ISK" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.2f K ISK" % (amount / 1000.0)
	else:
		return "%.2f ISK" % amount


func _update_skills_display(skills: Dictionary):
	# Clear existing skill labels except the header
	for child in skills_container.get_children():
		if child != skills_container.get_child(0):  # Keep the "Trading Skills:" label
			child.queue_free()

	var trading_skills = {"Broker Relations": "broker_relations", "Accounting": "accounting", "Trade": "trade", "Retail": "retail", "Wholesale": "wholesale", "Tycoon": "tycoon"}

	for skill_name in trading_skills.keys():
		var skill_key = trading_skills[skill_name]
		if skills.has(skill_key):
			var skill_label = Label.new()
			skill_label.text = "%s: Level %d" % [skill_name, skills[skill_key]]
			skills_container.add_child(skill_label)


func get_current_character() -> Dictionary:
	return current_character


func is_logged_in() -> bool:
	return not current_character.is_empty()
