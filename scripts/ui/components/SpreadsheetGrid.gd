# scripts/ui/components/SpreadsheetGrid.gd
class_name SpreadsheetGrid
extends Control

signal item_selected(item_id: int, item_data: Dictionary)
signal progress_updated(named_items: int, total_items: int, total_available: int)
signal column_resized(column_index: int, new_width: float)

# Calculation mode functionality
enum CalculationMode { RAW, SKILL_ADJUSTED }
var calculation_mode = CalculationMode.RAW
var current_character_data = {}

var data_manager: DataManager
var grid_data: Array = []
var unique_item_ids: Array = []

# Visual elements
var header_container: Control
var data_container: Control
var data_scroll: ScrollContainer
var background: ColorRect

# Column system
var column_definitions = [
	{"name": "Item Name", "width": 200, "field": "item_name", "type": "text"},
	{"name": "Buy Price", "width": 100, "field": "max_buy", "type": "price"},
	{"name": "Sell Price", "width": 100, "field": "min_sell", "type": "price"},
	{"name": "Spread", "width": 80, "field": "spread", "type": "price"},
	{"name": "Volume", "width": 80, "field": "volume", "type": "number"},
	{"name": "Margin %", "width": 80, "field": "margin", "type": "percentage"}
]

# Resize handles
var resize_handles: Array = []
var column_separators: Array = []
var is_resizing: bool = false
var resize_column_index: int = -1
var resize_start_pos: Vector2

# Style constants
const header_height = 30.0
const row_height = 25.0
const cell_color = Color(0.15, 0.15, 0.2, 1)
const alternate_row_color = Color(0.12, 0.12, 0.18, 1)
const header_color = Color(0.2, 0.2, 0.3, 1)
const border_color = Color(0.4, 0.4, 0.5, 1)
const text_color = Color.WHITE
const header_text_color = Color.CYAN

# Region info
var current_region_id: int = 0
var current_region_name: String = "Unknown Region"

# Name update system
var pending_name_updates = false
var name_update_timer: Timer


func _ready():
	setup_grid_structure()
	setup_name_update_timer()

	# Connect resize signal
	resized.connect(_on_grid_resized)


func setup_grid_structure():
	# Main background
	background = ColorRect.new()
	background.color = Color(0.08, 0.08, 0.12, 1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Header container (fixed at top)
	header_container = Control.new()
	header_container.name = "HeaderContainer"
	header_container.position = Vector2.ZERO
	header_container.size = Vector2(size.x, header_height)
	header_container.anchor_right = 1.0
	add_child(header_container)

	# Data scroll container (below header)
	data_scroll = ScrollContainer.new()
	data_scroll.name = "DataScroll"
	data_scroll.position = Vector2(0, header_height)
	data_scroll.size = Vector2(size.x, size.y - header_height)
	data_scroll.anchor_right = 1.0
	data_scroll.anchor_bottom = 1.0
	data_scroll.offset_top = header_height
	data_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  # ✅ CORRECT
	data_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  # ✅ CORRECT
	add_child(data_scroll)

	# Data container (holds all data rows)
	data_container = Control.new()
	data_container.name = "DataContainer"
	data_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_scroll.add_child(data_container)

	# Create initial header and handle mouse events
	create_header_cells()
	create_resize_handles()

	print("SpreadsheetGrid structure created")


func create_header_cells():
	var x_offset = 0.0

	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]

		# Header cell background
		var header_bg = ColorRect.new()
		header_bg.color = header_color
		header_bg.position = Vector2(x_offset, 0)
		header_bg.size = Vector2(col_def.width, header_height)
		header_container.add_child(header_bg)

		# Header label
		var header_label = Label.new()
		header_label.text = col_def.name
		header_label.position = Vector2(x_offset + 5, 0)
		header_label.size = Vector2(col_def.width - 10, header_height)
		header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header_label.add_theme_color_override("font_color", header_text_color)
		header_label.clip_contents = true
		header_container.add_child(header_label)

		# Column separator line
		var separator = Line2D.new()
		separator.add_point(Vector2(x_offset + col_def.width, 0))
		separator.add_point(Vector2(x_offset + col_def.width, header_height))
		separator.default_color = border_color
		separator.width = 1
		header_container.add_child(separator)
		column_separators.append(separator)

		x_offset += col_def.width


