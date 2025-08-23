extends Control

signal character_login_success(character_data: Dictionary)
signal character_logout

@onready var login_button = $MainHBoxContainer/LeftPortraitSection/LoginContainer/LoginButtonContainer/LoginButton
@onready var logout_button = $MainHBoxContainer/LeftPortraitSection/LogoutContainer/LogoutButton
@onready var status_label = $MainHBoxContainer/LeftPortraitSection/LoginContainer/StatusLabel
@onready var login_container = $MainHBoxContainer/LeftPortraitSection/LoginContainer
@onready var character_portrait_section = $MainHBoxContainer/LeftPortraitSection/CharacterPortraitSection
@onready var character_details = $MainHBoxContainer/RightDetailsSection/CharacterDetails

# Updated references for new layout structure
@onready var character_name_label = $MainHBoxContainer/LeftPortraitSection/CharacterPortraitSection/CharacterNameLabel
@onready var portrait_icon = $MainHBoxContainer/LeftPortraitSection/CharacterPortraitSection/PortraitFrame/PortraitIcon
@onready var balance_label = $MainHBoxContainer/RightDetailsSection/CharacterDetails/WalletSection/WalletDetails/BalanceLabel
@onready var escrow_label = $MainHBoxContainer/RightDetailsSection/CharacterDetails/WalletSection/WalletDetails/EscrowLabel
@onready var net_worth_label = $MainHBoxContainer/RightDetailsSection/CharacterDetails/WalletSection/WalletDetails/NetWorthLabel
@onready var location_label = $MainHBoxContainer/RightDetailsSection/CharacterDetails/LocationSection/LocationDetails/LocationLabel
@onready var skills_container = $MainHBoxContainer/RightDetailsSection/CharacterDetails/TradingSkillsContainer/SkillsDetails/SkillsContainer

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
	character_portrait_section.visible = false
	character_details.visible = false
	# Hide logout container when not logged in
	logout_button.get_parent().visible = false
	status_label.text = "Click Login to authenticate with EVE"


func _show_character_ui():
	login_container.visible = false
	character_portrait_section.visible = true
	character_details.visible = true
	# Show logout container when logged in
	logout_button.get_parent().visible = true
	_update_character_display(current_character)


func _update_character_display(data: Dictionary):
	if data.has("name"):
		character_name_label.text = data.name

	if data.has("balance"):
		balance_label.text = "Balance: " + _format_isk(data.balance)
		# Calculate net worth (for now, same as balance)
		net_worth_label.text = "Net Worth: " + _format_isk(data.balance)

	# Mock escrow data for now
	escrow_label.text = "In Escrow: " + _format_isk(0)

	if data.has("location"):
		location_label.text = data.location

	if data.has("skills"):
		_update_skills_display(data.skills)

	# Load actual EVE character portrait
	_load_character_portrait()


func _load_character_portrait():
	var char_id = character_api.get_character_id()
	if char_id > 0:
		print("Loading character portrait for ID: ", char_id)

		# EVE character portrait URL - size 128 for better quality
		var portrait_url = "https://images.evetech.net/characters/%d/portrait?size=128" % char_id

		var http_request = HTTPRequest.new()
		add_child(http_request)

		http_request.request_completed.connect(_on_portrait_loaded)
		var error = http_request.request(portrait_url)

		if error != OK:
			print("Failed to start portrait request: ", error)
			_create_portrait_placeholder()
			http_request.queue_free()
	else:
		print("No character ID available for portrait")
		_create_portrait_placeholder()


func _on_portrait_loaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Clean up HTTP request
	var http_requests = get_children().filter(func(child): return child is HTTPRequest)
	for request in http_requests:
		request.queue_free()

	print("Portrait response code: ", response_code)

	if response_code == 200 and body.size() > 0:
		print("Portrait loaded successfully, size: ", body.size())

		var image = Image.new()
		var error = image.load_jpg_from_buffer(body)

		if error != OK:
			# Try PNG if JPG fails
			error = image.load_png_from_buffer(body)

		if error == OK:
			var texture = ImageTexture.new()
			texture.set_image(image)
			portrait_icon.texture = texture
			print("Character portrait set successfully")
		else:
			print("Failed to load image from buffer, error: ", error)
			_create_portrait_placeholder()
	else:
		print("Failed to load portrait, response code: ", response_code)
		_create_portrait_placeholder()


func _create_portrait_placeholder():
	# Create a more EVE-like portrait placeholder
	var image = Image.create(96, 96, false, Image.FORMAT_RGB8)

	# Fill with dark space background
	image.fill(Color(0.05, 0.05, 0.1))

	# Add some simple geometric shapes to make it look more like a character silhouette
	# Head circle
	for y in range(20, 50):
		for x in range(30, 66):
			var dx = x - 48
			var dy = y - 35
			if dx * dx + dy * dy < 18 * 18:
				image.set_pixel(x, y, Color(0.3, 0.35, 0.4))

	# Body rectangle
	for y in range(45, 85):
		for x in range(35, 61):
			image.set_pixel(x, y, Color(0.25, 0.3, 0.35))

	# Add a subtle border
	for i in range(96):
		image.set_pixel(i, 0, Color(0.4, 0.45, 0.5))
		image.set_pixel(i, 95, Color(0.4, 0.45, 0.5))
		image.set_pixel(0, i, Color(0.4, 0.45, 0.5))
		image.set_pixel(95, i, Color(0.4, 0.45, 0.5))

	var texture = ImageTexture.new()
	texture.set_image(image)
	portrait_icon.texture = texture


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
	# Clear existing skill labels
	for child in skills_container.get_children():
		child.queue_free()

	var trading_skills = {"Broker Relations": "broker_relations", "Accounting": "accounting", "Trade": "trade", "Retail": "retail", "Wholesale": "wholesale", "Tycoon": "tycoon"}

	for skill_name in trading_skills.keys():
		var skill_key = trading_skills[skill_name]
		if skills.has(skill_key):
			# Create a single HBoxContainer for each skill
			var skill_container = HBoxContainer.new()

			var skill_name_label = Label.new()
			skill_name_label.text = skill_name + ":"
			skill_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			skill_name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

			var skill_level_label = Label.new()
			skill_level_label.text = "Level " + str(skills[skill_key])
			skill_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			skill_level_label.modulate = Color(0.3, 1.0, 0.5)  # Light green for levels
			skill_level_label.custom_minimum_size.x = 80  # Fixed width for alignment

			skill_container.add_child(skill_name_label)
			skill_container.add_child(skill_level_label)
			skills_container.add_child(skill_container)


func get_current_character() -> Dictionary:
	return current_character


func is_logged_in() -> bool:
	return not current_character.is_empty()
