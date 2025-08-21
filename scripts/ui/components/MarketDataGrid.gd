# scripts/ui/components/MarketDataGrid.gd
class_name MarketDataGrid
extends Control

signal item_selected(item_id: int, item_data: Dictionary)
signal progress_updated(named_items: int, total_items: int, total_available: int)

var data_manager: DataManager

var grid_data: Array = []
var unique_item_ids: Array = []
var sort_column: String = ""
var sort_ascending: bool = true

var scroll_container: ScrollContainer
var data_container: VBoxContainer
var header_row: HBoxContainer

var pending_name_updates = false
var name_update_timer: Timer
var loading_label: Label

var current_region_id: int = 0
var current_region_name: String = "Unknown Region"


func _ready():
	setup_grid()
	setup_name_update_timer()

	resized.connect(_on_grid_resized)

	# Create loading indicator
	loading_label = Label.new()
	loading_label.text = "Loading market data..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_color_override("font_color", Color.CYAN)

	# Initially show loading state
	show_loading_state()


func show_loading_state():
	# Clear existing content
	for child in data_container.get_children():
		child.queue_free()

	# Show loading message
	data_container.add_child(loading_label)


func setup_grid():
	# Set up the main layout with proper clipping
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.clip_contents = true  # Enable clipping
	add_child(main_vbox)

	# Create header
	create_header(main_vbox)

	# Create scrollable data area
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.clip_contents = true  # Enable clipping
	main_vbox.add_child(scroll_container)

	data_container = VBoxContainer.new()
	data_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_container.clip_contents = true  # Enable clipping
	scroll_container.add_child(data_container)

	print("MarketDataGrid setup complete with responsive layout")


func create_header(parent: VBoxContainer):
	header_row = HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.clip_contents = true  # Add clipping to header
	parent.add_child(header_row)

	var headers = [
		{"text": "Item Name", "width": 200, "min_width": 150},
		{"text": "Buy Price", "width": 100, "min_width": 80},
		{"text": "Sell Price", "width": 100, "min_width": 80},
		{"text": "Spread", "width": 80, "min_width": 70},
		{"text": "Margin %", "width": 80, "min_width": 70},
		{"text": "Volume", "width": 80, "min_width": 70}
	]

	for i in range(headers.size()):
		var header = headers[i]
		var label = Label.new()
		label.text = header.text
		label.custom_minimum_size.x = header.width
		label.add_theme_color_override("font_color", Color.CYAN)
		label.clip_contents = true  # Clip individual labels
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header_row.add_child(label)


func setup_name_update_timer():
	name_update_timer = Timer.new()
	name_update_timer.wait_time = 2.0  # Update UI every 2 seconds
	name_update_timer.timeout.connect(_process_pending_name_updates)
	add_child(name_update_timer)
	name_update_timer.start()


