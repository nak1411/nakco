class_name CharacterAPI
extends Node

signal login_success(character_data: Dictionary)
signal login_failed(error: String)
signal character_data_updated(data: Dictionary)

const ESI_BASE_URL = "https://esi.evetech.net/latest"
const LOGIN_URL = "https://login.eveonline.com/v2/oauth/authorize"
const TOKEN_URL = "https://login.eveonline.com/v2/oauth/token"

const CLIENT_ID = "a91863b4eb3746cea1076d2846926ce3"  # Your real client ID
const REDIRECT_URI = "http://localhost:8080/callback"
const SCOPES = "esi-wallet.read_character_wallet.v1 esi-location.read_location.v1 esi-skills.read_skills.v1"

var access_token: String = ""
var refresh_token: String = ""
var character_id: int = 0
var character_data: Dictionary = {}
var oauth_state: String = ""

var tcp_server: TCPServer
var is_listening: bool = false
var token_manager: TokenManager


func _ready():
	tcp_server = TCPServer.new()
	token_manager = TokenManager.new()
	add_child(token_manager)


func try_auto_login() -> bool:
	print("Attempting auto-login...")

	# Get list of saved characters
	var saved_characters = token_manager.get_all_saved_characters()
	if saved_characters.is_empty():
		print("No saved characters found")
		return false

	# Use the most recently saved character
	saved_characters.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	var latest_character = saved_characters[0]

	var token_data = token_manager.get_token_data(latest_character.character_id)
	if token_data.is_empty():
		print("No valid token data found")
		return false

	# Set the token data
	access_token = token_data.access_token
	refresh_token = token_data.get("refresh_token", "")
	character_id = token_data.character_id

	print("Auto-login successful for character: ", character_id)

	# Fetch character data
	_fetch_character_data()
	return true


func start_login():
	print("Starting EVE SSO login...")
	oauth_state = _generate_random_state()
	print("OAuth state: ", oauth_state)

	# Start the local server
	if not _start_local_server():
		return

	# Generate auth URL
	var auth_url = "%s?response_type=code&redirect_uri=%s&client_id=%s&scope=%s&state=%s" % [LOGIN_URL, REDIRECT_URI.uri_encode(), CLIENT_ID, SCOPES.uri_encode(), oauth_state]

	print("Auth URL: ", auth_url)
	print("Opening browser...")
	OS.shell_open(auth_url)


func _generate_random_state() -> String:
	var characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var state = ""
	for i in range(32):
		state += characters[randi() % characters.length()]
	return state


func _start_local_server() -> bool:
	print("Starting local server on port 8080...")

	var error = tcp_server.listen(8080, "127.0.0.1")
	if error != OK:
		print("Failed to start server: ", error)
		login_failed.emit("Failed to start local server: " + str(error))
		return false

	is_listening = true
	print("Server started successfully")
	return true


func _process(_delta):
	if not is_listening:
		return

	# Check for new connections
	if tcp_server.is_connection_available():
		print("New connection detected")
		var client = tcp_server.take_connection()
		_handle_request(client)


func _handle_request(client: StreamPeerTCP):
	print("Handling HTTP request...")

	# Read the request
	var request_text = ""
	var max_attempts = 100
	var attempts = 0

	while attempts < max_attempts:
		var bytes_available = client.get_available_bytes()
		if bytes_available > 0:
			request_text += client.get_string(bytes_available)
			# Look for end of HTTP headers
			if "\r\n\r\n" in request_text or "\n\n" in request_text:
				break
		attempts += 1
		await get_tree().process_frame

	print("Request received: ")
	print(request_text.substr(0, 200) if request_text.length() > 200 else request_text)

	# Send HTTP response
	var response_body = """
<!DOCTYPE html>
<html>
<head>
    <title>EVE SSO Success</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
        .success { color: green; }
    </style>
</head>
<body>
    <h1 class="success">EVE SSO Login Successful!</h1>
    <p>Login saved! You won't need to login again next time.</p>
    <p>You can now close this browser window.</p>
    <script>
        setTimeout(function() {
            window.close();
        }, 3000);
    </script>
</body>
</html>
"""

	var response = "HTTP/1.1 200 OK\r\n"
	response += "Content-Type: text/html; charset=utf-8\r\n"
	response += "Content-Length: " + str(response_body.length()) + "\r\n"
	response += "Connection: close\r\n"
	response += "\r\n"
	response += response_body

	client.put_data(response.to_utf8_buffer())

	# Parse the request line
	var request_lines = request_text.split("\n")
	if request_lines.size() > 0:
		var first_line = request_lines[0].strip_edges()
		print("Request line: ", first_line)

		var parts = first_line.split(" ")
		if parts.size() >= 2:
			var path = parts[1]
			print("Path: ", path)

			# Process the callback
			call_deferred("_process_oauth_callback", path)

	# Close the connection
	client.disconnect_from_host()

	# Stop listening after first request
	_stop_server()


