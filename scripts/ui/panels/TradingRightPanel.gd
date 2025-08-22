# scripts/ui/panels/TradingRightPanel.gd
class_name TradingRightPanel
extends VBoxContainer

signal order_placed(order_data: Dictionary)
signal alert_created(alert_data: Dictionary)

var selected_item_data: Dictionary = {}
var current_market_data: Dictionary = {}
var market_chart: MarketChart
var order_book_list: VBoxContainer
var quick_trade_panel: VBoxContainer
var analysis_tools_menu: MenuButton
var chart_display_menu: MenuButton

var current_loading_item_id: int = -1
var pending_historical_request: bool = false
var rapid_switch_count: int = 0
var last_switch_time: float = 0.0

var chart_data_cache: Dictionary = {}  # Cache historical data by item_id
var last_chart_request_time: float = 0.0
var min_chart_request_interval: float = 2.0  # Minimum 2 seconds between chart requests
var pending_chart_request_timer: Timer
var queued_item_id: int = -1

@onready var data_manager: DataManager


func _ready():
	setup_panels()


func setup_panels():
	# Clear existing content
	for child in get_children():
		child.queue_free()

	# Set the VBoxContainer to fill and expand
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 1. Item Info Header (fixed height)
	create_item_info_header()

	# 2. Real-time Price Chart (expandable)
	create_market_chart()


func create_order_book():
	"""Create order book section with fixed height"""
	var order_book_panel = PanelContainer.new()
	order_book_panel.name = "OrderBookPanel"
	order_book_panel.custom_minimum_size.y = 200  # Fixed height
	order_book_panel.size_flags_vertical = Control.SIZE_SHRINK_END  # Don't expand
	add_child(order_book_panel)

	var order_book_scroll = ScrollContainer.new()
	order_book_panel.add_child(order_book_scroll)

	order_book_list = VBoxContainer.new()
	order_book_scroll.add_child(order_book_list)