func create_resize_handles():
	resize_handles.clear()
	var x_offset = 0.0

	for i in range(column_definitions.size() - 1):  # No handle after last column
		var col_def = column_definitions[i]
		x_offset += col_def.width

		# Invisible resize handle
		var handle = Control.new()
		handle.position = Vector2(x_offset - 3, 0)
		handle.size = Vector2(6, header_height)
		handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		header_container.add_child(handle)

		# Connect handle events
		var column_index = i
		handle.gui_input.connect(_on_resize_handle_input.bind(column_index))

		resize_handles.append(handle)


func _on_resize_handle_input(event: InputEvent, column_index: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_resizing = true
				resize_column_index = column_index
				resize_start_pos = event.global_position
			else:
				is_resizing = false
				resize_column_index = -1

	elif event is InputEventMouseMotion and is_resizing and resize_column_index == column_index:
		var delta = event.global_position.x - resize_start_pos.x
		var new_width = column_definitions[column_index].width + delta
		new_width = max(50, new_width)  # Minimum column width

		set_column_width(column_index, new_width)
		resize_start_pos = event.global_position

		emit_signal("column_resized", column_index, new_width)


func _on_grid_resized():
	if header_container:
		header_container.size.x = size.x
	if data_scroll:
		data_scroll.size = Vector2(size.x, size.y - header_height)


func refresh_data_display():
	# Clear existing data rows
	for child in data_container.get_children():
		child.queue_free()

	if grid_data.size() == 0:
		var no_data = Label.new()
		no_data.text = "No market data available. Click Refresh to load data."
		no_data.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data.add_theme_color_override("font_color", Color.YELLOW)
		no_data.position = Vector2(10, 10)
		data_container.add_child(no_data)
		return

	# Set data container size based on row count
	data_container.custom_minimum_size.y = grid_data.size() * row_height

	# Create rows (limit to 50 for performance)
	for row_index in range(min(grid_data.size(), 50)):
		create_enhanced_data_row(row_index)


func create_enhanced_data_row(row_index: int):
	var item = grid_data[row_index]
	var y_pos = row_index * row_height

	# Main row container
	var row_container = Control.new()
	row_container.name = "Row_%d" % row_index
	row_container.position = Vector2(0, y_pos)
	row_container.size = Vector2(0, row_height)
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.anchor_right = 1.0
	data_container.add_child(row_container)

	# Base background
	var base_bg = ColorRect.new()
	base_bg.name = "BaseBG"
	base_bg.color = alternate_row_color if row_index % 2 == 1 else cell_color
	base_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(base_bg)

	# Hover background (initially transparent)
	var hover_bg = ColorRect.new()
	hover_bg.name = "HoverBG"
	hover_bg.color = Color(0.3, 0.3, 0.4, 0.0)  # Transparent initially
	hover_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(hover_bg)

	# Selection button (invisible, handles clicks)
	var select_button = Button.new()
	select_button.name = "SelectButton"
	select_button.flat = true
	select_button.text = ""
	select_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select_button.pressed.connect(_on_row_selected.bind(row_index, item))
	row_container.add_child(select_button)

	# Hover effects
	select_button.mouse_entered.connect(_on_row_hover.bind(hover_bg, true))
	select_button.mouse_exited.connect(_on_row_hover.bind(hover_bg, false))

	# Create cells with data
	var x_offset = 0.0
	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]
		create_cell(item, col_def, x_offset, 0, i, row_container)
		x_offset += col_def.width


func create_cell(item: Dictionary, col_def: Dictionary, x_pos: float, y_pos: float, col_index: int, parent: Control):
	var cell_label = Label.new()
	cell_label.position = Vector2(x_pos + 5, y_pos)
	cell_label.size = Vector2(col_def.width - 10, row_height)
	cell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell_label.clip_contents = true
	cell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Format cell content based on type
	var field_name = col_def.field
	var cell_value = item.get(field_name, 0)
	var display_text = ""
	var text_color = Color.WHITE

	match col_def.type:
		"text":
			display_text = str(cell_value)
			text_color = Color.WHITE

		"price":
			if field_name == "max_buy" and not item.get("has_buy", false):
				display_text = "No buy orders"
				text_color = Color.GRAY
			elif field_name == "min_sell" and not item.get("has_sell", false):
				display_text = "No sell orders"
				text_color = Color.GRAY
			elif field_name == "spread":
				if item.get("has_buy", false) and item.get("has_sell", false):
					display_text = format_isk(cell_value)
					text_color = Color.YELLOW if cell_value > 0 else Color.RED
				else:
					display_text = "N/A"
					text_color = Color.GRAY
			else:
				display_text = format_isk(cell_value)
				text_color = Color.LIGHT_GREEN if field_name == "max_buy" else Color.LIGHT_CORAL

		"number":
			display_text = format_number(cell_value)
			text_color = Color.LIGHT_BLUE

		"percentage":
			if item.get("has_buy", false) and item.get("has_sell", false):
				display_text = "%.1f%%" % cell_value
				if cell_value > 10:
					text_color = Color.LIGHT_GREEN
				elif cell_value > 5:
					text_color = Color.YELLOW
				elif cell_value > 0:
					text_color = Color.WHITE
				else:
					text_color = Color.LIGHT_CORAL
			else:
				display_text = "N/A"
				text_color = Color.GRAY

	cell_label.text = display_text
	cell_label.add_theme_color_override("font_color", text_color)
	parent.add_child(cell_label)