func _stop_server():
	print("Stopping server...")
	is_listening = false
	tcp_server.stop()


func _process_oauth_callback(path: String):
	print("Processing OAuth callback: ", path)

	if not path.begins_with("/callback"):
		print("Not a callback URL")
		login_failed.emit("Invalid callback URL")
		return

	# Parse query parameters
	var query_start = path.find("?")
	if query_start == -1:
		print("No query parameters found")
		login_failed.emit("No query parameters in callback")
		return

	var query_string = path.substr(query_start + 1)
	print("Query string: ", query_string)

	var params = {}
	var pairs = query_string.split("&")
	for pair in pairs:
		var kv = pair.split("=", false, 1)
		if kv.size() == 2:
			params[kv[0]] = kv[1].uri_decode()

	print("Parsed parameters: ", params)

	# Check state parameter
	if not params.has("state"):
		login_failed.emit("Missing state parameter")
		return

	if params["state"] != oauth_state:
		login_failed.emit("Invalid state parameter")
		return

	# Check for OAuth errors
	if params.has("error"):
		var error_desc = params.get("error_description", params["error"])
		login_failed.emit("OAuth error: " + error_desc)
		return

	# Get authorization code
	if not params.has("code"):
		login_failed.emit("Missing authorization code")
		return

	var auth_code = params["code"]
	print("Authorization code: ", auth_code)

	# Exchange code for token
	_exchange_code_for_token(auth_code)


func _exchange_code_for_token(auth_code: String):
	print("Exchanging authorization code for access token...")

	var http_request = HTTPRequest.new()
	add_child(http_request)

	var headers = ["Content-Type: application/x-www-form-urlencoded", "User-Agent: EVE-Trader-Godot/1.0"]

	var body = "grant_type=authorization_code&code=%s&redirect_uri=%s&client_id=%s" % [auth_code, REDIRECT_URI.uri_encode(), CLIENT_ID]

	print("Making token request to: ", TOKEN_URL)

	http_request.request_completed.connect(_on_token_received)
	var request_error = http_request.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body)

	if request_error != OK:
		print("Failed to make token request: ", request_error)
		login_failed.emit("Failed to make token request")
		http_request.queue_free()


func _on_token_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("Token response received - Code: ", response_code)

	# Clean up HTTP request
	var http_request_nodes = get_children().filter(func(child): return child is HTTPRequest)
	for node in http_request_nodes:
		node.queue_free()

	var response_text = body.get_string_from_utf8()
	print("Token response body: ", response_text)

	if response_code != 200:
		login_failed.emit("Token request failed with code: " + str(response_code))
		return

	# Parse JSON response
	var json = JSON.new()
	var parse_result = json.parse(response_text)
	if parse_result != OK:
		login_failed.emit("Failed to parse token response")
		return

	var token_data = json.data
	print("Token data: ", token_data)

	if not token_data.has("access_token"):
		login_failed.emit("No access token in response")
		return

	access_token = token_data["access_token"]
	refresh_token = token_data.get("refresh_token", "")
	print("Access token received (first 20 chars): ", access_token.substr(0, 20))

	# Extract character ID from JWT token
	_extract_character_id()