func update_market_data(data_dict: Dictionary):
	print("MarketDataGrid: Updating with data...")

	grid_data = []

	# Extract the actual market orders array
	var market_orders = data_dict.get("data", [])

	if typeof(market_orders) != TYPE_ARRAY:
		print("Warning: Expected market orders to be an array, got: ", typeof(market_orders))
		return

	print("Processing ", market_orders.size(), " market orders")

	# Group orders by item_id
	var items_data = {}
	var unique_item_ids = []

	for order in market_orders:
		if typeof(order) != TYPE_DICTIONARY:
			continue

		# Safe type conversion
		var item_id = 0
		var type_id_raw = order.get("type_id", 0)
		if typeof(type_id_raw) == TYPE_INT:
			item_id = type_id_raw
		elif typeof(type_id_raw) == TYPE_FLOAT:
			item_id = int(type_id_raw)
		else:
			continue  # Skip invalid orders

		var price = 0.0
		var price_raw = order.get("price", 0.0)
		if typeof(price_raw) == TYPE_FLOAT:
			price = price_raw
		elif typeof(price_raw) == TYPE_INT:
			price = float(price_raw)

		var volume = 0
		var volume_raw = order.get("volume_remain", 0)
		if typeof(volume_raw) == TYPE_INT:
			volume = volume_raw
		elif typeof(volume_raw) == TYPE_FLOAT:
			volume = int(volume_raw)

		var is_buy = bool(order.get("is_buy_order", false))

		# Track unique item IDs for name lookup
		var found = false
		for existing_id in unique_item_ids:
			if existing_id == item_id:
				found = true
				break
		if not found:
			unique_item_ids.append(item_id)

		if not items_data.has(item_id):
			# Get the item name from data manager if available
			var item_name = "Item %d" % item_id
			if data_manager:
				item_name = data_manager.get_item_name(item_id)

			items_data[item_id] = {
				"item_id": item_id,
				"item_name": item_name,
				"buy_orders": [],
				"sell_orders": [],
				"total_buy_volume": 0,
				"total_sell_volume": 0,
				"max_buy": 0.0,
				"min_sell": 999999999.0,
				"spread": 0.0,
				"margin": 0.0,
				"volume": 0,
				"has_buy": false,
				"has_sell": false
			}

		var item = items_data[item_id]

		if is_buy:
			item.buy_orders.append({"price": price, "volume": volume})
			item.total_buy_volume += volume
			item.has_buy = true
			if price > item.max_buy:
				item.max_buy = price
		else:
			item.sell_orders.append({"price": price, "volume": volume})
			item.total_sell_volume += volume
			item.has_sell = true
			if price < item.min_sell:
				item.min_sell = price

	print("Found ", items_data.size(), " unique items")

	# Request item names in batch instead of individually
	if data_manager and unique_item_ids.size() > 0:
		print("Requesting batch names for ", unique_item_ids.size(), " items")
		data_manager.request_item_names_batch(unique_item_ids)

	# Process all items
	for item_id in items_data:
		var item = items_data[item_id]

		# Calculate total volume
		item.volume = item.total_buy_volume + item.total_sell_volume

		# Calculate spread and margin only if we have both buy and sell
		if item.has_buy and item.has_sell and item.max_buy > 0 and item.min_sell < 999999999.0:
			item.spread = item.min_sell - item.max_buy
			item.margin = (item.spread / item.max_buy) * 100.0 if item.max_buy > 0 else 0.0
		else:
			if not item.has_sell:
				item.min_sell = 0.0
			if not item.has_buy:
				item.max_buy = 0.0
			item.spread = 0.0
			item.margin = 0.0

		# Add ALL items with any orders
		if item.volume > 0:
			grid_data.append(item)

	print("Added ", grid_data.size(), " items to display")

	# Sort by volume (most active first)
	grid_data.sort_custom(func(a, b): return a.volume > b.volume)

	if loading_label and loading_label.get_parent():
		loading_label.queue_free()

	refresh_display()


func update_item_name(type_id: int, new_name: String):
	var updated = false

	# Update the item in grid_data
	for item in grid_data:
		if item.get("item_id") == type_id:
			item.item_name = new_name
			updated = true

	# Refresh display if we updated anything
	if updated:
		refresh_display()


func _process_pending_name_updates():
	if pending_name_updates:
		refresh_display()
		pending_name_updates = false


func _on_grid_resized():
	# Adjust column widths based on available space
	adjust_column_widths()
	queue_redraw()


