# scripts/ui/components/SpreadsheetGrid.gd
class_name SpreadsheetGrid
extends Control

signal item_selected(item_id: int, item_data: Dictionary)
signal progress_updated(named_items: int, total_items: int, total_available: int)
signal column_resized(column_index: int, new_width: float)

var data_manager: DataManager

# Grid data
var grid_data: Array = []
var column_definitions: Array = []
var row_height: float = 25.0
var header_height: float = 30.0

# Visual components
var header_container: Control
var data_scroll: ScrollContainer
var data_container: Control
var column_separators: Array = []
var resize_handles: Array = []

# Interaction state
var is_resizing: bool = false
var resize_column_index: int = -1
var resize_start_pos: float = 0.0
var resize_start_width: float = 0.0

# Region info
var current_region_id: int = 0
var current_region_name: String = "Unknown Region"

# Colors and styling
var header_color: Color = Color(0.15, 0.17, 0.2, 1)
var cell_color: Color = Color(0.1, 0.12, 0.15, 1)
var alternate_row_color: Color = Color(0.12, 0.14, 0.17, 1)
var border_color: Color = Color(0.3, 0.3, 0.4, 1)
var text_color: Color = Color(0.85, 0.85, 0.9, 1)
var header_text_color: Color = Color(0.9, 0.9, 1, 1)
var selected_row_color: Color = Color(0.15, 0.25, 0.35, 0.4)
var hover_row_color: Color = Color(0.2, 0.2, 0.2, 0.3)

var selected_row_index: int = -1
var hovered_row_index: int = -1
var selection_tween: Tween
var hover_tween: Tween
var row_states: Dictionary = {}


func _ready():
	setup_column_definitions()
	setup_grid_structure()
	setup_input_handling()


func setup_column_definitions():
	column_definitions = [
		{"name": "Item Name", "key": "item_name", "width": 200.0, "min_width": 120.0, "max_width": 400.0, "alignment": HORIZONTAL_ALIGNMENT_LEFT, "color_func": null},
		{
			"name": "Buy Price",
			"key": "max_buy",
			"width": 100.0,
			"min_width": 80.0,
			"max_width": 150.0,
			"alignment": HORIZONTAL_ALIGNMENT_RIGHT,
			"color_func": func(value): return Color.LIGHT_GREEN if value > 0 else Color.GRAY,
			"format_func": format_isk
		},
		{
			"name": "Sell Price",
			"key": "min_sell",
			"width": 100.0,
			"min_width": 80.0,
			"max_width": 150.0,
			"alignment": HORIZONTAL_ALIGNMENT_RIGHT,
			"color_func": func(value): return Color.LIGHT_CORAL if value > 0 else Color.GRAY,
			"format_func": format_isk
		},
		{"name": "Spread", "key": "spread", "width": 80.0, "min_width": 60.0, "max_width": 120.0, "alignment": HORIZONTAL_ALIGNMENT_RIGHT, "format_func": format_isk},
		{
			"name": "Margin %",
			"key": "margin",
			"width": 80.0,
			"min_width": 60.0,
			"max_width": 120.0,
			"alignment": HORIZONTAL_ALIGNMENT_CENTER,
			"color_func": func(value): return Color.LIGHT_GREEN if value > 10 else (Color.YELLOW if value > 5 else (Color.WHITE if value > 0 else Color.GRAY)),
			"format_func": func(value): return "%.1f%%" % value if value > 0 else "N/A"
		},
		{
			"name": "Volume",
			"key": "volume",
			"width": 80.0,
			"min_width": 60.0,
			"max_width": 120.0,
			"alignment": HORIZONTAL_ALIGNMENT_RIGHT,
			"color_func": func(value): return Color.LIGHT_BLUE,
			"format_func": format_number
		}
	]


func setup_grid_structure():
	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# Header
	create_header(main_vbox)

	# Data area with scrolling
	data_scroll = ScrollContainer.new()
	data_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	data_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(data_scroll)

	# Data container - EXPAND TO FILL
	data_container = Control.new()
	data_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data_scroll.add_child(data_container)

	print("ExcelLikeGrid structure created")


