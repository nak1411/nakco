# scripts/ui/panels/TradingRightPanel.gd
class_name TradingRightPanel
extends VBoxContainer

signal order_placed(order_data: Dictionary)
signal alert_created(alert_data: Dictionary)

var selected_item_data: Dictionary = {}
var current_market_data: Dictionary = {}
var current_character_data: Dictionary = {}
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
var cache_status_label: Label
var cache_status_timer: Timer
var pending_chart_update: bool = false
var chart_update_timer: Timer

@onready var data_manager: DataManager


func _ready():
	setup_panels()
	setup_chart_update_optimization()
	call_deferred("debug_profit_calculations")


func setup_panels():
	# Clear existing content
	for child in get_children():
		child.queue_free()

	# Set the VBoxContainer to fill and expand
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	# 1. Item Info Header (fixed height)
	create_item_info_header()

	# 2. Real-time Price Chart (expandable)
	create_market_chart()


func setup_chart_update_optimization():
	"""Setup optimized chart updating"""
	chart_update_timer = Timer.new()
	chart_update_timer.wait_time = 0.1  # Batch updates every 100ms
	chart_update_timer.one_shot = true
	chart_update_timer.timeout.connect(_process_pending_chart_update)
	add_child(chart_update_timer)


func _process_pending_chart_update():
	"""Process batched chart update"""
	if pending_chart_update and market_chart:
		market_chart.queue_redraw()
		pending_chart_update = false


func batch_chart_update():
	"""Request a batched chart update instead of immediate"""
	if not pending_chart_update:
		pending_chart_update = true
		chart_update_timer.start()


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
	header_panel.custom_minimum_size.y = 40  # Slightly taller for better info display
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
	chart_panel.custom_minimum_size.y = 300
	chart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(chart_panel)

	var chart_vbox = VBoxContainer.new()
	chart_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart_vbox.add_theme_constant_override("separation", 0)
	chart_panel.add_child(chart_vbox)

	# Just add the market chart directly
	market_chart = MarketChart.new()
	market_chart.name = "MarketChart"
	market_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	market_chart.historical_data_requested.connect(_on_historical_data_requested)
	market_chart.tooltip_text = ""
	market_chart.mouse_filter = Control.MOUSE_FILTER_PASS

	chart_vbox.add_child(market_chart)

	# Add the control buttons directly to the chart as child controls
	_add_chart_overlay_controls()

	chart_panel.resized.connect(_on_chart_panel_resized)
	market_chart.resized.connect(_on_chart_resized)

	return chart_panel