func create_item_info_header():
	var header_panel = PanelContainer.new()
	header_panel.name = "ItemInfoPanel"
	header_panel.custom_minimum_size.y = 60  # Slightly taller for better info display
	add_child(header_panel)

	var header_vbox = VBoxContainer.new()
	header_panel.add_child(header_vbox)

	var item_name_label = Label.new()
	item_name_label.name = "ItemNameLabel"
	item_name_label.text = "Select an item"
	item_name_label.add_theme_font_size_override("font_size", 16)
	item_name_label.add_theme_color_override("font_color", Color.CYAN)
	header_vbox.add_child(item_name_label)

	var price_container = HBoxContainer.new()
	header_vbox.add_child(price_container)

	var buy_price_label = Label.new()
	buy_price_label.name = "BuyPriceLabel"
	buy_price_label.text = "Buy: --"
	buy_price_label.add_theme_color_override("font_color", Color.GREEN)
	price_container.add_child(buy_price_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_container.add_child(spacer)

	var sell_price_label = Label.new()
	sell_price_label.name = "SellPriceLabel"
	sell_price_label.text = "Sell: --"
	sell_price_label.add_theme_color_override("font_color", Color.RED)
	price_container.add_child(sell_price_label)

	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_container.add_child(spacer2)

	var spread_label = Label.new()
	spread_label.name = "SpreadLabel"
	spread_label.text = "Spread: --"
	spread_label.add_theme_color_override("font_color", Color.YELLOW)
	price_container.add_child(spread_label)


func create_market_chart():
	var chart_panel = PanelContainer.new()
	chart_panel.name = "ChartPanel"
	chart_panel.custom_minimum_size.y = 300  # Larger minimum since it has more space
	chart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Takes all remaining space
	add_child(chart_panel)

	var chart_vbox = VBoxContainer.new()
	chart_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart_panel.add_child(chart_vbox)

	var controls = create_chart_controls()
	chart_vbox.add_child(controls)

	var chart_header_container = HBoxContainer.new()
	chart_header_container.custom_minimum_size.y = 5
	chart_vbox.add_child(chart_header_container)

	market_chart = MarketChart.new()
	market_chart.name = "MarketChart"
	market_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	market_chart.historical_data_requested.connect(_on_historical_data_requested)

	# EXPLICITLY disable any tooltip behavior
	market_chart.tooltip_text = ""
	market_chart.mouse_filter = Control.MOUSE_FILTER_PASS

	chart_vbox.add_child(market_chart)

	# Connect signals

	chart_panel.resized.connect(_on_chart_panel_resized)
	market_chart.resized.connect(_on_chart_resized)

	return chart_panel


func create_chart_controls():
	"""Create chart control dropdowns with proper checkboxes and styling"""
	var controls_container = HBoxContainer.new()
	controls_container.name = "ChartControls"
	controls_container.alignment = BoxContainer.ALIGNMENT_BEGIN  # Center the controls
	controls_container.custom_minimum_size.y = 20  # Give more height for better appearance

	# Analysis Tools Menu
	analysis_tools_menu = MenuButton.new()
	analysis_tools_menu.name = "AnalysisToolsMenu"
	analysis_tools_menu.text = "Analysis Tools..."
	analysis_tools_menu.custom_minimum_size = Vector2(180, 20)

	# Style the Analysis Tools menu button
	_style_menu_button(analysis_tools_menu)

	var analysis_popup = analysis_tools_menu.get_popup()
	analysis_popup.add_check_item("Spread Analysis")
	analysis_popup.add_check_item("S/R Analysis")
	analysis_popup.add_check_item("Donchian Channel")
	analysis_popup.id_pressed.connect(_on_analysis_menu_selected)
	controls_container.add_child(analysis_tools_menu)

	# Chart Display Menu
	chart_display_menu = MenuButton.new()
	chart_display_menu.name = "ChartDisplayMenu"
	chart_display_menu.text = "Chart Display..."
	chart_display_menu.custom_minimum_size = Vector2(180, 20)

	# Style the Chart Display menu button
	_style_menu_button(chart_display_menu)

	var display_popup = chart_display_menu.get_popup()
	display_popup.add_check_item("Candlesticks")
	display_popup.add_check_item("Data Points")
	display_popup.add_check_item("MA Line")
	display_popup.id_pressed.connect(_on_chart_display_menu_selected)
	controls_container.add_child(chart_display_menu)

	# Set initial checkbox states
	_update_menu_states()

	return controls_container


func _style_menu_button(menu_button: MenuButton):
	"""Apply consistent styling to menu buttons"""
	# Create custom StyleBox for normal state
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.18, 0.2, 0.25, 1.0)  # Updated color
	style_normal.content_margin_left = 8
	style_normal.content_margin_top = 4
	style_normal.content_margin_right = 8
	style_normal.content_margin_bottom = 4
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.35, 0.4, 0.45, 1.0)  # Updated border color
	# Remove all corner radius for sharp corners
	style_normal.corner_radius_top_left = 0
	style_normal.corner_radius_top_right = 0
	style_normal.corner_radius_bottom_left = 0
	style_normal.corner_radius_bottom_right = 0

	# Create custom StyleBox for hover state
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.25, 0.28, 0.33, 1.0)  # Updated color
	style_hover.content_margin_left = 8
	style_hover.content_margin_top = 4
	style_hover.content_margin_right = 8
	style_hover.content_margin_bottom = 4
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.45, 0.5, 0.55, 1.0)  # Updated border color
	style_hover.corner_radius_top_left = 0
	style_hover.corner_radius_top_right = 0
	style_hover.corner_radius_bottom_left = 0
	style_hover.corner_radius_bottom_right = 0

	# Create custom StyleBox for pressed state
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.12, 0.15, 0.18, 1.0)  # Updated color
	style_pressed.content_margin_left = 8
	style_pressed.content_margin_top = 4
	style_pressed.content_margin_right = 8
	style_pressed.content_margin_bottom = 4
	style_pressed.border_width_left = 1
	style_pressed.border_width_right = 1
	style_pressed.border_width_top = 1
	style_pressed.border_width_bottom = 1
	style_pressed.border_color = Color(0.55, 0.6, 0.65, 1.0)  # Updated border color
	style_pressed.corner_radius_top_left = 0
	style_pressed.corner_radius_top_right = 0
	style_pressed.corner_radius_bottom_left = 0
	style_pressed.corner_radius_bottom_right = 0

	# Apply the styles
	menu_button.add_theme_stylebox_override("normal", style_normal)
	menu_button.add_theme_stylebox_override("hover", style_hover)
	menu_button.add_theme_stylebox_override("pressed", style_pressed)

	# Set font properties
	menu_button.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1))
	menu_button.add_theme_color_override("font_hover_color", Color(0.95, 0.98, 1.0, 1.0))
	menu_button.add_theme_color_override("font_pressed_color", Color(0.75, 0.85, 0.95, 1.0))

	# Set smaller font size for sleeker look
	menu_button.add_theme_font_size_override("font_size", 11)

	# Center the text
	menu_button.alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_chart_loading_state():
	"""Show loading overlay specifically on the ChartPanel"""
	print("=== CHART LOADING STATE ===")

	# Find the ChartPanel specifically
	var chart_panel = get_node_or_null("ChartPanel")
	if not chart_panel:
		print("ERROR: ChartPanel not found")
		return

	# IMMEDIATELY remove ALL existing loading overlays (not just queue_free)
	var children_to_remove = []
	for child in chart_panel.get_children():
		if child.name.begins_with("ChartLoadingOverlay"):
			children_to_remove.append(child)

	for child in children_to_remove:
		print("Immediately removing existing loading overlay: ", child.name)
		chart_panel.remove_child(child)
		child.queue_free()

	# Also remove timeout timers immediately
	var timers_to_remove = []
	for child in get_children():
		if child is Timer and child.name.begins_with("LoadingTimeout"):
			timers_to_remove.append(child)

	for timer in timers_to_remove:
		print("Immediately removing timeout timer: ", timer.name)
		remove_child(timer)
		timer.queue_free()

	# Create loading overlay with unique name to prevent conflicts
	var timestamp = str(Time.get_ticks_msec())
	var loading_overlay = Control.new()
	loading_overlay.name = "ChartLoadingOverlay_" + timestamp
	loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_overlay.z_index = 100

	# Bright background for visibility
	var background = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.0, 0.0, 0.0, 0.8)
	loading_overlay.add_child(background)

	# Centered content
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_child(center_container)

	# Loading panel
	var loading_panel = PanelContainer.new()
	loading_panel.custom_minimum_size = Vector2(300, 120)

	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.2, 1.0)
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color.CYAN
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	loading_panel.add_theme_stylebox_override("panel", panel_style)

	center_container.add_child(loading_panel)

	# Content margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	loading_panel.add_child(margin)

	# Content vbox
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Loading title
	var loading_title = Label.new()
	loading_title.text = "Loading Chart Data..."
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_title.add_theme_font_size_override("font_size", 20)
	loading_title.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(loading_title)

	# Loading message
	var loading_message = Label.new()
	var item_name = selected_item_data.get("item_name", "Unknown Item")

	if item_name and item_name != "":
		loading_message.text = "Fetching price history for " + str(item_name) + "..."
	else:
		loading_message.text = "Fetching price history..."

	loading_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_message.add_theme_font_size_override("font_size", 14)
	loading_message.add_theme_color_override("font_color", Color.WHITE)
	loading_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(loading_message)

	# Progress indicator
	var progress_label = Label.new()
	progress_label.text = "●●●●●"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 18)
	progress_label.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(progress_label)

	# Add to the ChartPanel
	chart_panel.add_child(loading_overlay)
	loading_overlay.visible = true

	print("Added loading overlay to ChartPanel: ", loading_overlay.name)

	# Animate progress dots
	var tween = loading_overlay.create_tween()
	tween.set_loops()
	tween.tween_property(progress_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(progress_label, "modulate:a", 1.0, 0.8)

	# Add timeout safety mechanism with unique name
	var timeout_timer = Timer.new()
	timeout_timer.name = "LoadingTimeout_" + timestamp
	timeout_timer.wait_time = 6.0  # Even shorter timeout
	timeout_timer.one_shot = true
	timeout_timer.timeout.connect(
		func():
			print("Loading timeout - forcing cleanup")
			force_cleanup_all_loading_panels()
			timeout_timer.queue_free()
	)
	add_child(timeout_timer)
	timeout_timer.start()


func hide_chart_loading_state():
	"""Hide ALL loading overlays from the ChartPanel immediately"""
	print("=== HIDING ALL CHART LOADING PANELS ===")

	# Reset loading state flags
	pending_historical_request = false

	var chart_panel = get_node_or_null("ChartPanel")
	if not chart_panel:
		print("ERROR: ChartPanel not found")
		return

	# Remove ALL loading overlays immediately
	var children_to_remove = []
	for child in chart_panel.get_children():
		if child.name.begins_with("ChartLoadingOverlay"):
			children_to_remove.append(child)

	print("Found ", children_to_remove.size(), " loading overlays to remove")

	for child in children_to_remove:
		print("Immediately removing loading overlay: ", child.name)
		chart_panel.remove_child(child)
		child.queue_free()

	# Also remove timeout timers
	var timers_to_remove = []
	for child in get_children():
		if child is Timer and child.name.begins_with("LoadingTimeout"):
			timers_to_remove.append(child)

	for timer in timers_to_remove:
		print("Immediately removing timeout timer: ", timer.name)
		remove_child(timer)
		timer.queue_free()


func is_rapid_switching() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0

	if current_time - last_switch_time < 2.0:  # Less than 2 seconds since last switch
		rapid_switch_count += 1
	else:
		rapid_switch_count = 0  # Reset if enough time has passed

	last_switch_time = current_time

	var is_rapid = rapid_switch_count > 2  # More than 2 switches in rapid succession
	if is_rapid:
		print("RAPID SWITCHING DETECTED - count: ", rapid_switch_count)

	return is_rapid


func _on_analysis_menu_selected(id: int):
	"""Handle analysis tools menu selection"""
	if not market_chart:
		return

	match id:
		0:  # Spread Analysis
			market_chart.toggle_spread_analysis()
		1:  # S/R Analysis
			market_chart.toggle_support_resistance()
		2:  # Donchian Channel  # ADD THIS CASE
			market_chart.toggle_donchian_channel()

	_update_menu_states()


func _on_chart_display_menu_selected(id: int):
	"""Handle chart display menu selection"""
	if not market_chart:
		return

	match id:
		0:  # Candlesticks
			market_chart.toggle_candlesticks()
		1:  # Data Points
			market_chart.toggle_data_points()
		2:  # MA Lines
			market_chart.toggle_ma_lines()

	_update_menu_states()


func _update_menu_states():
	"""Update menu checkbox states"""
	if not market_chart:
		return

	# Update Analysis Tools menu
	if analysis_tools_menu:
		var analysis_popup = analysis_tools_menu.get_popup()
		analysis_popup.set_item_checked(0, market_chart.show_spread_analysis)
		analysis_popup.set_item_checked(1, market_chart.show_support_resistance)
		analysis_popup.set_item_checked(2, market_chart.show_donchian_channel)

	# Update Chart Display menu
	if chart_display_menu:
		var display_popup = chart_display_menu.get_popup()
		display_popup.set_item_checked(0, market_chart.show_candlesticks)
		display_popup.set_item_checked(1, market_chart.show_data_points)
		display_popup.set_item_checked(2, market_chart.show_ma_lines)


func _on_chart_panel_resized():
	"""Called when the chart panel is resized"""
	print("Chart panel resized to: ", get_node("ChartPanel").size)
	if market_chart:
		# Force a redraw to adjust to new size
		market_chart.queue_redraw()


func _on_chart_resized():
	"""Called when the chart itself is resized"""
	if market_chart:
		print("Chart resized to: ", market_chart.size)
		# Recalculate chart boundaries and redraw
		market_chart.queue_redraw()


func create_order_book_header():
	"""Create order book header"""
	var header = HBoxContainer.new()
	order_book_list.add_child(header)

	var price_header = Label.new()
	price_header.text = "Price (ISK)"
	price_header.custom_minimum_size.x = 100
	price_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(price_header)

	var volume_header = Label.new()
	volume_header.text = "Volume"
	volume_header.custom_minimum_size.x = 80
	volume_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(volume_header)

	var type_header = Label.new()
	type_header.text = "Type"
	type_header.custom_minimum_size.x = 50
	type_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(type_header)


func update_item_display(item_data: Dictionary):
	"""Called only for NEW item selection - this clears the chart"""
	print("=== TRADING PANEL: NEW ITEM SELECTED ===")
	var new_item_id = item_data.get("item_id", 0)
	print("New item: ", item_data.get("item_name", "Unknown"), " (ID: ", new_item_id, ")")

	# Cancel any pending chart request timer
	if pending_chart_request_timer:
		pending_chart_request_timer.queue_free()
		pending_chart_request_timer = null

	# Always clean up loading panels
	force_cleanup_all_loading_panels()

	# Set new item tracking
	current_loading_item_id = new_item_id
	selected_item_data = item_data

	if market_chart:
		# ALWAYS completely reset chart state first
		print("Performing complete chart reset...")
		market_chart.clear_data()
		market_chart.chart_data.is_loading_historical = false
		market_chart.chart_data.has_loaded_historical = false
		market_chart.zoom_level = 1.0
		print("Chart completely reset")

	# Check if we have cached data for this item
	var cached_data = get_cached_chart_data(new_item_id)
	if not cached_data.is_empty():
		print("Loading chart from cache for item ", new_item_id)

		# Set basic chart data (without centering)
		if market_chart:
			market_chart.set_station_trading_data(item_data)

		# Wait a frame to ensure chart setup is complete
		await get_tree().process_frame

		# Load cached data - centering will happen after data is loaded
		load_cached_chart_data(cached_data)
	else:
		# Show loading and handle request throttling
		show_chart_loading_state()

		if should_request_chart_data(new_item_id):
			print("Requesting chart data immediately for item ", new_item_id)
			request_chart_data_for_item(new_item_id)
		else:
			print("Throttling chart request for item ", new_item_id)
			queue_chart_request(new_item_id)

	# Always update other displays (but NOT chart centering yet)
	if market_chart:
		market_chart.set_station_trading_data(item_data)

		var max_buy = item_data.get("max_buy", 0.0)
		var min_sell = item_data.get("min_sell", 0.0)
		if max_buy > 0 and min_sell > 0:
			market_chart.update_spread_data(max_buy, min_sell)

	update_item_header(item_data)
	update_trading_defaults(item_data)
	update_alert_defaults(item_data)
	update_order_book(item_data)

	print("New item display setup complete")


func load_cached_chart_data(cached_history_data: Dictionary):
	"""Load cached chart data with proper state management"""
	print("=== LOADING CACHED CHART DATA ===")

	if not market_chart:
		print("ERROR: No market_chart available")
		return

	var context = cached_history_data.get("context", {})
	var data_item_id = context.get("type_id", 0)

	print("Loading cached data for item: ", data_item_id)

	# Ensure chart is in the right state for loading
	market_chart.chart_data.is_loading_historical = true
	market_chart.chart_data.has_loaded_historical = false

	var history_entries = cached_history_data.get("data", [])
	print("Cached history entries count: ", history_entries.size())

	if typeof(history_entries) != TYPE_ARRAY or history_entries.size() == 0:
		print("No valid cached historical data available")
		market_chart.chart_data.is_loading_historical = false
		market_chart.finish_historical_data_load()
		return

	var current_time = Time.get_unix_time_from_system()
	var max_window_start = current_time - 31536000.0  # 1 year ago
	var points_added = 0

	# Process cached historical entries
	var valid_entries = []
	for entry in history_entries:
		var date_str = entry.get("date", "")
		if date_str.is_empty():
			continue

		var entry_timestamp = parse_eve_date(date_str)
		if entry_timestamp >= max_window_start and entry_timestamp <= current_time:
			valid_entries.append({"timestamp": entry_timestamp, "data": entry})

	# Sort entries by timestamp (oldest first)
	valid_entries.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	print("Processing %d valid cached entries" % valid_entries.size())

	# Add cached data to chart
	for entry_info in valid_entries:
		var entry = entry_info.data
		var day_timestamp = entry_info.timestamp

		var real_avg_price = entry.get("average", 0.0)
		var real_volume = entry.get("volume", 0)
		var real_highest = entry.get("highest", real_avg_price)
		var real_lowest = entry.get("lowest", real_avg_price)

		if real_avg_price > 0:
			# Add to moving average data (for the line)
			market_chart.add_historical_data_point(real_avg_price, real_volume, day_timestamp)

			# Add candlestick data
			market_chart.add_candlestick_data_point(real_avg_price, real_highest, real_lowest, real_avg_price, real_volume, day_timestamp)  # open  # high  # low  # close  # volume  # timestamp
			points_added += 1

	print("Added %d cached data points to chart" % points_added)

	# IMPORTANT: Finish the historical data load first
	market_chart.chart_data.is_loading_historical = false
	market_chart.chart_data.has_loaded_historical = true
	market_chart.finish_historical_data_load()

	# NOW center the chart based on the actual loaded data
	if points_added > 0:
		center_chart_after_data_load()

	print("Cached chart data loading complete")


func center_chart_after_data_load():
	"""Center chart based on the actual historical data that was loaded"""
	if not market_chart or market_chart.chart_data.price_data.size() == 0:
		print("No chart or no data to center on")
		return

	print("=== CENTERING CHART AFTER DATA LOAD ===")

	# Get the actual price range from loaded data
	var min_price = market_chart.chart_data.get_min_price()
	var max_price = market_chart.chart_data.get_max_price()

	print("Data price range: min=%.2f, max=%.2f" % [min_price, max_price])

	if min_price == 0 or max_price == 0 or min_price == max_price:
		print("Invalid price range, using fallback")
		# Use current market prices as fallback
		var max_buy = selected_item_data.get("max_buy", 1000000.0)
		var min_sell = selected_item_data.get("min_sell", 1000000.0)
		if max_buy > 0 and min_sell > 0:
			min_price = max_buy * 0.8
			max_price = min_sell * 1.2
		else:
			min_price = 500000.0
			max_price = 1500000.0

	# Calculate center and range with some padding
	var center_price = (min_price + max_price) / 2.0
	var data_range = max_price - min_price
	var price_range = data_range * 1.2  # Add 20% padding

	print("Calculated center: %.2f, range: %.2f" % [center_price, price_range])

	# Set chart view to show all data with proper padding
	market_chart.chart_center_price = center_price
	market_chart.chart_price_range = price_range

	# Set time to show all historical data
	var current_time = Time.get_unix_time_from_system()
	market_chart.chart_center_time = current_time - (31536000.0 / 2.0)  # Center on 6 months ago

	# Reset zoom to show full range
	market_chart.zoom_level = 1.0

	print("Chart recentered - center_price: %.2f, range: %.2f" % [center_price, price_range])

	# Force redraw
	market_chart.queue_redraw()


func request_chart_data_for_item(item_id: int):
	"""Request chart data for a specific item"""
	last_chart_request_time = Time.get_ticks_msec() / 1000.0
	pending_historical_request = true

	if data_manager:
		var region_id = selected_item_data.get("region_id", 10000002)
		print("Making throttled chart request for item ", item_id)
		data_manager.get_market_history(region_id, item_id)


func queue_chart_request(item_id: int):
	"""Queue a chart request to be made after the minimum interval"""
	queued_item_id = item_id

	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last = current_time - last_chart_request_time
	var wait_time = min_chart_request_interval - time_since_last

	print("Queueing chart request for item ", item_id, " (wait: ", wait_time, " seconds)")

	pending_chart_request_timer = Timer.new()
	pending_chart_request_timer.wait_time = wait_time
	pending_chart_request_timer.one_shot = true
	pending_chart_request_timer.timeout.connect(_on_queued_chart_request_ready)
	add_child(pending_chart_request_timer)
	pending_chart_request_timer.start()


func _on_queued_chart_request_ready():
	"""Handle queued chart request when timer expires"""
	if queued_item_id != -1 and queued_item_id == current_loading_item_id:
		print("Processing queued chart request for item ", queued_item_id)
		request_chart_data_for_item(queued_item_id)
	else:
		print("Queued chart request cancelled (item changed)")

	queued_item_id = -1
	if pending_chart_request_timer:
		pending_chart_request_timer.queue_free()
		pending_chart_request_timer = null


func verify_chart_ready_for_new_item() -> bool:
	"""Verify the chart is properly reset and ready for new data"""
	if not market_chart:
		return false

	var chart_data = market_chart.chart_data

	print("=== CHART STATE VERIFICATION ===")
	print("Price data points: ", chart_data.price_data.size())
	print("Volume data points: ", chart_data.volume_data.size())
	print("Candlestick data points: ", chart_data.candlestick_data.size())
	print("Is loading historical: ", chart_data.is_loading_historical)
	print("Has loaded historical: ", chart_data.has_loaded_historical)

	# Chart should be empty and not in loading state
	var is_ready = chart_data.price_data.size() == 0 and chart_data.volume_data.size() == 0 and chart_data.candlestick_data.size() == 0 and not chart_data.is_loading_historical

	print("Chart ready for new item: ", is_ready)
	print("================================")

	return is_ready


func center_chart_for_new_item(item_data: Dictionary):
	"""Center and zoom the chart appropriately for the new item's price range"""
	if not market_chart:
		return

	print("=== CENTERING CHART FOR NEW ITEM ===")

	var max_buy = item_data.get("max_buy", 0.0)
	var min_sell = item_data.get("min_sell", 0.0)

	# Calculate a reasonable center price
	var center_price: float
	var price_range: float

	if max_buy > 0 and min_sell > 0:
		# Use the midpoint of the spread
		center_price = (max_buy + min_sell) / 2.0
		var spread = min_sell - max_buy
		# Set range to show the spread plus some margin (200% of spread, minimum 10% of center price)
		price_range = max(spread * 2.0, center_price * 0.1)
	elif max_buy > 0:
		# Only buy orders available
		center_price = max_buy
		price_range = max_buy * 0.2  # 20% range around buy price
	elif min_sell > 0:
		# Only sell orders available
		center_price = min_sell
		price_range = min_sell * 0.2  # 20% range around sell price
	else:
		# No price data, use reasonable defaults
		center_price = 1000000.0  # 1M ISK default
		price_range = 500000.0  # 500K ISK range

	print("Chart centering: center_price=%.2f, price_range=%.2f" % [center_price, price_range])

	# Apply the centering to the chart
	market_chart.chart_center_price = center_price
	market_chart.chart_price_range = price_range
	market_chart.chart_center_time = Time.get_unix_time_from_system()

	# Reset zoom to a consistent level for all items
	market_chart.zoom_level = 1.0

	# Force redraw
	market_chart.queue_redraw()

	print("Chart centering complete")


func update_price_labels_with_animation(item_data: Dictionary):
	"""Update price labels with smooth animation for real-time updates"""
	# Get the price container (HBoxContainer with the price labels)
	var price_container = get_node_or_null("ItemInfoPanel").get_child(0).get_child(1)  # Second child is the HBoxContainer

	if price_container:
		var buy_price_label = price_container.get_node_or_null("BuyPriceLabel")
		if buy_price_label:
			var max_buy = item_data.get("max_buy", 0)
			var new_text = "Buy: %s ISK" % format_isk(max_buy)

			if item_data.get("is_realtime", false) and buy_price_label.text != new_text:
				# Flash animation for real-time updates
				var original_color = Color.GREEN
				buy_price_label.add_theme_color_override("font_color", Color.YELLOW)

				var tween = create_tween()
				tween.tween_method(func(color): buy_price_label.add_theme_color_override("font_color", color), Color.YELLOW, original_color, 0.5)

			buy_price_label.text = new_text
			print("Updated buy price label to: ", new_text)
		else:
			print("ERROR: Could not find BuyPriceLabel in price container")

		var sell_price_label = price_container.get_node_or_null("SellPriceLabel")
		if sell_price_label:
			var min_sell = item_data.get("min_sell", 0)
			var new_text = "Sell: %s ISK" % format_isk(min_sell)

			if item_data.get("is_realtime", false) and sell_price_label.text != new_text:
				# Flash animation for real-time updates
				var original_color = Color.RED
				sell_price_label.add_theme_color_override("font_color", Color.YELLOW)

				var tween = create_tween()
				tween.tween_method(func(color): sell_price_label.add_theme_color_override("font_color", color), Color.YELLOW, original_color, 0.5)

			sell_price_label.text = new_text
			print("Updated sell price label to: ", new_text)
		else:
			print("ERROR: Could not find SellPriceLabel in price container")

		var spread_label = price_container.get_node_or_null("SpreadLabel")
		if spread_label:
			var spread = item_data.get("spread", 0)
			var margin = item_data.get("margin", 0)
			spread_label.text = "Spread: %s ISK (%.1f%%)" % [format_isk(spread), margin]
			print("Updated spread label to: ", spread_label.text)
		else:
			print("ERROR: Could not find SpreadLabel in price container")
	else:
		print("ERROR: Could not find price container")


func update_with_realtime_data(realtime_data: Dictionary):
	"""Update panel with fresh real-time data"""
	print("TradingRightPanel: Received real-time data update")

	# Update selected_item_data with new real-time info
	selected_item_data.merge(realtime_data, true)

	# Update header info with new prices (without clearing chart)
	update_item_header(realtime_data)

	# Update chart with new price point (without clearing)
	update_realtime_chart_data(realtime_data)

	# Update order book in LEFT PANEL instead of right panel
	update_left_panel_order_book(realtime_data)

	print("Real-time update complete - chart data preserved")


func update_left_panel_order_book(data: Dictionary):
	"""Update order book in left panel via main scene"""
	# Get reference to main scene
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("update_left_panel_order_book"):
		main_scene.update_left_panel_order_book(data)


func update_realtime_chart_data(data: Dictionary):
	"""Add new data point to real-time chart WITHOUT clearing existing data"""
	if not market_chart:
		print("ERROR: No market_chart available")
		return

	var max_buy = data.get("max_buy", 0.0)
	var min_sell = data.get("min_sell", 0.0)
	var total_buy_volume = data.get("total_buy_volume", 0)
	var total_sell_volume = data.get("total_sell_volume", 0)
	var total_volume = data.get("volume", total_buy_volume + total_sell_volume)
	var buy_orders = data.get("buy_orders", [])
	var sell_orders = data.get("sell_orders", [])

	# Calculate market price for the chart line
	var market_price = 0.0
	if max_buy > 0 and min_sell > 0:
		market_price = (max_buy + min_sell) / 2.0
	elif max_buy > 0:
		market_price = max_buy
	elif min_sell > 0:
		market_price = min_sell

	# Ensure meaningful volume
	if total_volume <= 0:
		total_volume = max(total_buy_volume + total_sell_volume, 1)

	# UPDATE SPREAD DATA FIRST, before adding price point
	if buy_orders.size() > 0 and sell_orders.size() > 0:
		print("Using realistic spread calculation with %d buy orders and %d sell orders" % [buy_orders.size(), sell_orders.size()])
		update_realistic_spread_data(buy_orders, sell_orders)
	elif max_buy > 0 and min_sell > 0:
		print("Fallback to basic spread: buy=%.2f, sell=%.2f" % [max_buy, min_sell])
		market_chart.update_spread_data(max_buy, min_sell)
	else:
		print("No valid spread data available")

	# THEN add the price point
	if market_price > 0:
		var time_label = Time.get_datetime_string_from_system().substr(11, 8)
		print("Adding real-time chart point: price=%.2f, volume=%d (preserving existing data)" % [market_price, total_volume])
		market_chart.add_data_point(market_price, total_volume, time_label)
	else:
		print("No valid market price for real-time update")


func update_realistic_spread_data(buy_orders: Array, sell_orders: Array):
	"""Calculate realistic station trading opportunities in the same region"""
	if not market_chart:
		return

	# Sort orders to ensure we have best prices first
	var sorted_buy_orders = buy_orders.duplicate()
	var sorted_sell_orders = sell_orders.duplicate()
	sorted_buy_orders.sort_custom(func(a, b): return a.get("price", 0) > b.get("price", 0))  # Highest first
	sorted_sell_orders.sort_custom(func(a, b): return a.get("price", 0) < b.get("price", 0))  # Lowest first

	if sorted_buy_orders.size() == 0 or sorted_sell_orders.size() == 0:
		print("Insufficient orders for station trading analysis")
		return

	# STATION TRADING STRATEGY:
	# 1. You place a BUY order slightly higher than current best buy order
	# 2. You place a SELL order slightly lower than current best sell order
	# 3. You profit from the difference (minus taxes/broker fees)

	var current_highest_buy = sorted_buy_orders[0].get("price", 0.0)  # What others are bidding
	var current_lowest_sell = sorted_sell_orders[0].get("price", 0.0)  # What others are asking

	print("Station Trading Analysis:")
	print("  Current highest buy order: %.2f ISK" % current_highest_buy)
	print("  Current lowest sell order: %.2f ISK" % current_lowest_sell)

	# ALWAYS show the actual market spread in the chart (matches market overview)
	market_chart.update_spread_data(current_highest_buy, current_lowest_sell)

	# Check if there's a gap to exploit
	var market_gap = current_lowest_sell - current_highest_buy
	if market_gap <= 0:
		print("  No market gap - orders overlap, no station trading opportunity")
		# Clear trading opportunity data but keep the market spread visible
		market_chart.set_station_trading_data({})
		return

	# Calculate your competitive prices
	var price_increment = market_gap * 0.01  # 1% of the gap, or minimum 0.01 ISK
	price_increment = max(price_increment, 0.01)

	var your_buy_order_price = current_highest_buy + price_increment  # Bid slightly higher
	var your_sell_order_price = current_lowest_sell - price_increment  # Ask slightly lower

	# EVE Online trading fees and taxes (can be reduced with skills/standings)
	var broker_fee_rate = 0.025  # 2.5% broker fee (default, reducible to ~1% with skills)
	var sales_tax_rate = 0.08  # 8% sales tax (reducible to ~1% with skills)
	var transaction_tax_rate = 0.02  # 2% transaction tax (reducible with standings)

	# Calculate total costs and income
	var cost_per_unit = your_buy_order_price * (1 + broker_fee_rate + transaction_tax_rate)
	var income_per_unit = your_sell_order_price * (1 - sales_tax_rate - broker_fee_rate)

	var profit_per_unit = income_per_unit - cost_per_unit
	var profit_margin = (profit_per_unit / cost_per_unit) * 100.0

	print("  Your buy order: %.2f ISK (total cost with fees: %.2f ISK)" % [your_buy_order_price, cost_per_unit])
	print("  Your sell order: %.2f ISK (net income after taxes: %.2f ISK)" % [your_sell_order_price, income_per_unit])
	print("  Profit per unit: %.2f ISK" % profit_per_unit)
	print("  Profit margin: %.2f%%" % profit_margin)

	# Store the station trading opportunity data for tooltips
	if profit_margin > 2.0:  # At least 2% profit to be worth the effort
		print("  ✅ PROFITABLE station trading opportunity!")
		(
			market_chart
			. set_station_trading_data(
				{
					"your_buy_price": your_buy_order_price,
					"your_sell_price": your_sell_order_price,
					"cost_with_fees": cost_per_unit,
					"income_after_taxes": income_per_unit,
					"profit_per_unit": profit_per_unit,
					"profit_margin": profit_margin,
					"market_gap": market_gap,
					"actual_best_buy": current_highest_buy,
					"actual_best_sell": current_lowest_sell,
					# ADD THE ORDER BOOK DATA:
					"buy_orders": sorted_buy_orders,
					"sell_orders": sorted_sell_orders
				}
			)
		)
	else:
		print("  ❌ Not profitable after fees (%.2f%% margin too low)" % profit_margin)
		# Even for unprofitable trades, include order book for volume analysis
		market_chart.set_station_trading_data({"buy_orders": sorted_buy_orders, "sell_orders": sorted_sell_orders})


func update_order_book_realtime(data: Dictionary):
	"""Update order book with real-time order data"""
	if not order_book_list:
		return

	# Clear existing orders
	for child in order_book_list.get_children():
		child.queue_free()

	# Add updated header
	create_order_book_header()

	# Add fresh buy orders (top 10)
	var buy_orders = data.get("buy_orders", [])
	for i in range(min(10, buy_orders.size())):
		create_order_row(buy_orders[i], true)

	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separator", Color.GRAY)
	order_book_list.add_child(separator)

	# Add fresh sell orders (top 10)
	var sell_orders = data.get("sell_orders", [])
	for i in range(min(10, sell_orders.size())):
		create_order_row(sell_orders[i], false)


func update_item_header(item_data: Dictionary):
	print("=== UPDATING ITEM HEADER ===")
	print("Item data keys: ", item_data.keys())
	print("Item name: ", item_data.get("item_name", "N/A"))
	print("Max buy: ", item_data.get("max_buy", "N/A"))
	print("Min sell: ", item_data.get("min_sell", "N/A"))

	# Find the item info panel - try different paths
	var item_info_panel = get_node_or_null("ItemInfoPanel")
	if not item_info_panel:
		print("ItemInfoPanel not found, searching children...")
		for child in get_children():
			print("  Child: ", child.name, " (", child.get_class(), ")")
			if child.name == "ItemInfoPanel":
				item_info_panel = child
				break

	if not item_info_panel:
		print("ERROR: ItemInfoPanel still not found!")
		return

	print("Found ItemInfoPanel: ", item_info_panel.name)

	# Navigate to the VBoxContainer inside the PanelContainer
	var vbox = item_info_panel.get_child(0)  # Should be VBoxContainer
	if not vbox:
		print("ERROR: No VBoxContainer found in ItemInfoPanel")
		return

	print("Found VBoxContainer with ", vbox.get_child_count(), " children")

	# Update item name label (first child)
	var item_name_label = vbox.get_child(0)
	if item_name_label and item_name_label.has_method("set_text"):
		var item_name = item_data.get("item_name", "Unknown Item")
		var item_id = item_data.get("item_id", 0)
		var new_text = "%s (ID: %d)" % [item_name, item_id]
		item_name_label.text = new_text
		print("✓ Updated item name to: ", new_text)
	else:
		print("ERROR: Item name label not found or invalid")

	# Update price container (second child should be HBoxContainer)
	if vbox.get_child_count() > 1:
		var price_container = vbox.get_child(1)
		print("Price container has ", price_container.get_child_count(), " children")

		# Buy price (first child)
		if price_container.get_child_count() > 0:
			var buy_price_label = price_container.get_child(0)
			if buy_price_label and buy_price_label.has_method("set_text"):
				var max_buy = item_data.get("max_buy", 0.0)
				buy_price_label.text = "Buy: %s" % format_isk(max_buy)
				buy_price_label.add_theme_color_override("font_color", Color.GREEN if max_buy > 0 else Color.GRAY)
				print("✓ Updated buy price to: ", buy_price_label.text)

		# Sell price (third child, skipping spacer)
		if price_container.get_child_count() > 2:
			var sell_price_label = price_container.get_child(2)
			if sell_price_label and sell_price_label.has_method("set_text"):
				var min_sell = item_data.get("min_sell", 0.0)
				sell_price_label.text = "Sell: %s" % format_isk(min_sell)
				sell_price_label.add_theme_color_override("font_color", Color.RED if min_sell > 0 else Color.GRAY)
				print("✓ Updated sell price to: ", sell_price_label.text)

		# Spread (fifth child, skipping spacers)
		if price_container.get_child_count() > 4:
			var spread_label = price_container.get_child(4)
			if spread_label and spread_label.has_method("set_text"):
				var spread = item_data.get("spread", 0.0)
				var margin = item_data.get("margin", 0.0)
				spread_label.text = "Spread: %s (%.1f%%)" % [format_isk(spread), margin]

				# Color code based on margin
				if margin > 10:
					spread_label.add_theme_color_override("font_color", Color.GREEN)
				elif margin > 5:
					spread_label.add_theme_color_override("font_color", Color.YELLOW)
				else:
					spread_label.add_theme_color_override("font_color", Color.WHITE)
				print("✓ Updated spread to: ", spread_label.text)

	print("=== HEADER UPDATE COMPLETE ===")


func update_trading_defaults(item_data: Dictionary):
	var price_spinbox = get_node_or_null("TradingPanel/VBoxContainer/HBoxContainer2/PriceSpinBox")
	if price_spinbox:
		var suggested_price = item_data.get("max_buy", 100.0)
		if suggested_price > 0:
			price_spinbox.value = suggested_price

	var quantity_spinbox = get_node_or_null("TradingPanel/VBoxContainer/HBoxContainer/QuantitySpinBox")
	if quantity_spinbox:
		# Set a reasonable default quantity based on item volume
		var volume = item_data.get("volume", 0)
		if volume > 1000:
			quantity_spinbox.value = 10
		elif volume > 100:
			quantity_spinbox.value = 5
		else:
			quantity_spinbox.value = 1


func update_alert_defaults(item_data: Dictionary):
	var alert_price_input = get_node_or_null("AlertPanel/VBoxContainer/HBoxContainer/AlertPriceInput")
	if alert_price_input:
		var current_price = item_data.get("min_sell", item_data.get("max_buy", 100.0))
		if current_price > 0:
			alert_price_input.value = current_price


func update_market_chart(item_data: Dictionary):
	if market_chart:
		var price = item_data.get("max_buy", item_data.get("min_sell", 0))
		var volume = item_data.get("volume", 0)

		if price > 0:
			var timestamp = Time.get_datetime_string_from_system().substr(11, 8)
			market_chart.add_data_point(price, volume, timestamp)

		market_chart.debug_data_status()


func update_order_book(item_data: Dictionary):
	if not order_book_list:
		return

	# Clear existing orders
	for child in order_book_list.get_children():
		child.queue_free()

	# Add header
	var header = HBoxContainer.new()
	order_book_list.add_child(header)

	var price_header = Label.new()
	price_header.text = "Price"
	price_header.custom_minimum_size.x = 80
	price_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(price_header)

	var volume_header = Label.new()
	volume_header.text = "Volume"
	volume_header.custom_minimum_size.x = 60
	volume_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(volume_header)

	var type_header = Label.new()
	type_header.text = "Type"
	type_header.custom_minimum_size.x = 40
	type_header.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(type_header)

	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separator", Color.WHITE)
	order_book_list.add_child(separator)

	# Add buy orders (green) - top 5
	var buy_orders = item_data.get("buy_orders", [])
	# Sort buy orders by price (highest first)
	buy_orders.sort_custom(func(a, b): return a.get("price", 0) > b.get("price", 0))

	for i in range(min(5, buy_orders.size())):
		create_order_row(buy_orders[i], true)

	# Add separator
	var separator2 = HSeparator.new()
	separator2.add_theme_color_override("separator", Color.GRAY)
	order_book_list.add_child(separator2)

	# Add sell orders (red) - top 5
	var sell_orders = item_data.get("sell_orders", [])
	# Sort sell orders by price (lowest first)
	sell_orders.sort_custom(func(a, b): return a.get("price", 0) < b.get("price", 0))

	for i in range(min(5, sell_orders.size())):
		create_order_row(sell_orders[i], false)


func handle_market_data_update(market_data: Dictionary):
	if not selected_item_data.has("item_id"):
		return

	var item_id = selected_item_data.get("item_id", 0)
	var updated_item_data = process_market_data_for_item(market_data, item_id)

	if not updated_item_data.is_empty():
		update_item_display(updated_item_data)


func _on_historical_data_requested():
	"""Handle request for historical data"""
	print("=== HISTORICAL DATA REQUESTED BY CHART ===")

	if not selected_item_data.has("item_id"):
		print("No item selected, finishing without data")
		pending_historical_request = false
		hide_chart_loading_state()
		if market_chart:
			market_chart.finish_historical_data_load()
		return

	if not data_manager:
		print("No data manager available, finishing without data")
		pending_historical_request = false
		hide_chart_loading_state()
		if market_chart:
			market_chart.finish_historical_data_load()
		return

	var item_id = selected_item_data.get("item_id", 0)
	var region_id = selected_item_data.get("region_id", 10000002)

	print("=== REQUESTING HISTORICAL DATA ===")
	print("Item ID: ", item_id)
	print("Region ID: ", region_id)
	print("Current loading item ID: ", current_loading_item_id)

	# Check if this request is still valid (item hasn't changed)
	if item_id != current_loading_item_id:
		print("Item changed during request, cancelling historical data request")
		pending_historical_request = false
		hide_chart_loading_state()
		if market_chart:
			market_chart.finish_historical_data_load()
		return

	# Verify chart is ready
	if not verify_chart_ready_for_new_item():
		print("Chart not ready, forcing reset...")
		if market_chart:
			market_chart.clear_data()
			market_chart.chart_data.is_loading_historical = false
			market_chart.chart_data.has_loaded_historical = false

	print("Making history request for item ", item_id, " in region ", region_id)

	# Mark chart as loading BEFORE making request
	if market_chart:
		market_chart.chart_data.is_loading_historical = true

	# Request market history for the past day
	data_manager.get_market_history(region_id, item_id)


func load_historical_chart_data(history_data: Dictionary):
	"""Load historical market data into the chart as candlesticks - REAL EVE DATA ONLY"""
	print("=== LOADING REAL HISTORICAL CHART DATA AS CANDLESTICKS ===")

	var context = history_data.get("context", {})
	var data_item_id = context.get("type_id", 0)

	print("Historical data received for item: ", data_item_id)
	print("Currently selected item: ", current_loading_item_id)

	# Check if this data is for the currently selected item
	if data_item_id != current_loading_item_id:
		print("Historical data is for different item (", data_item_id, " vs ", current_loading_item_id, "), ignoring")
		return

	# Cache this data for future use
	cache_chart_data(data_item_id, history_data)

	print("Historical data is for correct item, processing...")

	# Mark request as completed
	pending_historical_request = false

	# Hide loading state since we're now loading data
	hide_chart_loading_state()

	if not market_chart:
		print("ERROR: No market_chart available")
		return

	var history_entries = history_data.get("data", [])

	print("History entries count: ", history_entries.size())

	if typeof(history_entries) != TYPE_ARRAY or history_entries.size() == 0:
		print("No valid historical data available")
		market_chart.finish_historical_data_load()
		return

	var current_time = Time.get_unix_time_from_system()
	var max_window_start = current_time - 31536000.0  # 1 year ago
	var points_added = 0

	print("Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))
	print("Max window start (1 year ago): %s" % Time.get_datetime_string_from_unix_time(max_window_start))

	# Process historical entries for both moving average and candlesticks
	var valid_entries = []
	for entry in history_entries:
		var date_str = entry.get("date", "")
		if date_str.is_empty():
			continue

		var entry_timestamp = parse_eve_date(date_str)
		if entry_timestamp >= max_window_start and entry_timestamp <= current_time:
			valid_entries.append({"timestamp": entry_timestamp, "data": entry})

	# Sort entries by timestamp (oldest first)
	valid_entries.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	print("Found %d valid historical entries within 1 year" % valid_entries.size())

	# Create both moving average points AND candlestick data
	for entry_info in valid_entries:
		var entry = entry_info.data
		var day_timestamp = entry_info.timestamp  # 11:00 UTC Eve Time

		# Use REAL data from EVE API
		var real_avg_price = entry.get("average", 0.0)
		var real_volume = entry.get("volume", 0)
		var real_highest = entry.get("highest", real_avg_price)
		var real_lowest = entry.get("lowest", real_avg_price)

		if real_avg_price > 0:
			# Add to moving average data (for the line)
			market_chart.add_historical_data_point(real_avg_price, real_volume, day_timestamp)
			points_added += 1

			# Add candlestick data (OHLC) using the correct function name
			market_chart.add_candlestick_data_point(real_avg_price, real_highest, real_lowest, real_avg_price, real_volume, day_timestamp)  # open (EVE doesn't give us open, use average)  # high  # low  # close (EVE doesn't give us close, use average)  # volume  # timestamp

	print("Added %d historical data points to chart" % points_added)

	# Finish the historical data load
	market_chart.finish_historical_data_load()

	if points_added > 0:
		center_chart_after_data_load()

	print("Historical chart data loading complete")


func parse_eve_date(date_str: String) -> float:
	"""Parse EVE API date format (YYYY-MM-DD) to Unix timestamp at 11:00 UTC"""
	var parts = date_str.split("-")
	if parts.size() != 3:
		print("Invalid date format: ", date_str)
		return 0.0

	var year = int(parts[0])
	var month = int(parts[1])
	var day = int(parts[2])

	# Create a dictionary for the datetime
	var datetime = {"year": year, "month": month, "day": day, "hour": 11, "minute": 0, "second": 0}  # 11:00 UTC (Eve's daily reset time)

	var timestamp = Time.get_unix_time_from_datetime_dict(datetime)

	# Debug the first few dates
	var current_time = Time.get_unix_time_from_system()
	if timestamp > current_time - 86400 * 7:  # If within last week
		print("Parsed date %s -> %s (timestamp: %.0f)" % [date_str, Time.get_datetime_string_from_unix_time(timestamp), timestamp])

	return timestamp


func process_market_data_for_item(market_data: Dictionary, target_item_id: int) -> Dictionary:
	print("=== PROCESSING MARKET DATA FOR ITEM %d ===" % target_item_id)

	var orders = market_data.get("data", [])
	print("Total orders: %d" % orders.size())

	var buy_orders = []
	var sell_orders = []

	for order in orders:
		if order.get("type_id") == target_item_id:
			if order.get("is_buy_order", false):
				buy_orders.append(order)
			else:
				sell_orders.append(order)

	print("Found %d buy orders, %d sell orders for item %d" % [buy_orders.size(), sell_orders.size(), target_item_id])

	# Sort orders
	buy_orders.sort_custom(func(a, b): return a.get("price", 0) > b.get("price", 0))
	sell_orders.sort_custom(func(a, b): return a.get("price", 0) < b.get("price", 0))

	var result = {
		"item_id": target_item_id,
		"buy_orders": buy_orders,
		"sell_orders": sell_orders,
		# ... other existing fields ...
	}

	print("Returning processed data with keys: %s" % result.keys())
	return result


func create_order_row(order: Dictionary, is_buy: bool):
	var row = HBoxContainer.new()
	order_book_list.add_child(row)

	var price_label = Label.new()
	price_label.text = format_isk(order.get("price", 0))
	price_label.custom_minimum_size.x = 80
	price_label.add_theme_color_override("font_color", Color.GREEN if is_buy else Color.RED)
	row.add_child(price_label)

	var volume_label = Label.new()
	volume_label.text = str(order.get("volume", 0))
	volume_label.custom_minimum_size.x = 60
	volume_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(volume_label)

	var type_label = Label.new()
	type_label.text = "BUY" if is_buy else "SELL"
	type_label.custom_minimum_size.x = 40
	type_label.add_theme_color_override("font_color", Color.GREEN if is_buy else Color.RED)
	row.add_child(type_label)


func _update_real_time_data():
	if selected_item_data.has("item_id") and data_manager:
		var item_id = selected_item_data.get("item_id", 0)
		var region_id = selected_item_data.get("region_id", 10000002)
		data_manager.get_market_orders(region_id, item_id)


func _on_buy_button_pressed():
	create_trade_order(true)


func _on_sell_button_pressed():
	create_trade_order(false)


func create_trade_order(is_buy: bool):
	var quantity_spinbox = get_node("TradingPanel/VBoxContainer/HBoxContainer/QuantitySpinBox")
	var price_spinbox = get_node("TradingPanel/VBoxContainer/HBoxContainer2/PriceSpinBox")

	if not quantity_spinbox or not price_spinbox:
		print("Error: Could not find trading input controls")
		return

	var order_data = {
		"item_id": selected_item_data.get("item_id", 0),
		"item_name": selected_item_data.get("item_name", "Unknown"),
		"is_buy": is_buy,
		"quantity": int(quantity_spinbox.value),
		"price": price_spinbox.value,
		"total_value": quantity_spinbox.value * price_spinbox.value
	}

	emit_signal("order_placed", order_data)

	# Show confirmation
	print("Order created: ", "BUY" if is_buy else "SELL", " ", order_data.quantity, "x ", order_data.item_name, " @ ", order_data.price, " ISK")


func _on_create_alert_pressed():
	var alert_price_input = get_node("AlertPanel/VBoxContainer/HBoxContainer/AlertPriceInput")
	var condition_selector = get_node("AlertPanel/VBoxContainer/HBoxContainer/ConditionSelector")

	if not alert_price_input or not condition_selector or not selected_item_data.has("item_id"):
		print("Error: Could not find alert input controls or no item selected")
		return

	var condition_text = "above" if condition_selector.selected == 0 else "below"

	var alert_data = {
		"item_id": selected_item_data.get("item_id", 0), "item_name": selected_item_data.get("item_name", "Unknown"), "target_price": alert_price_input.value, "condition": condition_text
	}

	emit_signal("alert_created", alert_data)
	print("Alert created for ", alert_data.item_name, " at ", alert_data.target_price, " ISK (", condition_text, ")")


func cache_chart_data(item_id: int, history_data: Dictionary):
	"""Cache historical chart data for an item"""
	var cache_entry = {"data": history_data, "timestamp": Time.get_ticks_msec() / 1000.0, "item_id": item_id}
	chart_data_cache[item_id] = cache_entry
	print("Cached chart data for item ", item_id)


func get_cached_chart_data(item_id: int) -> Dictionary:
	"""Get cached chart data if available and not too old"""
	if not chart_data_cache.has(item_id):
		return {}

	var cache_entry = chart_data_cache[item_id]
	var current_time = Time.get_ticks_msec() / 1000.0
	var cache_age = current_time - cache_entry.timestamp

	# Cache is valid for 5 minutes
	if cache_age < 300.0:
		print("Using cached chart data for item ", item_id, " (age: ", cache_age, " seconds)")
		return cache_entry.data
	else:
		print("Cached data for item ", item_id, " is too old (", cache_age, " seconds)")
		chart_data_cache.erase(item_id)
		return {}


func should_request_chart_data(item_id: int) -> bool:
	"""Check if we should request chart data or wait"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last_request = current_time - last_chart_request_time

	# Check if we have cached data
	if not get_cached_chart_data(item_id).is_empty():
		return false

	# Check if enough time has passed since last request
	if time_since_last_request < min_chart_request_interval:
		print("Too soon to request chart data (", time_since_last_request, " seconds since last)")
		return false

	return true


func format_isk(value: float) -> String:
	if value >= 1000000000:
		return "%.2fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.2fK" % (value / 1000.0)
	return "%.2f" % value


func debug_node_structure(node: Node, indent: String = ""):
	print(indent, node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		debug_node_structure(child, indent + "  ")


func cleanup_previous_item_requests():
	"""Clean up any pending requests or loading states from previous items"""
	pending_historical_request = false
	hide_chart_loading_state()

	# Reset current item tracking
	current_loading_item_id = -1


func force_cleanup_loading_state():
	"""Force cleanup of all loading states - emergency reset"""
	print("=== FORCE CLEANUP LOADING STATE ===")

	pending_historical_request = false
	current_loading_item_id = -1

	hide_chart_loading_state()

	# Force chart out of loading state
	if market_chart and market_chart.chart_data.is_loading_historical:
		market_chart.chart_data.is_loading_historical = false
		market_chart.finish_historical_data_load()

	# Remove all timeout timers
	for child in get_children():
		if child is Timer:
			child.queue_free()

	print("Force cleanup complete")


func force_reset_all_state():
	"""Emergency reset of ALL loading state and timers"""
	print("=== FORCE RESET ALL STATE ===")

	# Reset all tracking variables
	pending_historical_request = false
	current_loading_item_id = -1

	# Force cleanup all loading panels
	force_cleanup_all_loading_panels()

	# Remove ALL timers (fallback timers can accumulate)
	var timers_to_remove = []
	for child in get_children():
		if child is Timer:
			timers_to_remove.append(child)

	for timer in timers_to_remove:
		print("Removing timer: ", timer.name)
		remove_child(timer)
		timer.queue_free()

	# Force chart out of any loading state
	if market_chart:
		market_chart.chart_data.is_loading_historical = false
		market_chart.chart_data.has_loaded_historical = false
		market_chart.clear_data()
		print("Chart forcibly reset")

	# Cancel ALL pending history requests in DataManager
	if data_manager:
		# Clear all pending requests
		for item_id in data_manager.pending_history_requests.keys():
			print("Force cancelling pending request for item: ", item_id)
		data_manager.pending_history_requests.clear()

	print("Force reset complete")


func force_cleanup_all_loading_panels():
	"""Emergency cleanup of ALL loading panels and timers"""
	print("=== FORCE CLEANUP ALL LOADING PANELS ===")

	pending_historical_request = false
	current_loading_item_id = -1

	var chart_panel = get_node_or_null("ChartPanel")
	if chart_panel:
		# Remove ALL children that look like loading panels
		var children_to_remove = []
		for child in chart_panel.get_children():
			if child.name.begins_with("ChartLoadingOverlay") or child.name.contains("Loading"):
				children_to_remove.append(child)

		for child in children_to_remove:
			print("Force removing: ", child.name)
			chart_panel.remove_child(child)
			child.queue_free()

	# Remove ALL timeout timers
	var timers_to_remove = []
	for child in get_children():
		if child is Timer:
			timers_to_remove.append(child)

	for timer in timers_to_remove:
		print("Force removing timer: ", timer.name)
		remove_child(timer)
		timer.queue_free()

	# Force chart out of loading state
	if market_chart and market_chart.chart_data.is_loading_historical:
		market_chart.chart_data.is_loading_historical = false
		market_chart.finish_historical_data_load()

	print("Force cleanup complete")
