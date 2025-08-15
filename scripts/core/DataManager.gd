# DataManager.gd
class_name DataManager
extends Node

signal data_updated(data_type: String, data: Dictionary)
signal api_error(error_message: String)

# ESI Base URL
const ESI_BASE_URL = "https://esi.evetech.net/latest"
const USER_AGENT = "EVE-Trader-Godot/1.0"

# Rate limiting
var request_queue: Array[Dictionary] = []
var requests_this_second: int = 0
var max_requests_per_second: int = 80  # Stay under 100 limit
var last_request_time: float = 0.0

# HTTP clients
var http_request: HTTPRequest
var cache_timer: Timer

# Data cache
var market_data_cache: Dictionary = {}
var item_cache: Dictionary = {}
var region_cache: Dictionary = {}
var cache_duration: float = 60.0  # Cache for 60 seconds

# Major trade hub region IDs
var major_regions: Dictionary = {"The Forge": 10000002, "Domain": 10000043, "Sinq Laison": 10000032, "Metropolis": 10000042, "Heimatar": 10000030}  # Jita  # Amarr  # Dodixie  # Rens  # Hek


func _ready():
	setup_http_client()
	setup_cache_timer()

	# Load item database on startup
	load_item_database()


func setup_http_client():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	# Configure headers
	var headers = PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"])


func setup_cache_timer():
	cache_timer = Timer.new()
	add_child(cache_timer)
	cache_timer.wait_time = 1.0
	cache_timer.timeout.connect(_process_request_queue)
	cache_timer.start()


# Main API Methods


func get_market_orders(region_id: int, type_id: int = -1) -> void:
	var cache_key = "orders_%d_%d" % [region_id, type_id]

	if is_cached(cache_key):
		var cached_data = get_cached_data(cache_key)
		emit_signal("data_updated", "market_orders", cached_data)
		return

	var url = ESI_BASE_URL + "/markets/%d/orders/" % region_id
	if type_id != -1:
		url += "?type_id=%d" % type_id

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": cache_key, "data_type": "market_orders"})


func get_market_history(region_id: int, type_id: int) -> void:
	var cache_key = "history_%d_%d" % [region_id, type_id]

	if is_cached(cache_key):
		var cached_data = get_cached_data(cache_key)
		emit_signal("data_updated", "market_history", cached_data)
		return

	var url = ESI_BASE_URL + "/markets/%d/history/?type_id=%d" % [region_id, type_id]

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": cache_key, "data_type": "market_history"})


func get_item_info(type_id: int) -> void:
	var cache_key = "item_%d" % type_id

	if is_cached(cache_key):
		var cached_data = get_cached_data(cache_key)
		emit_signal("data_updated", "item_info", cached_data)
		return

	var url = ESI_BASE_URL + "/universe/types/%d/" % type_id

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": cache_key, "data_type": "item_info"})


func search_items(search_term: String) -> void:
	var url = ESI_BASE_URL + "/search/?categories=inventory_type&search=%s&strict=false" % search_term.uri_encode()

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": "search_" + search_term, "data_type": "item_search"})


func get_region_info(region_id: int) -> void:
	var cache_key = "region_%d" % region_id

	if is_cached(cache_key):
		var cached_data = get_cached_data(cache_key)
		emit_signal("data_updated", "region_info", cached_data)
		return

	var url = ESI_BASE_URL + "/universe/regions/%d/" % region_id

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": cache_key, "data_type": "region_info"})


# Request Queue Management


func queue_request(request_data: Dictionary) -> void:
	request_queue.append(request_data)


func _process_request_queue() -> void:
	# Reset request counter every second
	requests_this_second = 0

	# Process queued requests
	while requests_this_second < max_requests_per_second and request_queue.size() > 0:
		var request_data = request_queue.pop_front()
		_execute_request(request_data)
		requests_this_second += 1


func _execute_request(request_data: Dictionary) -> void:
	var headers = PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"])

	# Store request context for callback
	http_request.set_meta("request_context", request_data)

	var error = http_request.request(request_data.url, headers, request_data.method)

	if error != OK:
		emit_signal("api_error", "Failed to make request: " + str(error))


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var context = http_request.get_meta("request_context", {})

	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())

		if parse_result == OK:
			var data = json.data

			# Cache the data
			if context.has("cache_key"):
				cache_data(context.cache_key, data)

			# Emit the appropriate signal
			emit_signal("data_updated", context.get("data_type", "unknown"), {"data": data, "context": context})
		else:
			emit_signal("api_error", "Failed to parse JSON response")
	else:
		var error_msg = "API request failed with code: %d" % response_code
		if response_code == 429:
			error_msg += " (Rate limited - requests queued)"
		emit_signal("api_error", error_msg)


# Cache Management


func is_cached(key: String) -> bool:
	if not market_data_cache.has(key):
		return false

	var cache_entry = market_data_cache[key]
	var current_time = Time.get_ticks_msec() / 1000.0

	return (current_time - cache_entry.timestamp) < cache_duration


func cache_data(key: String, data) -> void:
	market_data_cache[key] = {"data": data, "timestamp": Time.get_ticks_msec() / 1000.0}


func get_cached_data(key: String):
	if is_cached(key):
		return market_data_cache[key].data
	return null


func clear_cache() -> void:
	market_data_cache.clear()


# Item Database Loading (for autocomplete and item info)


func load_item_database() -> void:
	# This would load a local database of EVE items
	# You can download the Static Data Export (SDE) from CCP
	# For now, we'll use the API search for items
	pass


# Utility Methods


func get_major_trade_hubs() -> Dictionary:
	return major_regions


func format_isk(value: float) -> String:
	if value >= 1000000000:
		return "%.2fB ISK" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.2fM ISK" % (value / 1000000.0)
	if value >= 1000:
		return "%.2fK ISK" % (value / 1000.0)

	return "%.2f ISK" % value


func calculate_profit_margin(buy_price: float, sell_price: float, volume: int = 1) -> Dictionary:
	var total_buy = buy_price * volume
	var total_sell = sell_price * volume
	var profit = total_sell - total_buy
	var margin_percent = (profit / total_buy) * 100.0 if total_buy > 0 else 0.0

	return {"profit": profit, "margin_percent": margin_percent, "roi": margin_percent, "volume": volume}
