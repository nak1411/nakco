# DataManager.gd
class_name DataManager
extends Node

signal data_updated(data_type: String, data: Dictionary)
signal api_error(error_message: String)

# ESI Base URL
const ESI_BASE_URL = "https://esi.evetech.net/latest"
const USER_AGENT = "EVE-Trader-Godot/1.0"

const COMMON_ITEMS = {
	34: "Tritanium",
	35: "Pyerite",
	36: "Mexallon",
	37: "Isogen",
	38: "Nocxium",
	39: "Zydrine",
	40: "Megacyte",
	11399: "Morphite",
	16275: "Oxygen",
	9848: "Nitrogen",
	9832: "Hydrogen",
}

var major_regions: Dictionary = {"The Forge (Jita)": 10000002, "Domain (Amarr)": 10000043, "Sinq Laison (Dodixie)": 10000032, "Metropolis (Rens)": 10000042, "Heimatar (Hek)": 10000030}

# Rate limiting
var request_queue: Array[Dictionary] = []
var requests_this_second: int = 0
var max_requests_per_second: int = 80  # Stay under 100 limit
var last_request_time: float = 0.0

# HTTP clients
var http_request: HTTPRequest
var cache_timer: Timer

var active_http_requests: Array = []
var max_concurrent_requests: int = 5
var item_request_queue: Array = []

# Data cache
var market_data_cache: Dictionary = {}
var item_cache: Dictionary = {}
var region_cache: Dictionary = {}
var cache_duration: float = 60.0  # Cache for 60 seconds

var item_names_cache: Dictionary = {}
var pending_item_lookups: Array = []
var item_lookup_timer: Timer

var debug_items_data: Dictionary = {}
var debug_items_pending: Array = []
var debug_region_id: int = 0
var is_collecting_debug_data: bool = false


func _ready():
	setup_http_client()
	setup_cache_timer()
	setup_item_lookup_timer()
	# Load item database on startup
	load_item_database()


func setup_http_client():
	# Create multiple HTTP clients for concurrent requests
	for i in range(max_concurrent_requests):
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_request_completed.bind(i))
		active_http_requests.append({"client": http_request, "busy": false, "context": {}})

	print("Created ", max_concurrent_requests, " HTTP clients")


func setup_cache_timer():
	cache_timer = Timer.new()
	add_child(cache_timer)
	cache_timer.wait_time = 1.0
	cache_timer.timeout.connect(_process_request_queue)
	cache_timer.start()


func setup_item_lookup_timer():
	item_lookup_timer = Timer.new()
	add_child(item_lookup_timer)
	item_lookup_timer.wait_time = 0.2  # Faster - 5 requests per second
	item_lookup_timer.timeout.connect(_process_item_lookups)
	item_lookup_timer.start()


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

	var request_context = {
		"url": url,
		"method": HTTPClient.METHOD_GET,
		"cache_key": cache_key,
		"data_type": "market_orders",
		"region_id": region_id,
		"type_id": type_id,
		"region_name": get_region_name_by_id(region_id),
		"is_individual_item": type_id != -1  # Flag to identify individual item requests
	}

	queue_request(request_context)


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


func get_region_name_by_id(region_id: int) -> String:
	for region_name in major_regions.keys():
		if major_regions[region_name] == region_id:
			return region_name
	return "Region %d" % region_id


# Request Queue Management


func queue_request(request_data: Dictionary) -> void:
	request_queue.append(request_data)


func _process_request_queue() -> void:
	# Reset request counter every second
	requests_this_second = 0

	# Process queued requests for market data (high priority)
	while requests_this_second < max_requests_per_second and request_queue.size() > 0:
		var request_data = request_queue.pop_front()
		_execute_request(request_data)
		requests_this_second += 1