func _add_chart_overlay_controls():
	"""Add control buttons as overlays on the chart itself"""

	# Create background panel for the buttons
	var controls_background = PanelContainer.new()
	controls_background.name = "ControlsBackground"
	controls_background.z_index = 99  # Behind the buttons but above chart

	# Style the background panel
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.75)  # Dark semi-transparent background
	bg_style.border_width_left = 0
	bg_style.border_width_right = 1
	bg_style.border_width_top = 0
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	controls_background.add_theme_stylebox_override("panel", bg_style)

	# Position and size the background (will be adjusted dynamically)
	controls_background.position = Vector2(195, 5)  # Slightly larger than button area
	controls_background.custom_minimum_size = Vector2(160, 30)  # Width to cover both buttons

	market_chart.add_child(controls_background)

	# Analysis Tools Menu
	analysis_tools_menu = MenuButton.new()
	analysis_tools_menu.name = "AnalysisToolsMenu"
	analysis_tools_menu.text = "Analysis Tools"
	analysis_tools_menu.custom_minimum_size = Vector2(120, 0)
	analysis_tools_menu.position = Vector2(200, 10)
	analysis_tools_menu.z_index = 100  # Above background\
	analysis_tools_menu.alignment = HORIZONTAL_ALIGNMENT_LEFT

	_style_overlay_button(analysis_tools_menu)

	var analysis_popup = analysis_tools_menu.get_popup()
	analysis_popup.add_check_item("Spread Analysis")
	analysis_popup.add_check_item("S/R Analysis")
	analysis_popup.add_check_item("Donchian Channel")
	analysis_popup.id_pressed.connect(_on_analysis_menu_selected)
	analysis_popup.popup_hide.connect(func(): pass)
	analysis_popup.visibility_changed.connect(
		func():
			if analysis_popup.visible:
				var button_rect = analysis_tools_menu.get_global_rect()
				analysis_popup.position = Vector2i(button_rect.position.x, button_rect.position.y + button_rect.size.y + 7)
	)

	_style_popup_menu(analysis_popup)

	market_chart.add_child(analysis_tools_menu)

	# Chart Display Menu
	chart_display_menu = MenuButton.new()
	chart_display_menu.name = "ChartDisplayMenu"
	chart_display_menu.text = "Chart Display"
	chart_display_menu.custom_minimum_size = Vector2(120, 0)
	chart_display_menu.position = Vector2(330, 10)
	chart_display_menu.z_index = 100  # Above background
	chart_display_menu.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_overlay_button(chart_display_menu)

	var display_popup = chart_display_menu.get_popup()
	display_popup.add_check_item("Candlesticks")
	display_popup.add_check_item("Data Points")
	display_popup.add_check_item("MA Line")
	display_popup.popup_hide.connect(func(): pass)
	display_popup.visibility_changed.connect(
		func():
			if display_popup.visible:
				var button_rect = chart_display_menu.get_global_rect()
				display_popup.position = Vector2i(button_rect.position.x, button_rect.position.y + button_rect.size.y + 7)
	)
	display_popup.id_pressed.connect(_on_chart_display_menu_selected)

	_style_popup_menu(display_popup)

	market_chart.add_child(chart_display_menu)

	# Cache status label (top-right)
	cache_status_label = Label.new()
	cache_status_label.name = "CacheStatusLabel"
	cache_status_label.custom_minimum_size = Vector2(200, 0)
	cache_status_label.add_theme_font_size_override("font_size", 10)
	cache_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	cache_status_label.text = "📊 Ready for data"
	cache_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cache_status_label.z_index = 100

	market_chart.add_child(cache_status_label)

	# Connect resize to reposition controls
	market_chart.resized.connect(_on_chart_resized_reposition_controls)

	# Set initial checkbox states
	_update_menu_states()


func _style_popup_menu(popup: PopupMenu):
	"""Style popup menus to match the dark theme with no radius"""

	# Background panel style
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.18, 0.2, 0.25, 1.0)  # Same as your button background
	popup_style.border_width_left = 1
	popup_style.border_width_right = 1
	popup_style.border_width_top = 1
	popup_style.border_width_bottom = 1
	popup_style.border_color = Color(0.35, 0.4, 0.45, 1.0)  # Same as button border
	popup_style.content_margin_left = 4
	popup_style.content_margin_right = 4
	popup_style.content_margin_top = 4
	popup_style.content_margin_bottom = 4

	# Hover style for menu items
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.28, 0.33, 1.0)  # Same as button hover

	# Apply styles to popup
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.add_theme_stylebox_override("hover", hover_style)

	# Text colors to match theme
	popup.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1))
	popup.add_theme_color_override("font_hover_color", Color(0.95, 0.98, 1, 1))
	popup.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1))

	# Font size
	popup.add_theme_font_size_override("font_size", 11)

	# Separator color
	popup.add_theme_color_override("separator_color", Color(0.4, 0.4, 0.5, 0.8))