func _on_row_hover(hover_bg: ColorRect, is_hovering: bool):
	if is_hovering:
		hover_bg.color.a = 0.3  # Show hover effect
	else:
		hover_bg.color.a = 0.0  # Hide hover effect


func _on_row_selected(row_index: int, item: Dictionary):
	var item_id = item.get("item_id", 0)
	print("SpreadsheetGrid: Selected item: ", item.get("item_name", "Unknown"))

	# Add region information
	var enhanced_item_data = item.duplicate()
	enhanced_item_data["region_id"] = current_region_id
	enhanced_item_data["region_name"] = current_region_name

	emit_signal("item_selected", item_id, enhanced_item_data)


func update_row_positions(row_node: Node):
	# Update cell positions in a data row
	var x_offset = 0.0
	var cell_index = 0

	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]

		# Find and update cell at this column
		for child in row_node.get_children():
			if child.position.x >= x_offset - 1 and child.position.x <= x_offset + 1:
				child.position.x = x_offset
				child.size.x = col_def.width
				break

		x_offset += col_def.width


func set_column_width(column_index: int, new_width: float):
	if column_index < 0 or column_index >= column_definitions.size():
		return

	column_definitions[column_index].width = new_width
	rebuild_header()
	refresh_data_display()


func rebuild_header():
	# Clear existing header elements
	for child in header_container.get_children():
		child.queue_free()

	column_separators.clear()
	resize_handles.clear()

	# Wait for cleanup
	await get_tree().process_frame

	# Recreate header
	create_header_cells()
	create_resize_handles()


func handle_cell_click(position: Vector2):
	# Calculate which row was clicked
	var scroll_offset = data_scroll.scroll_vertical
	var adjusted_y = position.y + scroll_offset - header_height

	if adjusted_y < 0:
		return  # Clicked on header

	var row_index = int(adjusted_y / row_height)

	if row_index >= 0 and row_index < grid_data.size():
		var item_data = grid_data[row_index]
		var item_id = item_data.get("item_id", 0)
		emit_signal("item_selected", item_id, item_data)
		print("ExcelGrid: Selected item: ", item_data.get("item_name", "Unknown"))


func update_market_data(data_dict: Dictionary):
	print("ExcelLikeGrid: Updating with data...")

	grid_data = []
	var market_orders = data_dict.get("data", [])

	if typeof(market_orders) != TYPE_ARRAY:
		print("Warning: Expected market orders to be an array")
		return

	# Process market data (same logic as before)
	var items_data = {}
	var unique_item_ids = []

	for order in market_orders:
		if typeof(order) != TYPE_DICTIONARY:
			continue

		var item_id = order.get("type_id", 0)
		var price = float(order.get("price", 0.0))
		var volume = int(order.get("volume_remain", 0))
		var is_buy = bool(order.get("is_buy_order", false))

		# Track unique item IDs
		if item_id not in unique_item_ids:
			unique_item_ids.append(item_id)

		if not items_data.has(item_id):
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

	# Request item names in batch
	if data_manager and unique_item_ids.size() > 0:
		print("Requesting batch names for ", unique_item_ids.size(), " items")
		data_manager.request_item_names_batch(unique_item_ids)

	# Process all items
	for item_id in items_data:
		var item = items_data[item_id]

		# Calculate total volume
		item.volume = item.total_buy_volume + item.total_sell_volume

		# Calculate spread and margin using current calculation mode
		if item.has_buy and item.has_sell and item.max_buy > 0 and item.min_sell < 999999999.0:
			item.spread = item.min_sell - item.max_buy

			# Use current calculation mode for margin
			if calculation_mode == CalculationMode.RAW:
				item.margin = (item.spread / item.max_buy) * 100.0 if item.max_buy > 0 else 0.0
			else:
				# Skill-adjusted calculation
				var character_skills = current_character_data.get("skills", {})
				var mock_buy_orders = [{"price": item.max_buy, "volume": 1}]
				var mock_sell_orders = [{"price": item.min_sell, "volume": 1}]
				var trading_analysis = ProfitCalculator.calculate_optimal_trading_prices(mock_buy_orders, mock_sell_orders, character_skills)

				if not trading_analysis.is_empty() and trading_analysis.get("has_opportunity", false):
					item.margin = trading_analysis.get("profit_margin", 0.0)
				else:
					item.margin = 0.0
		else:
			if not item.has_sell:
				item.min_sell = 0.0
			if not item.has_buy:
				item.max_buy = 0.0
			item.spread = 0.0
			item.margin = 0.0

		# Add items with orders
		if item.volume > 0:
			grid_data.append(item)

	# Sort by volume (most active first)
	grid_data.sort_custom(func(a, b): return a.volume > b.volume)

	print("Added ", grid_data.size(), " items to display")
	refresh_data_display()
	update_progress_display()