func _execute_request(request_data: Dictionary) -> void:
	var available_client = null
	var client_index = -1

	for i in range(active_http_requests.size()):
		if not active_http_requests[i].busy:
			available_client = active_http_requests[i]
			client_index = i
			break

	if available_client == null:
		item_request_queue.append(request_data)
		return

	available_client.busy = true
	available_client.context = request_data

	var headers = request_data.get("headers", PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"]))
	var body = request_data.get("body", "")

	var error = available_client.client.request(request_data.url, headers, request_data.method, body)

	if error != OK:
		available_client.busy = false
		available_client.context = {}
		emit_signal("api_error", "Failed to make request: " + str(error))


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, client_index: int) -> void:
	var client_info = active_http_requests[client_index]
	var context = client_info.context

	# Free up the client
	client_info.busy = false
	client_info.context = {}

	# Process next queued request if any
	if item_request_queue.size() > 0:
		var next_request = item_request_queue.pop_front()
		_execute_request(next_request)

	# Handle the response
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())

		if parse_result == OK:
			var raw_data = json.data

			# Handle batch item name responses
			if context.get("data_type") == "batch_item_names":
				var type_ids = context.get("type_ids", [])

				if typeof(raw_data) == TYPE_ARRAY:
					for item_data in raw_data:
						if typeof(item_data) == TYPE_DICTIONARY:
							var type_id = item_data.get("id", 0)
							var item_name = item_data.get("name", "Item %d" % type_id)
							item_names_cache[type_id] = item_name

				# Emit signal to update all displays
				emit_signal("data_updated", "batch_item_names_updated", {"updated_count": raw_data.size() if typeof(raw_data) == TYPE_ARRAY else 0})
				return

			# Handle debug market orders (individual items)
			if context.get("data_type") == "debug_market_orders":
				var item_id = context.get("type_id", 0)
				var structured_data = {"data": raw_data, "context": context, "timestamp": Time.get_ticks_msec()}

				# Cache the data
				if context.has("cache_key"):
					cache_data(context.cache_key, structured_data)

				# Process this debug item
				_process_debug_item_response(structured_data, item_id)
				return

			# Handle single item name responses
			if context.get("data_type") == "item_name":
				var type_id = context.get("type_id", 0)
				var item_name = raw_data.get("name", "Item %d" % type_id)
				item_names_cache[type_id] = item_name

				# Cache the full item data too
				if context.has("cache_key"):
					cache_data(context.cache_key, raw_data)

				# Emit signal to update displays
				emit_signal("data_updated", "item_name_updated", {"type_id": type_id, "name": item_name, "data": raw_data})
				return

			# Handle other data types (market orders, history, etc.)
			var structured_data = {"data": raw_data, "context": context, "timestamp": Time.get_ticks_msec(), "region_id": context.get("region_id", 0), "type_id": context.get("type_id", -1)}

			if context.has("cache_key"):
				cache_data(context.cache_key, structured_data)

			emit_signal("data_updated", context.get("data_type", "unknown"), structured_data)
		else:
			emit_signal("api_error", "Failed to parse JSON response")
	else:
		var error_msg = "API request failed with code: %d" % response_code
		if response_code == 429:
			error_msg += " (Rate limited - requests queued)"
		elif response_code == 404 and context.get("data_type") == "item_name":
			# Handle item not found
			var type_id = context.get("type_id", 0)
			item_names_cache[type_id] = "Unknown Item %d" % type_id
			return
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


func get_item_name(type_id: int) -> String:
	# Check static cache first
	if COMMON_ITEMS.has(type_id):
		return COMMON_ITEMS[type_id]

	# Check dynamic cache
	if item_names_cache.has(type_id):
		return item_names_cache[type_id]

	# Queue for lookup if not already pending
	if not pending_item_lookups.has(type_id):
		pending_item_lookups.append(type_id)

	return "Item %d" % type_id


func _process_item_lookups():
	var lookups_this_cycle = 0
	while pending_item_lookups.size() > 0 and lookups_this_cycle < 5:  # Up from 2
		var type_id = pending_item_lookups.pop_front()
		request_item_name(type_id)
		lookups_this_cycle += 1