func create_header(parent: VBoxContainer):
	# Header background
	var header_bg = ColorRect.new()
	header_bg.color = header_color
	header_bg.custom_minimum_size.y = header_height
	parent.add_child(header_bg)

	# Header container for text and resize handles
	header_container = Control.new()
	header_container.custom_minimum_size.y = header_height
	header_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_bg.add_child(header_container)

	create_header_cells()
	create_resize_handles()

	# Header border
	var border = ColorRect.new()
	border.color = border_color
	border.custom_minimum_size.y = 1
	parent.add_child(border)


func create_header_cells():
	var x_offset = 0.0

	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]

		# Create header cell background
		var cell_bg = ColorRect.new()
		cell_bg.color = Color.TRANSPARENT
		cell_bg.position.x = x_offset
		cell_bg.position.y = 0
		cell_bg.size.x = col_def.width
		cell_bg.size.y = header_height
		header_container.add_child(cell_bg)

		# Create header label
		var label = Label.new()
		label.text = col_def.name
		label.add_theme_color_override("font_color", header_text_color)
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position.x = x_offset + 5
		label.position.y = 0
		label.size.x = col_def.width - 10
		label.size.y = header_height
		label.clip_contents = true
		header_container.add_child(label)

		# Create vertical separator
		if i < column_definitions.size() - 1:
			var separator = ColorRect.new()
			separator.color = border_color
			separator.position.x = x_offset + col_def.width
			separator.position.y = 0
			separator.size.x = 1
			separator.size.y = header_height
			header_container.add_child(separator)
			column_separators.append(separator)

		x_offset += col_def.width


func create_resize_handles():
	var x_offset = 0.0

	for i in range(column_definitions.size() - 1):  # No handle after last column
		var col_def = column_definitions[i]
		x_offset += col_def.width

		# Create invisible resize handle
		var handle = Control.new()
		handle.position.x = x_offset - 5
		handle.position.y = 0
		handle.size.x = 10
		handle.size.y = header_height
		handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE

		# Make it slightly visible for debugging (remove this in production)
		handle.modulate = Color(1, 1, 1, 0.1)

		header_container.add_child(handle)

		# Connect signals for this handle
		var column_index = i
		handle.gui_input.connect(_on_resize_handle_input.bind(column_index))
		handle.mouse_entered.connect(func(): handle.modulate = Color(1, 1, 1, 0.2))
		handle.mouse_exited.connect(func(): handle.modulate = Color(1, 1, 1, 0.1))

		resize_handles.append(handle)


func setup_input_handling():
	gui_input.connect(_on_grid_input)


func _on_global_input(event: InputEvent):
	# Handle global mouse release to prevent stuck resize state
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if is_resizing:
				end_column_resize()


func _on_resize_handle_input(event: InputEvent, column_index: int):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				start_column_resize(column_index, mouse_event.global_position.x)
				# Capture mouse to prevent losing events
				get_viewport().set_input_as_handled()
			else:
				if is_resizing and resize_column_index == column_index:
					end_column_resize()
	elif event is InputEventMouseMotion and is_resizing and resize_column_index == column_index:
		update_column_resize(event.global_position.x)
		get_viewport().set_input_as_handled()


func _on_grid_input(event: InputEvent):
	if event is InputEventMouseMotion and is_resizing:
		update_column_resize(event.global_position.x)
	elif event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if is_resizing:
				end_column_resize()
			else:
				handle_cell_click(mouse_event.position)


func start_column_resize(column_index: int, mouse_x: float):
	if is_resizing:
		return  # Prevent double-start

	is_resizing = true
	resize_column_index = column_index
	resize_start_pos = mouse_x
	resize_start_width = column_definitions[column_index].width

	# Change mouse cursor globally
	Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
	print("Started resizing column ", column_index)


func update_column_resize(mouse_x: float):
	if not is_resizing or resize_column_index < 0:
		return

	var delta = mouse_x - resize_start_pos
	var new_width = resize_start_width + delta
	var col_def = column_definitions[resize_column_index]

	# Clamp to min/max width
	new_width = max(col_def.min_width, min(col_def.max_width, new_width))

	# Only update if width actually changed
	if abs(new_width - col_def.width) > 1.0:
		set_column_width_immediate(resize_column_index, new_width)


func end_column_resize():
	if not is_resizing:
		return

	print("Ended resizing column ", resize_column_index)

	# Reset cursor
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	# Emit signal for saving preferences
	if resize_column_index >= 0:
		emit_signal("column_resized", resize_column_index, column_definitions[resize_column_index].width)

	is_resizing = false
	resize_column_index = -1