func update_progress_display():
	# Count items with real names vs placeholders
	var items_to_show = min(grid_data.size(), 50)
	var named_items = 0

	for i in range(items_to_show):
		var item = grid_data[i]
		var item_name = item.get("item_name", "")
		if not item_name.begins_with("Item ") and item_name != "":
			named_items += 1

	print("Progress: ", named_items, "/", items_to_show, " items named")
	emit_signal("progress_updated", named_items, items_to_show, grid_data.size())


func update_item_name(type_id: int, new_name: String):
	var updated = false

	# Update the item in grid_data
	for item in grid_data:
		if item.get("item_id") == type_id:
			item.item_name = new_name
			updated = true

	# Refresh display if we updated anything
	if updated:
		pending_name_updates = true


func setup_name_update_timer():
	name_update_timer = Timer.new()
	name_update_timer.wait_time = 2.0
	name_update_timer.timeout.connect(_process_pending_name_updates)
	add_child(name_update_timer)
	name_update_timer.start()


func _process_pending_name_updates():
	if pending_name_updates:
		refresh_data_display()
		update_progress_display()
		pending_name_updates = false


func set_region_info(region_id: int, region_name: String):
	current_region_id = region_id
	current_region_name = region_name


# 🔥 NEW: Calculation mode methods
func set_calculation_mode(mode: int):
	calculation_mode = mode
	print("SpreadsheetGrid: Calculation mode set to: ", "RAW" if mode == 0 else "SKILL_ADJUSTED")
	# Trigger a refresh of margins if we have data
	if grid_data.size() > 0:
		refresh_margin_calculations()


func set_character_data(character_data: Dictionary):
	current_character_data = character_data
	print("SpreadsheetGrid: Character data updated")
	# Only refresh if we're in skill-adjusted mode
	if calculation_mode == CalculationMode.SKILL_ADJUSTED:
		refresh_margin_calculations()


func refresh_margin_calculations():
	print("SpreadsheetGrid: Refreshing margin calculations with mode: ", calculation_mode)

	# Update margins in the grid_data
	for item in grid_data:
		if calculation_mode == CalculationMode.RAW:
			# Raw calculation: (sell - buy) / buy * 100
			if item.get("has_buy", false) and item.get("has_sell", false) and item.get("max_buy", 0) > 0:
				var spread = item.get("min_sell", 0) - item.get("max_buy", 0)
				item["margin"] = (spread / item.get("max_buy", 0)) * 100.0
			else:
				item["margin"] = 0.0
		else:
			# Skill-adjusted calculation using ProfitCalculator
			if item.get("has_buy", false) and item.get("has_sell", false):
				var character_skills = current_character_data.get("skills", {})
				var mock_buy_orders = [{"price": item.get("max_buy", 0), "volume": 1}]
				var mock_sell_orders = [{"price": item.get("min_sell", 0), "volume": 1}]
				var trading_analysis = ProfitCalculator.calculate_optimal_trading_prices(mock_buy_orders, mock_sell_orders, character_skills)

				if not trading_analysis.is_empty() and trading_analysis.get("has_opportunity", false):
					item["margin"] = trading_analysis.get("profit_margin", 0.0)
				else:
					item["margin"] = 0.0
			else:
				item["margin"] = 0.0

	# Refresh the visual display
	refresh_data_display()


# Utility functions
func format_isk(value: float) -> String:
	if value >= 1000000000000:
		return "%.2fT" % (value / 1000000000000.0)
	elif value >= 1000000000:
		return "%.2fB" % (value / 1000000000.0)
	elif value >= 1000000:
		return "%.2fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.2fK" % (value / 1000.0)
	else:
		return "%.2f" % value


func format_number(value: int) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	elif value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK" % (value / 1000.0)
	else:
		return str(value)