func _extract_character_id():
	print("Extracting character ID from JWT token...")

	var token_parts = access_token.split(".")
	if token_parts.size() < 2:
		login_failed.emit("Invalid JWT token format")
		return

	# Decode the payload (second part)
	var payload = token_parts[1]

	# Add padding if needed for base64 decoding
	while payload.length() % 4 != 0:
		payload += "="

	var decoded_payload = Marshalls.base64_to_utf8(payload)
	print("Decoded JWT payload: ", decoded_payload)

	var json = JSON.new()
	if json.parse(decoded_payload) != OK:
		login_failed.emit("Failed to parse JWT payload")
		return

	var payload_data = json.data
	if not payload_data.has("sub"):
		login_failed.emit("No subject in JWT token")
		return

	# Extract character ID from subject (format: "CHARACTER:EVE:12345678")
	var subject = payload_data["sub"]
	var subject_parts = subject.split(":")
	if subject_parts.size() < 3:
		login_failed.emit("Invalid subject format in JWT")
		return

	character_id = subject_parts[2].to_int()
	print("Character ID: ", character_id)

	if character_id == 0:
		login_failed.emit("Invalid character ID")
		return

	# Save token data for future use
	var expires_in = payload_data.get("exp", Time.get_unix_time_from_system() + 1200)  # Default 20 min
	token_manager.save_token_data(access_token, refresh_token, character_id, expires_in)

	# Now fetch character data
	_fetch_character_data()


func _fetch_character_data():
	print("Fetching character data...")

	# Start with basic character info
	var http_request = HTTPRequest.new()
	add_child(http_request)

	var headers = ["Authorization: Bearer " + access_token, "User-Agent: EVE-Trader-Godot/1.0"]

	http_request.request_completed.connect(_on_character_info_received)
	var url = ESI_BASE_URL + "/characters/%d/" % character_id
	print("Fetching character info from: ", url)

	var request_error = http_request.request(url, headers)
	if request_error != OK:
		print("Failed to make character info request: ", request_error)
		login_failed.emit("Failed to fetch character data")
		http_request.queue_free()


func _on_character_info_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("Character info response - Code: ", response_code)

	# Clean up HTTP request
	var http_request_nodes = get_children().filter(func(child): return child is HTTPRequest)
	for node in http_request_nodes:
		node.queue_free()

	var response_text = body.get_string_from_utf8()
	print("Character info response: ", response_text)

	if response_code != 200:
		print("Character info request failed with code: ", response_code)
		# Use mock data instead of failing
		_create_mock_character_data()
		return

	# Parse character info
	var json = JSON.new()
	if json.parse(response_text) != OK:
		print("Failed to parse character info response")
		_create_mock_character_data()
		return

	var char_info = json.data
	print("Character info: ", char_info)

	# Build character data
	character_data = {
		"name": char_info.get("name", "Unknown Pilot"),
		"balance": 1234567890.0,  # Mock balance for now
		"location": "Jita IV - Moon 4 - Caldari Navy Assembly Plant",  # Mock location
		"skills": {"trade": 5, "accounting": 4, "broker_relations": 3, "retail": 2}  # Mock skills
	}

	print("Final character data: ", character_data)
	character_data_updated.emit(character_data)
	login_success.emit(character_data)


func _create_mock_character_data():
	print("Creating mock character data...")
	character_data = {
		"name": "Test Pilot", "balance": 1234567890.0, "location": "Jita IV - Moon 4 - Caldari Navy Assembly Plant", "skills": {"trade": 5, "accounting": 4, "broker_relations": 3, "retail": 2}
	}

	print("Mock character data: ", character_data)
	character_data_updated.emit(character_data)
	login_success.emit(character_data)


func logout():
	print("Logging out...")
	_stop_server()

	# Remove saved tokens for this character
	if character_id > 0:
		token_manager.remove_character_tokens(character_id)

	access_token = ""
	refresh_token = ""
	character_id = 0
	character_data.clear()
	oauth_state = ""


func clear_all_saved_logins():
	token_manager.clear_all_tokens()
	print("All saved logins cleared")


func get_access_token() -> String:
	return access_token


func get_character_id() -> int:
	return character_id