func set_column_width_immediate(column_index: int, new_width: float):
	if column_index < 0 or column_index >= column_definitions.size():
		return

	column_definitions[column_index].width = new_width
	update_header_positions()
	update_data_positions()
	refresh_data_display()


func update_header_positions():
	var x_offset = 0.0
	var child_index = 0

	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]

		# Update header cell position and size
		if child_index < header_container.get_child_count():
			var cell_bg = header_container.get_child(child_index)
			if cell_bg is ColorRect:
				cell_bg.position.x = x_offset
				cell_bg.size.x = col_def.width
				child_index += 1

			# Update label
			if child_index < header_container.get_child_count():
				var label = header_container.get_child(child_index)
				if label is Label:
					label.position.x = x_offset + 5
					label.size.x = col_def.width - 10
					child_index += 1

		# Update separator position
		if i < column_definitions.size() - 1 and child_index < header_container.get_child_count():
			var separator = header_container.get_child(child_index)
			if separator is ColorRect:
				separator.position.x = x_offset + col_def.width
				child_index += 1

		x_offset += col_def.width

	# Update resize handles
	update_resize_handle_positions()


func update_resize_handle_positions():
	var x_offset = 0.0

	for i in range(resize_handles.size()):
		if i < column_definitions.size():
			x_offset += column_definitions[i].width
			if i < resize_handles.size():
				resize_handles[i].position.x = x_offset - 5


func update_data_positions():
	# Update data rows to match new column positions
	# This is more efficient than rebuilding everything
	for row_child in data_container.get_children():
		if row_child.has_method("get_children"):
			update_row_positions(row_child)


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

		if not unique_item_ids.has(item_id):
			unique_item_ids.append(item_id)

		if not items_data.has(item_id):
			items_data[item_id] = {
				"item_id": item_id,
				"item_name": data_manager.get_item_name(item_id) if data_manager else "Item %d" % item_id,
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

	# Request batch item names
	if data_manager and unique_item_ids.size() > 0:
		data_manager.request_item_names_batch(unique_item_ids)

	# Process all items
	for item_id in items_data:
		var item = items_data[item_id]

		item.volume = item.total_buy_volume + item.total_sell_volume

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

		if item.volume > 0:
			grid_data.append(item)

	# Sort by volume
	grid_data.sort_custom(func(a, b): return a.volume > b.volume)

	refresh_data_display()

	# Emit progress
	var named_items = 0
	for item in grid_data:
		if not item.get("item_name", "").begins_with("Item "):
			named_items += 1

	emit_signal("progress_updated", named_items, grid_data.size(), grid_data.size())


func refresh_data_display():
	selected_row_index = -1

	# Clear existing data display
	for child in data_container.get_children():
		child.queue_free()

	if grid_data.is_empty():
		var no_data = Label.new()
		no_data.text = "No market data available. Click Refresh to load data."
		no_data.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data.add_theme_color_override("font_color", Color.YELLOW)
		no_data.position = Vector2(10, 10)
		data_container.add_child(no_data)
		return

	# DON'T set custom_minimum_size - let it expand naturally
	# Set only the height based on row count
	data_container.custom_minimum_size.y = grid_data.size() * row_height

	# Create rows
	for row_index in range(min(grid_data.size(), 50)):
		create_enhanced_data_row(row_index)


func create_data_row(row_index: int):
	var item = grid_data[row_index]
	var y_pos = row_index * row_height

	# Row background (alternating colors) - fill available width
	var row_bg = ColorRect.new()
	row_bg.color = alternate_row_color if row_index % 2 == 1 else cell_color
	row_bg.position = Vector2(0, y_pos)
	row_bg.size = Vector2(data_container.size.x, row_height)
	row_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	data_container.add_child(row_bg)

	# Create clickable area for row selection
	var row_button = Button.new()
	row_button.flat = true
	row_button.text = ""
	row_button.position = Vector2(0, y_pos)
	row_button.size = Vector2(data_container.size.x, row_height)
	row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_button.mouse_filter = Control.MOUSE_FILTER_PASS
	row_button.pressed.connect(func(): _on_row_selected(row_index, item))
	data_container.add_child(row_button)

	# Create cells
	var x_offset = 0.0
	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]
		create_cell(item, col_def, x_offset, y_pos, i)
		x_offset += col_def.width