func request_item_name(type_id: int):
	var cache_key = "item_name_%d" % type_id

	# Check if already cached
	if is_cached(cache_key):
		var cached_data = get_cached_data(cache_key)
		item_names_cache[type_id] = cached_data.get("name", "Item %d" % type_id)
		return

	var url = ESI_BASE_URL + "/universe/types/%d/" % type_id

	queue_request({"url": url, "method": HTTPClient.METHOD_GET, "cache_key": cache_key, "data_type": "item_name", "type_id": type_id})


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


# Batching


func request_item_names_batch(type_ids: Array):
	# EVE API supports batch requests for up to 1000 items
	var batch_size = 200  # Conservative batch size

	for i in range(0, type_ids.size(), batch_size):
		var end_index = min(i + batch_size, type_ids.size())
		var batch = type_ids.slice(i, end_index)
		request_item_names_batch_single(batch)


func request_item_names_batch_single(type_ids: Array):
	var url = ESI_BASE_URL + "/universe/names/"

	var request_data = {
		"url": url,
		"method": HTTPClient.METHOD_POST,
		"headers": PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json", "Content-Type: application/json"]),
		"body": JSON.stringify(type_ids),
		"data_type": "batch_item_names",
		"type_ids": type_ids
	}

	queue_request(request_data)


func get_debug_market_data(region_id: int) -> void:
	# Prevent multiple simultaneous collection attempts
	if is_collecting_debug_data:
		print("Debug data collection already in progress, skipping...")
		return

	print("Getting debug market data for popular items only...")

	# Set collection flag
	is_collecting_debug_data = true

	# Reset debug data collection
	debug_items_data.clear()
	debug_items_pending.clear()
	debug_region_id = region_id

	# List of popular items to fetch
	var debug_items = [34, 35, 36, 37, 38, 39, 40, 11399, 16275, 9848]  # 10 items
	debug_items_pending = debug_items.duplicate()

	print("Fetching ", debug_items.size(), " debug items...")

	for item_id in debug_items:
		var cache_key = "orders_%d_%d" % [region_id, item_id]

		var url = ESI_BASE_URL + "/markets/%d/orders/?type_id=%d" % [region_id, item_id]

		var request_context = {
			"url": url,
			"method": HTTPClient.METHOD_GET,
			"cache_key": cache_key,
			"data_type": "debug_market_orders",  # Keep the debug data type
			"region_id": region_id,
			"type_id": item_id,
			"region_name": get_region_name_by_id(region_id),
			"debug_collection_id": Time.get_ticks_msec()  # Add unique collection ID
		}

		queue_request(request_context)

		# Add small delay between requests
		await get_tree().create_timer(0.05).timeout


func _process_debug_item_response(response_data: Dictionary, item_id: int):
	if not is_collecting_debug_data:
		print("Received debug response but not collecting, ignoring...")
		return

	# Store this item's data
	var orders = response_data.get("data", [])
	debug_items_data[item_id] = orders

	# Remove from pending list
	debug_items_pending.erase(item_id)

	print("Collected data for item ", item_id, " (", orders.size(), " orders). Pending: ", debug_items_pending.size())

	# If all items are collected, combine and emit
	if debug_items_pending.is_empty():
		_emit_combined_debug_data()


func _emit_combined_debug_data():
	print("Combining debug market data from ", debug_items_data.size(), " items...")

	# Combine all orders into one array
	var combined_orders = []

	for item_id in debug_items_data:
		var item_orders = debug_items_data[item_id]
		for order in item_orders:
			combined_orders.append(order)

	print("Combined ", combined_orders.size(), " total orders")

	# Create combined market data structure
	var combined_data = {
		"data": combined_orders,
		"context": {"region_id": debug_region_id, "region_name": get_region_name_by_id(debug_region_id), "debug_mode": true, "items_fetched": debug_items_data.keys(), "combined_response": true},  # Flag to identify this as combined data
		"timestamp": Time.get_ticks_msec()
	}

	# Reset collection flag
	is_collecting_debug_data = false

	# Emit the combined data
	emit_signal("data_updated", "market_orders", combined_data)

	print("Emitted combined debug market data - collection complete")