func adjust_column_widths():
	if not header_row:
		return

	var available_width = size.x
	var min_total_width = 640  # Minimum width for all columns

	# Define responsive column widths
	var column_configs = [
		{"name": "Item Name", "min_width": 150, "flex": 3},
		{"name": "Buy Price", "min_width": 80, "flex": 1},
		{"name": "Sell Price", "min_width": 80, "flex": 1},
		{"name": "Spread", "min_width": 70, "flex": 1},
		{"name": "Volume", "min_width": 70, "flex": 1},
		{"name": "Margin %", "min_width": 70, "flex": 1}
	]

	if available_width < min_total_width:
		# Use minimum widths when space is constrained
		for i in range(header_row.get_child_count()):
			if i < column_configs.size():
				var child = header_row.get_child(i)
				child.custom_minimum_size.x = column_configs[i].min_width
	else:
		# Use flexible widths when space is available
		var total_flex = 0
		for config in column_configs:
			total_flex += config.flex

		var remaining_width = available_width
		for i in range(header_row.get_child_count()):
			if i < column_configs.size():
				var child = header_row.get_child(i)
				var config = column_configs[i]
				var flex_width = (remaining_width * config.flex) / total_flex
				child.custom_minimum_size.x = max(config.min_width, flex_width)


func refresh_display():
	print("MarketDataGrid: Refreshing display with ", grid_data.size(), " items...")

	# Clear existing rows
	for child in data_container.get_children():
		child.queue_free()

	if grid_data.size() == 0:
		var no_data_label = Label.new()
		no_data_label.text = "No market data available. Click Refresh to load data."
		no_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data_label.add_theme_color_override("font_color", Color.YELLOW)
		data_container.add_child(no_data_label)

		print("=== EMITTING PROGRESS SIGNAL (NO DATA) ===")
		emit_signal("progress_updated", 0, 0, 0)
		return

	# Show more items to get past 70%
	var items_to_show = min(grid_data.size(), 25)  # Increased from 10 to 25
	print("Showing ", items_to_show, " items (total available: ", grid_data.size(), ")")

	# Count items with real names vs placeholders
	var named_items = 0
	for i in range(items_to_show):
		var item = grid_data[i]
		var item_name = item.get("item_name", "")
		if not item_name.begins_with("Item ") and item_name != "":
			named_items += 1

	print("=== EMITTING PROGRESS SIGNAL ===")
	print("  named_items: ", named_items)
	print("  items_to_show: ", items_to_show)
	print("  total_available: ", grid_data.size())

	# Emit progress signal - this should reach 100% when all names are loaded
	emit_signal("progress_updated", named_items, items_to_show, grid_data.size())

	# Add data rows
	for i in range(items_to_show):
		create_item_row(grid_data[i])

	print("Display updated with ", items_to_show, " items (", named_items, " named)")


func create_item_row(item: Dictionary):
	# Create the clickable button background
	var row_button = Button.new()
	row_button.flat = true
	row_button.text = ""  # Empty text
	row_button.custom_minimum_size.y = 30
	row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Connect the click event
	row_button.pressed.connect(func(): _on_item_selected(item))

	# Create container for labels
	var row_container = HBoxContainer.new()
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.custom_minimum_size.y = 30

	# KEY FIX: Make labels ignore mouse input
	row_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create individual labels
	var name_label = Label.new()
	name_label.text = item.get("item_name", "Unknown")
	name_label.custom_minimum_size.x = 200
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	row_container.add_child(name_label)

	var buy_label = Label.new()
	buy_label.text = format_isk(item.get("max_buy", 0)) if item.get("has_buy", false) else "No buy orders"
	buy_label.custom_minimum_size.x = 100
	buy_label.add_theme_color_override("font_color", Color.LIGHT_GREEN if item.get("has_buy", false) else Color.GRAY)
	buy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	row_container.add_child(buy_label)

	var sell_label = Label.new()
	sell_label.text = format_isk(item.get("min_sell", 0)) if item.get("has_sell", false) else "No sell orders"
	sell_label.custom_minimum_size.x = 100
	sell_label.add_theme_color_override("font_color", Color.LIGHT_CORAL if item.get("has_sell", false) else Color.GRAY)
	sell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	row_container.add_child(sell_label)

	var spread_label = Label.new()
	spread_label.text = format_isk(item.get("spread", 0)) if item.get("has_buy", false) and item.get("has_sell", false) else "N/A"
	spread_label.custom_minimum_size.x = 80
	spread_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	row_container.add_child(spread_label)

	var margin_label = Label.new()
	var margin = item.get("margin", 0)
	margin_label.text = "%.1f%%" % margin if item.get("has_buy", false) and item.get("has_sell", false) else "N/A"
	margin_label.custom_minimum_size.x = 80
	margin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	if margin > 10:
		margin_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	elif margin > 5:
		margin_label.add_theme_color_override("font_color", Color.YELLOW)
	elif margin > 0:
		margin_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		margin_label.add_theme_color_override("font_color", Color.LIGHT_CORAL)
	row_container.add_child(margin_label)

	var volume_label = Label.new()
	volume_label.text = format_number(item.get("volume", 0))
	volume_label.custom_minimum_size.x = 80
	volume_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	volume_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY FIX
	row_container.add_child(volume_label)

	# Create a container that stacks the button and labels
	var final_container = Control.new()
	final_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	final_container.custom_minimum_size.y = 30

	# Add button first (background)
	final_container.add_child(row_button)
	row_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Add labels on top
	final_container.add_child(row_container)
	row_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Add hover effect to the button
	row_button.mouse_entered.connect(func(): final_container.modulate = Color(1.2, 1.2, 1.2, 1.0))  # Brighten on hover
	row_button.mouse_exited.connect(func(): final_container.modulate = Color.WHITE)  # Normal color

	data_container.add_child(final_container)