func _style_overlay_button(menu_button: MenuButton):
	"""Style buttons for chart overlay with transparency"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.1, 0.15, 0.8)  # Semi-transparent
	style_normal.content_margin_left = 6
	style_normal.content_margin_top = 2
	style_normal.content_margin_right = 6
	style_normal.content_margin_bottom = 2
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.4, 0.4, 0.5, 0.6)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style_hover.content_margin_left = 6
	style_hover.content_margin_top = 2
	style_hover.content_margin_right = 6
	style_hover.content_margin_bottom = 2
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.5, 0.5, 0.6, 0.8)

	menu_button.add_theme_stylebox_override("normal", style_normal)
	menu_button.add_theme_stylebox_override("hover", style_hover)
	menu_button.add_theme_stylebox_override("pressed", style_hover)
	menu_button.add_theme_font_size_override("font_size", 10)


func create_cache_status_label(parent: VBoxContainer):
	"""Create the cache status label"""
	var status_container = HBoxContainer.new()
	status_container.custom_minimum_size.y = 0
	parent.add_child(status_container)

	# Spacer to push label to the right
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_container.add_child(spacer)

	# Cache status label with wider minimum size
	cache_status_label = Label.new()
	cache_status_label.name = "CacheStatusLabel"
	cache_status_label.custom_minimum_size = Vector2(350, 0)  # Even wider
	cache_status_label.add_theme_font_size_override("font_size", 10)
	cache_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	cache_status_label.text = "📊 Ready for data"
	cache_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cache_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	cache_status_label.clip_contents = false
	status_container.add_child(cache_status_label)

	# Remove old timer if exists
	if cache_status_timer:
		cache_status_timer.queue_free()

	# Create new timer
	cache_status_timer = Timer.new()
	cache_status_timer.name = "CacheStatusTimer"
	cache_status_timer.wait_time = 1.0
	cache_status_timer.timeout.connect(_update_cache_status_display)
	add_child(cache_status_timer)
	cache_status_timer.start()

	print("Cache status timer created and started - should call update every second")

	# Test the update immediately
	update_cache_status_display()


func create_chart_controls():
	"""Create chart control dropdowns with proper checkboxes and styling"""
	var controls_container = HBoxContainer.new()
	controls_container.name = "ChartControls"
	controls_container.alignment = BoxContainer.ALIGNMENT_BEGIN  # Center the controls
	controls_container.custom_minimum_size.y = 0  # Give more height for better appearance

	# Analysis Tools Menu
	analysis_tools_menu = MenuButton.new()
	analysis_tools_menu.name = "AnalysisToolsMenu"
	analysis_tools_menu.text = "Analysis Tools..."
	analysis_tools_menu.custom_minimum_size = Vector2(180, 0)
	analysis_tools_menu.position = Vector2(market_chart.size.x - 280, 10)

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
	chart_display_menu.custom_minimum_size = Vector2(180, 0)
	chart_display_menu.position = Vector2(market_chart.size.x - 150, 10)

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
	style_normal.content_margin_top = 0
	style_normal.content_margin_right = 8
	style_normal.content_margin_bottom = 0
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.35, 0.4, 0.45, 1.0)  # Updated border color

	# Create custom StyleBox for hover state
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.25, 0.28, 0.33, 1.0)  # Updated color
	style_hover.content_margin_left = 8
	style_hover.content_margin_top = 0
	style_hover.content_margin_right = 8
	style_hover.content_margin_bottom = 0
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.45, 0.5, 0.55, 1.0)  # Updated border color

	# Create custom StyleBox for pressed state
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.12, 0.15, 0.18, 1.0)  # Updated color
	style_pressed.content_margin_left = 8
	style_pressed.content_margin_top = 0
	style_pressed.content_margin_right = 8
	style_pressed.content_margin_bottom = 0
	style_pressed.border_width_left = 1
	style_pressed.border_width_right = 1
	style_pressed.border_width_top = 1
	style_pressed.border_width_bottom = 1
	style_pressed.border_color = Color(0.55, 0.6, 0.65, 1.0)  # Updated border color

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


func update_cache_status_display():
	"""Update the cache status label - main function"""
	if not cache_status_label:
		return

	if current_loading_item_id == -1:
		cache_status_label.text = "📊 No item selected"
		return

	print("Updating cache status for item: ", current_loading_item_id)

	# Check if current item has cached data
	if chart_data_cache.has(current_loading_item_id):
		var cache_entry = chart_data_cache[current_loading_item_id]
		var cache_timestamp = cache_entry.timestamp
		var current_time = Time.get_ticks_msec() / 1000.0
		var cache_age = current_time - cache_timestamp
		var cache_duration = 300.0  # 5 minutes
		var time_until_refresh = cache_duration - cache_age

		print("Cache found - age: %.1f seconds, time until refresh: %.1f seconds" % [cache_age, time_until_refresh])

		if time_until_refresh > 0:
			# Data is cached and still valid
			var age_minutes = int(cache_age / 60)
			var age_seconds = int(cache_age) % 60
			var refresh_minutes = int(time_until_refresh / 60)
			var refresh_seconds = int(time_until_refresh) % 60

			# Use compact format
			var status_text = "📊 Cached %02d:%02d | Refresh %02d:%02d" % [age_minutes, age_seconds, refresh_minutes, refresh_seconds]

			print("Setting cache status text: '", status_text, "'")
			cache_status_label.text = status_text
			cache_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 0.9))  # Light green
		else:
			# Cache expired
			print("Cache expired")
			cache_status_label.text = "📊 Cache expired - will refresh on next request"
			cache_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.6, 0.9))  # Light red
	else:
		# No cached data
		print("No cached data found")
		if pending_historical_request:
			cache_status_label.text = "📡 Loading fresh data..."
			cache_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8, 0.9))  # Light blue
		else:
			cache_status_label.text = "📊 Live data"
			cache_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6, 0.9))  # Light yellow


func set_character_data(character_data: Dictionary):
	"""Update character data and refresh spread calculations"""
	print("TradingRightPanel: Setting character data: ", character_data.keys())
	var previous_character_data = current_character_data.duplicate()
	current_character_data = character_data

	var skills_changed = _skills_have_changed(previous_character_data.get("skills", {}), character_data.get("skills", {}))

	if skills_changed:
		print("Character skills changed - refreshing all spread calculations")

		# Show visual feedback
		var has_skills_now = not character_data.get("skills", {}).is_empty()
		_show_skill_change_feedback(has_skills_now)

		_refresh_all_spread_calculations()
	else:
		print("Character data updated but skills unchanged")


func _skills_have_changed(old_skills: Dictionary, new_skills: Dictionary) -> bool:
	"""Check if trading-relevant skills have changed"""
	var trading_skills = ["broker_relations", "accounting", "trade", "retail", "marketing"]

	for skill in trading_skills:
		var old_level = old_skills.get(skill, 0)
		var new_level = new_skills.get(skill, 0)
		if old_level != new_level:
			print("Skill change detected: %s %d -> %d" % [skill, old_level, new_level])
			return true

	# Also check if we went from no skills to having skills (login) or vice versa (logout)
	var had_skills = not old_skills.is_empty()
	var has_skills = not new_skills.is_empty()

	if had_skills != has_skills:
		print("Character login state changed: had_skills=%s, has_skills=%s" % [had_skills, has_skills])
		return true

	return false


func _refresh_all_spread_calculations():
	"""Refresh all spread and profit calculations with current character skills"""
	print("=== REFRESHING SPREAD CALCULATIONS ===")

	# Only refresh if we have current market data to work with
	if selected_item_data.is_empty():
		print("No current item data to refresh")
		return

	var buy_orders = selected_item_data.get("buy_orders", [])
	var sell_orders = selected_item_data.get("sell_orders", [])

	if buy_orders.is_empty() or sell_orders.is_empty():
		print("No order data to refresh")
		return

	print("Refreshing calculations for item: %s" % selected_item_data.get("item_name", "Unknown"))

	# Immediately update spread analysis with new character skills
	update_realistic_spread_data(buy_orders, sell_orders)

	# Update the item header to show new profit calculations
	_refresh_item_header_calculations()

	# Force chart redraw to show updated spread analysis
	if market_chart:
		market_chart.queue_redraw()

	print("=== SPREAD CALCULATIONS REFRESHED ===")


func _refresh_item_header_calculations():
	"""Refresh the profit calculations shown in the item header"""
	if selected_item_data.is_empty():
		return

	# Recalculate spread and margin with current character skills
	var max_buy = selected_item_data.get("max_buy", 0.0)
	var min_sell = selected_item_data.get("min_sell", 0.0)

	if max_buy > 0 and min_sell > 0:
		# Use ProfitCalculator to get skill-adjusted calculations
		var character_skills = current_character_data.get("skills", {})
		var basic_spread = min_sell - max_buy

		# Calculate what the actual trading profit would be with current skills
		var mock_buy_orders = [{"price": max_buy, "volume": 1}]
		var mock_sell_orders = [{"price": min_sell, "volume": 1}]
		var trading_analysis = ProfitCalculator.calculate_optimal_trading_prices(mock_buy_orders, mock_sell_orders, character_skills)

		var updated_item_data = selected_item_data.duplicate()
		updated_item_data["spread"] = basic_spread

		if not trading_analysis.is_empty():
			# Show the realistic margin accounting for fees and skills
			var realistic_margin = trading_analysis.get("profit_margin", 0.0)
			updated_item_data["margin"] = realistic_margin
			updated_item_data["skill_adjusted"] = true
		else:
			# Fallback to basic calculation
			updated_item_data["margin"] = (basic_spread / max_buy) * 100.0 if max_buy > 0 else 0.0
			updated_item_data["skill_adjusted"] = false

		updated_item_data["is_realtime"] = true  # Trigger flash animation

		# Update the header display
		update_item_header(updated_item_data)


func analyze_station_trading_optimized(buy_orders: Array, sell_orders: Array, character_data: Dictionary):
	"""Optimized skill-based station trading analysis"""
	if buy_orders.is_empty() or sell_orders.is_empty():
		if market_chart:
			market_chart.set_station_trading_data({})
		return

	# Defer heavy calculation to next frame to avoid blocking
	call_deferred("_perform_trading_analysis", buy_orders, sell_orders, character_data)


func _perform_trading_analysis(buy_orders: Array, sell_orders: Array, character_data: Dictionary):
	"""Perform the actual analysis on deferred frame"""
	print("=== SKILL-BASED STATION TRADING ANALYSIS (OPTIMIZED) ===")

	var character_skills = character_data.get("skills", {})
	var trading_analysis = ProfitCalculator.calculate_optimal_trading_prices(buy_orders, sell_orders, character_skills)

	if trading_analysis.is_empty() or not trading_analysis.get("has_opportunity", false):
		print("  ", trading_analysis.get("reason", "No opportunity found"))
		if market_chart:
			var buy_price = buy_orders[0].get("price", 0.0) if buy_orders.size() > 0 else 0.0
			var sell_price = sell_orders[0].get("price", 0.0) if sell_orders.size() > 0 else 0.0
			market_chart.update_spread_data(buy_price, sell_price)

			# Pass character info even for non-profitable opportunities
			var basic_data = {}
			if not character_data.is_empty():
				basic_data["skill_benefits"] = {
					"broker_relations_level": character_skills.get("broker_relations", 0), "accounting_level": character_skills.get("accounting", 0), "fee_savings_pct": 0.0
				}
			market_chart.set_station_trading_data(basic_data)
		return

	# Update UI with results - Show ALL profitable opportunities (even small ones)
	if market_chart:
		market_chart.update_spread_data(trading_analysis.get("current_highest_buy", 0), trading_analysis.get("current_lowest_sell", 0))

		var fees = trading_analysis.get("fees", {})
		var skill_savings = trading_analysis.get("skill_savings", {})
		var profit_margin = trading_analysis.get("profit_margin", 0)

		# 🔥 FIX: Show ALL positive profit opportunities, regardless of margin size
		print("  ✅ PROFITABLE station trading opportunity!")
		print("  Margin: %.2f%%" % profit_margin)

		# Enhanced station trading data with detailed skill breakdown
		var station_trading_data = {
			"your_buy_price": trading_analysis.get("your_buy_price", 0),
			"your_sell_price": trading_analysis.get("your_sell_price", 0),
			"cost_with_fees": trading_analysis.get("cost_per_unit", 0),
			"income_after_taxes": trading_analysis.get("income_per_unit", 0),
			"profit_per_unit": trading_analysis.get("profit_per_unit", 0),
			"profit_margin": profit_margin,
			"skill_benefits":
			{
				"broker_relations_level": fees.get("broker_relations_level", 0),
				"accounting_level": fees.get("accounting_level", 0),
				"fee_savings_pct": skill_savings.get("total_fee_savings_pct", 0),
				"current_broker_fee": fees.get("broker_fee_rate", 0.025) * 100,
				"current_sales_tax": fees.get("sales_tax_rate", 0.08) * 100,
				"broker_savings": skill_savings.get("broker_fee_savings_pct", 0),
				"sales_tax_savings": skill_savings.get("sales_tax_savings_pct", 0)
			}
		}
		market_chart.set_station_trading_data(station_trading_data)

		# 🔥 NEW: Update the item header to show skill-adjusted results
		if not selected_item_data.is_empty():
			var updated_item_data = selected_item_data.duplicate()
			updated_item_data["margin"] = profit_margin
			updated_item_data["skill_adjusted"] = true  # Mark as skill-adjusted
			updated_item_data["spread"] = trading_analysis.get("profit_per_unit", 0)  # Use actual profit as spread
			update_item_header(updated_item_data)


# Remove the old _update_cache_status_display function and replace it
func _update_cache_status_display():
	"""Timer callback - just calls the main function"""
	update_cache_status_display()


func hide_cache_status():
	"""Hide cache status when no item is selected"""
	if cache_status_label:
		cache_status_label.text = ""


func _on_chart_resized_reposition_controls():
	"""Reposition overlay controls when chart is resized"""
	if market_chart:
		var controls_bg = market_chart.get_node_or_null("ControlsBackground")

		if analysis_tools_menu:
			analysis_tools_menu.position = Vector2(50, 8)
		if chart_display_menu:
			chart_display_menu.position = Vector2(140, 8)
		if controls_bg:
			# Position background to cover both buttons with padding
			controls_bg.position = Vector2(50, 0)
			controls_bg.custom_minimum_size = Vector2(160, 10)
		if cache_status_label:
			cache_status_label.position = Vector2(market_chart.size.x - 205, market_chart.size.y - 200)


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
	background.color = Color(0.1, 0.1, 0.1, 1.0)
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


func _show_skill_change_feedback(skills_improved: bool):
	"""Show visual feedback when character skills change calculations"""
	if not market_chart:
		return

	# Create a temporary notification overlay
	var notification = Label.new()
	if skills_improved:
		notification.text = "✅ Trading calculations updated with character skills!"
		notification.add_theme_color_override("font_color", Color.GREEN)
	else:
		notification.text = "⚠️ Trading calculations reverted to default rates"
		notification.add_theme_color_override("font_color", Color.YELLOW)

	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.add_theme_font_size_override("font_size", 16)

	# Position at top of chart
	notification.position = Vector2(market_chart.size.x / 2 - 200, 20)
	notification.size = Vector2(400, 30)
	market_chart.add_child(notification)

	# Animate and remove
	var tween = create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 2.0)
	tween.tween_callback(notification.queue_free)


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

		# Show cache status
		trigger_cache_status_update()

		# Set basic chart data (without centering)
		if market_chart:
			market_chart.set_station_trading_data(item_data)

		# Wait a frame to ensure chart setup is complete
		await get_tree().process_frame

		# Load cached data - centering will happen after data is loaded
		load_cached_chart_data(cached_data)
	else:
		# Show loading status
		trigger_cache_status_update()

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


func trigger_cache_status_update():
	"""Simple function to trigger cache status update"""
	if cache_status_label:
		update_cache_status_display()


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


# Replace in TradingRightPanel.gd
func update_realistic_spread_data(buy_orders: Array, sell_orders: Array):
	"""Calculate realistic station trading opportunities - OPTIMIZED"""
	if not market_chart or buy_orders.is_empty() or sell_orders.is_empty():
		return

	# Use optimized analysis
	analyze_station_trading_optimized(buy_orders, sell_orders, current_character_data)


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
	print("Item name: ", item_data.get("item_name", "N/A"))
	print("Max buy: ", item_data.get("max_buy", "N/A"))
	print("Min sell: ", item_data.get("min_sell", "N/A"))
	print("Skill adjusted: ", item_data.get("skill_adjusted", false))

	# Update item name
	var item_name_label = get_node("ItemInfoPanel").get_child(0).get_child(0)
	if item_name_label:
		var item_name = item_data.get("item_name", "Unknown Item")
		var item_id = item_data.get("item_id", 0)
		item_name_label.text = "✓ Updated item name to: %s (ID: %d)" % [item_name, item_id]
		print("✓ Updated item name to: %s (ID: %d)" % [item_name, item_id])

	# Update prices with skill benefit indicator
	var price_container = get_node("ItemInfoPanel").get_child(0).get_child(1)
	if price_container:
		print("Price container has %d children" % price_container.get_child_count())

		var buy_price_label = price_container.get_node_or_null("BuyPriceLabel")
		if buy_price_label:
			var max_buy = item_data.get("max_buy", 0)
			var new_text = "Buy: %s ISK" % format_isk(max_buy)
			buy_price_label.text = new_text
			print("✓ Updated buy price to: %s" % new_text)

		var sell_price_label = price_container.get_node_or_null("SellPriceLabel")
		if sell_price_label:
			var min_sell = item_data.get("min_sell", 0)
			var new_text = "Sell: %s ISK" % format_isk(min_sell)
			sell_price_label.text = new_text
			print("✓ Updated sell price to: %s" % new_text)

		var spread_label = price_container.get_node_or_null("SpreadLabel")
		if spread_label:
			var spread = item_data.get("spread", 0)
			var margin = item_data.get("margin", 0)
			var is_skill_adjusted = item_data.get("skill_adjusted", false)
			var has_character = not current_character_data.is_empty()

			# Show different text based on character login state
			if has_character and is_skill_adjusted:
				var character_name = current_character_data.get("name", "Character")
				spread_label.text = "Spread: %s ISK (%.1f%% with %s's skills)" % [format_isk(spread), margin, character_name]
				spread_label.add_theme_color_override("font_color", Color.GREEN)  # Green for skill-adjusted
			elif has_character:
				# Character logged in - check if margin is actually profitable
				if margin > 0.0:
					var character_name = current_character_data.get("name", "Character")
					spread_label.text = "Spread: %s ISK (%.1f%% - analyzing with %s's skills)" % [format_isk(spread), margin, character_name]
					spread_label.add_theme_color_override("font_color", Color.YELLOW)  # Yellow for analyzing
				else:
					spread_label.text = "Spread: %s ISK (%.1f%% - no profitable opportunity)" % [format_isk(spread), margin]
					spread_label.add_theme_color_override("font_color", Color.ORANGE)  # Orange for no opportunity
			else:
				spread_label.text = "Spread: %s ISK (%.1f%% - default rates)" % [format_isk(spread), margin]
				spread_label.add_theme_color_override("font_color", Color.GRAY)

			print("✓ Updated spread to: %s" % spread_label.text)

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
	print("Cached chart data for item ", item_id, " at timestamp ", cache_entry.timestamp)

	# Update cache status display immediately
	trigger_cache_status_update()


func get_cached_chart_data(item_id: int) -> Dictionary:
	"""Get cached chart data if available and not too old"""
	if not chart_data_cache.has(item_id):
		return {}

	var cache_entry = chart_data_cache[item_id]
	var current_time = Time.get_ticks_msec() / 1000.0
	var cache_age = current_time - cache_entry.timestamp

	# Cache is valid for 5 minutes (300 seconds)
	if cache_age < 300.0:
		print("Using cached chart data for item ", item_id, " (age: ", cache_age, " seconds)")
		return cache_entry.data

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


func debug_profit_calculations():
	"""Debug function to test profit calculations with various margins"""
	print("=== DEBUGGING PROFIT CALCULATIONS ===")

	var test_cases = [
		{"buy": 1000.0, "sell": 1050.0, "expected_margin": 5.0},  # 5% raw margin
		{"buy": 1000.0, "sell": 1020.0, "expected_margin": 2.0},  # 2% raw margin
		{"buy": 1000.0, "sell": 1010.0, "expected_margin": 1.0},  # 1% raw margin
		{"buy": 1000.0, "sell": 1005.0, "expected_margin": 0.5}  # 0.5% raw margin
	]

	for test_case in test_cases:
		var buy_orders = [{"price": test_case.buy, "volume": 100}]
		var sell_orders = [{"price": test_case.sell, "volume": 100}]
		var skills = {"broker_relations": 3, "accounting": 4}

		var result = ProfitCalculator.calculate_optimal_trading_prices(buy_orders, sell_orders, skills)

		print("Buy: %.0f, Sell: %.0f" % [test_case.buy, test_case.sell])
		print("  Expected margin: %.1f%%" % test_case.expected_margin)
		print("  Actual margin: %.2f%%" % result.get("profit_margin", 0))
		print("  Has opportunity: %s" % result.get("has_opportunity", false))
		print("  Reason: %s" % result.get("reason", "N/A"))
		print("")