func create_enhanced_data_row(row_index: int):
	var item = grid_data[row_index]
	var y_pos = row_index * row_height

	# Main row container - EXPAND TO FILL WIDTH
	var row_container = Control.new()
	row_container.name = "Row_%d" % row_index
	row_container.position = Vector2(0, y_pos)
	row_container.size = Vector2(0, row_height)  # Set width to 0, let it expand
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.anchor_right = 1.0  # Anchor to right edge
	data_container.add_child(row_container)

	# Base background - FILL THE ROW CONTAINER
	var base_bg = ColorRect.new()
	base_bg.name = "BaseBG"
	base_bg.color = alternate_row_color if row_index % 2 == 1 else cell_color
	base_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(base_bg)

	# Hover background - FILL THE ROW CONTAINER
	var hover_bg = ColorRect.new()
	hover_bg.name = "HoverBG"
	hover_bg.color = Color.TRANSPARENT
	hover_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(hover_bg)

	# Selection background - FILL THE ROW CONTAINER
	var selection_bg = ColorRect.new()
	selection_bg.name = "SelectionBG"
	selection_bg.color = Color.TRANSPARENT
	selection_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selection_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(selection_bg)

	# Button - FILL THE ROW CONTAINER
	var row_button = Button.new()
	row_button.flat = true
	row_button.text = ""
	row_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_button.add_theme_color_override("font_color", Color.TRANSPARENT)
	row_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	row_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	row_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	row_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	row_button.pressed.connect(func(): _on_row_selected(row_index, item))
	row_button.mouse_entered.connect(func(): _set_hover(row_index, true))
	row_button.mouse_exited.connect(func(): _set_hover(row_index, false))
	row_container.add_child(row_button)

	# Content layer for text
	var content_layer = Control.new()
	content_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_container.add_child(content_layer)

	# Create cells
	var x_offset = 0.0
	for i in range(column_definitions.size()):
		var col_def = column_definitions[i]
		create_enhanced_cell(item, col_def, x_offset, 0, i, content_layer)
		x_offset += col_def.width


func _set_hover(row_index: int, hovering: bool):
	if row_index < 0 or row_index >= data_container.get_child_count():
		return

	var row_container = data_container.get_child(row_index)
	if not row_container:
		return

	var hover_bg = row_container.get_node("HoverBG")
	if hover_bg:
		hover_bg.color = hover_row_color if hovering else Color.TRANSPARENT


func _on_row_selected(row_index: int, item: Dictionary):
	# Clear old selection
	if selected_row_index >= 0:
		var old_row = data_container.get_child(selected_row_index)
		if old_row:
			var old_selection = old_row.get_node("SelectionBG")
			if old_selection:
				old_selection.color = Color.TRANSPARENT

	# Set new selection
	selected_row_index = row_index
	var row_container = data_container.get_child(row_index)
	if row_container:
		var selection_bg = row_container.get_node("SelectionBG")
		if selection_bg:
			selection_bg.color = selected_row_color

	# Emit signal
	var item_id = item.get("item_id", 0)
	emit_signal("item_selected", item_id, item)


func _on_row_clicked(row_index: int, item: Dictionary):
	animate_selection(row_index)
	var item_id = item.get("item_id", 0)
	emit_signal("item_selected", item_id, item)
	print("ExcelGrid: Selected item: ", item.get("item_name", "Unknown"))


func _on_row_hover_start(row_index: int):
	# Prevent stuck highlights by checking current state
	if not row_states.has(row_index):
		row_states[row_index] = {"is_hovered": false, "is_selected": false}

	if not row_states[row_index].is_hovered:
		row_states[row_index].is_hovered = true
		animate_hover(row_index, true)
		hovered_row_index = row_index


func _on_row_hover_end(row_index: int):
	# Clear hover state and animate out
	if row_states.has(row_index):
		row_states[row_index].is_hovered = false

	if hovered_row_index == row_index:
		animate_hover(row_index, false)
		hovered_row_index = -1