func _on_item_selected(item: Dictionary):
	var item_id = item.get("item_id", 0)
	var item_name = item.get("item_name", "Unknown")

	print("MarketGrid: Item selected - ", item_name, " (ID: ", item_id, ")")
	print("Item data keys: ", item.keys())

	# Add region information to the item data
	var enhanced_item_data = item.duplicate()
	enhanced_item_data["region_id"] = current_region_id
	enhanced_item_data["region_name"] = current_region_name

	# Emit the selection signal with the COMPLETE item data
	emit_signal("item_selected", item_id, enhanced_item_data)


func format_isk(value: float) -> String:
	if value >= 1000000000:
		return "%.2fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.2fK" % (value / 1000.0)
	return "%.2f" % value


func format_number(value: float) -> String:
	if value >= 1000000:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.2fK" % (value / 1000.0)
	return "%.2f" % value


func refresh_all_item_names():
	if data_manager:
		for item in grid_data:
			var type_id = item.get("item_id", 0)
			var new_name = data_manager.get_item_name(type_id)
			if new_name != item.get("item_name", "") and not new_name.begins_with("Item "):
				item.item_name = new_name

		# Don't refresh immediately - batch the updates
		pending_name_updates = true


func set_region_info(region_id: int, region_name: String):
	current_region_id = region_id
	current_region_name = region_name
	print("MarketDataGrid: Set region to ", region_name, " (", region_id, ")")


func get_current_region_name() -> String:
	# You'll need to pass this from Main or store it
	return "Current Region"  # Placeholder for now


func get_item_data(item_id: int) -> Dictionary:
	# Find the item data in our existing grid_data
	for item in grid_data:
		if item.get("item_id", 0) == item_id:
			print("MarketDataGrid: Found existing data for item ", item_id)
			return item.duplicate()  # Return a copy to avoid reference issues

	print("MarketDataGrid: No existing data found for item ", item_id)
	return {}


func get_trading_hub_info(region_name: String) -> String:
	match region_name:
		"The Forge (Jita)":
			return " - Caldari Trade Hub"
		"Domain (Amarr)":
			return " - Amarr Trade Hub"
		"Sinq Laison (Dodixie)":
			return " - Gallente Trade Hub"
		"Metropolis (Rens)":
			return " - Minmatar Trade Hub"
		"Heimatar (Hek)":
			return " - Secondary Minmatar Hub"
		_:
			return ""