func animate_selection(row_index: int):
	# Clear previous selection state
	if selected_row_index >= 0:
		if row_states.has(selected_row_index):
			row_states[selected_row_index].is_selected = false
		clear_row_selection(selected_row_index)

	# Set new selection
	selected_row_index = row_index
	if not row_states.has(row_index):
		row_states[row_index] = {"is_hovered": false, "is_selected": false}
	row_states[row_index].is_selected = true

	var row_container = data_container.get_child(row_index)
	if not row_container:
		return

	var selection_bg = row_container.get_node("SelectionBG")

	if selection_tween:
		selection_tween.kill()

	selection_tween = create_tween()

	# Simple, subtle selection animation
	selection_tween.tween_method(func(color): selection_bg.color = color, Color.TRANSPARENT, selected_row_color, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func animate_hover(row_index: int, is_hovering: bool):
	if row_index < 0 or row_index >= data_container.get_child_count():
		return

	var row_container = data_container.get_child(row_index)
	if not row_container:
		return

	var hover_bg = row_container.get_node("HoverBG")

	# Kill existing hover tween to prevent conflicts
	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()

	var target_color = hover_row_color if is_hovering else Color.TRANSPARENT
	var duration = 0.1 if is_hovering else 0.2

	hover_tween.tween_method(func(color): hover_bg.color = color, hover_bg.color, target_color, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func clear_row_selection(row_index: int):
	if row_index < 0 or row_index >= data_container.get_child_count():
		return

	var row_container = data_container.get_child(row_index)
	if not row_container:
		return

	var selection_bg = row_container.get_node("SelectionBG")

	var clear_tween = create_tween()
	clear_tween.tween_method(func(color): selection_bg.color = color, selection_bg.color, Color.TRANSPARENT, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func create_enhanced_cell(item: Dictionary, col_def: Dictionary, x: float, y: float, col_index: int, parent: Control):
	# Cell container
	var cell = Control.new()
	cell.position = Vector2(x, y)
	cell.size = Vector2(col_def.width, row_height)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cell)

	# Cell text - simplified styling
	var label = Label.new()
	label.position = Vector2(6, 0)
	label.size = Vector2(col_def.width - 12, row_height)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = col_def.alignment
	label.clip_contents = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Get and format cell value
	var value = item.get(col_def.key, 0)
	var text = str(value)

	if col_def.has("format_func") and col_def.format_func != null:
		text = col_def.format_func.call(value)

	label.text = text

	# Apply color
	var color = text_color
	if col_def.has("color_func") and col_def.color_func != null:
		color = col_def.color_func.call(value)

	label.add_theme_color_override("font_color", color)
	cell.add_child(label)

	# Subtle cell border
	if col_index < column_definitions.size() - 1:
		var border = ColorRect.new()
		border.color = Color(border_color.r, border_color.g, border_color.b, 0.2)
		border.position = Vector2(col_def.width - 1, 0)
		border.size = Vector2(1, row_height)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(border)


func create_cell(item: Dictionary, col_def: Dictionary, x: float, y: float, col_index: int):
	# Cell container
	var cell = Control.new()
	cell.position = Vector2(x, y)
	cell.size = Vector2(col_def.width, row_height)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	data_container.add_child(cell)

	# Cell text
	var label = Label.new()
	label.position = Vector2(5, 0)
	label.size = Vector2(col_def.width - 10, row_height)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = col_def.alignment
	label.clip_contents = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Get and format cell value
	var value = item.get(col_def.key, 0)
	var text = str(value)

	if col_def.has("format_func") and col_def.format_func != null:
		text = col_def.format_func.call(value)

	label.text = text

	# Apply color
	var color = text_color
	if col_def.has("color_func") and col_def.color_func != null:
		color = col_def.color_func.call(value)
	label.add_theme_color_override("font_color", color)

	cell.add_child(label)

	# Cell border
	if col_index < column_definitions.size() - 1:
		var border = ColorRect.new()
		border.color = border_color
		border.position = Vector2(col_def.width - 1, 0)
		border.size = Vector2(1, row_height)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(border)


# Utility functions
func format_isk(value: float) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return "%.0f" % value


func format_number(value: float) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return "%.0f" % value


func update_item_name(type_id: int, new_name: String):
	var updated = false
	for item in grid_data:
		if item.get("item_id") == type_id:
			item.item_name = new_name
			updated = true

	if updated:
		refresh_data_display()


func set_region_info(region_id: int, region_name: String):
	current_region_id = region_id
	current_region_name = region_name


func get_item_data(item_id: int) -> Dictionary:
	for item in grid_data:
		if item.get("item_id", 0) == item_id:
			return item.duplicate()
	return {}
