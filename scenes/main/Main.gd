# scenes/main/Main.gd
class_name Main
extends Control

const SpreadsheetGrid = preload("res://scripts/ui/components/SpreadsheetGrid.gd")
const TradingRightPanel = preload("res://scripts/ui/panels/TradingRightPanel.gd")

# Constants
const VERSION = "1.0.0"
const APP_NAME = "EVE Trader"

# Application state
var current_region_id: int = 10000002  # Jita by default
var selected_item_id: int = -1
var is_loading: bool = false

# Core managers
var data_manager: DataManager
var config_manager: ConfigManager
var notification_manager: NotificationManager
var database_manager: DatabaseManager
var market_grid: SpreadsheetGrid

# UI Components
@onready var ui_manager: Control = $UIManager
@onready var menu_bar: MenuBar = $UIManager/MenuBar
@onready var toolbar: HBoxContainer = $UIManager/Toolbar
@onready var main_content: HSplitContainer = $UIManager/MainContent
@onready var status_bar: HBoxContainer = $UIManager/StatusBar

# Toolbar controls
@onready var refresh_button: Button = $UIManager/Toolbar/RefreshButton
@onready var region_selector: OptionButton = $UIManager/Toolbar/RegionSelector
@onready var alerts_button: Button = $UIManager/Toolbar/AlertsButton
@onready var settings_button: Button = $UIManager/Toolbar/SettingsButton

# Main panels
@onready var left_panel: VSplitContainer = $UIManager/MainContent/LeftPanel
@onready var center_panel: TabContainer = $UIManager/MainContent/CenterRightPanel/CenterPanel
@onready var center_right_panel: VSplitContainer = $UIManager/MainContent/CenterRightPanel
@onready var right_panel: VBoxContainer = $UIManager/MainContent/CenterRightPanel/RightPanel

# Search and watchlist
@onready var search_button: Button = $UIManager/MainContent/LeftPanel/SearchWatchlistPanel/SearchPanel/SearchContainer/SearchButton
@onready var item_search: LineEdit = $UIManager/MainContent/LeftPanel/SearchWatchlistPanel/SearchPanel/SearchContainer/ItemSearch
@onready var watchlist_items: VBoxContainer = $UIManager/MainContent/LeftPanel/SearchWatchlistPanel/WatchlistPanel/WatchlistContainer/WatchlistItems

# Status bar elements
@onready var connection_status: Label = $UIManager/StatusBar/ConnectionStatus
@onready var api_status: Label = $UIManager/StatusBar/APIStatus
@onready var last_update: Label = $UIManager/StatusBar/LastUpdate

# Dialogs
@onready var error_dialog: AcceptDialog = $DialogLayer/ErrorDialog
@onready var settings_dialog: AcceptDialog = $DialogLayer/SettingsDialog
@onready var alert_dialog: AcceptDialog = $DialogLayer/AlertDialog


func _ready():
	print("Main scene starting...")

	setup_managers()
	setup_ui()
	setup_signals()
	populate_region_selector()

	apply_theme()

	# Load initial data
	refresh_market_data()

	print("Main scene ready")


func setup_managers():
	# Initialize core managers
	data_manager = DataManager.new()
	config_manager = ConfigManager.new()
	notification_manager = NotificationManager.new()
	database_manager = DatabaseManager.new()

	# Add to scene tree
	add_child(data_manager)
	add_child(config_manager)
	add_child(notification_manager)
	add_child(database_manager)

	# Set cross-references between managers
	notification_manager.config_manager = config_manager

	print("Managers initialized")


func setup_application():
	# Set window properties
	get_window().title = "%s v%s" % [APP_NAME, VERSION]
	get_window().min_size = Vector2i(1200, 800)

	# Setup theme (now that config_manager exists)
	apply_theme()


func setup_ui():
	# Configure toolbar buttons
	refresh_button.text = "Refresh"
	var refresh_icon_path = "res://assets/icons/ui/refresh.svg"
	if FileAccess.file_exists(refresh_icon_path):
		refresh_button.icon = load(refresh_icon_path)

	alerts_button.text = "Alerts"
	var alert_icon_path = "res://assets/icons/ui/alert.svg"
	if FileAccess.file_exists(alert_icon_path):
		alerts_button.icon = load(alert_icon_path)

	settings_button.text = "Settings"
	var settings_icon_path = "res://assets/icons/ui/settings.svg"
	if FileAccess.file_exists(settings_icon_path):
		settings_button.icon = load(settings_icon_path)

	# Setup search button icon
	var search_icon_path = "res://assets/icons/ui/search.svg"
	if FileAccess.file_exists(search_icon_path):
		search_button.icon = load(search_icon_path)
	else:
		search_button.text = "🔍"  # Fallback emoji

	# Setup region selector
	populate_region_selector()

	# Configure search
	item_search.placeholder_text = "Search items..."
	item_search.clear_button_enabled = true

	# Setup tab container
	if center_panel:
		center_panel.tab_alignment = TabBar.ALIGNMENT_LEFT
	else:
		print("ERROR: center_panel is null - check node path")

	# Configure status bar
	connection_status.text = "Connecting..."
	api_status.text = "API: Initializing"
	last_update.text = "Last update: Never"

	# Set panel sizes
	main_content.split_offset = 300  # Left panel width
	left_panel.split_offset = 200  # Search vs watchlist

	# Create market grid
	setup_market_grid()

	setup_status_bar_with_progress()

	setup_right_panel()

	configure_panel_constraints()


func setup_signals():
	# Toolbar signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	alerts_button.pressed.connect(_on_alerts_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	region_selector.item_selected.connect(_on_region_changed)

	# Search signals
	search_button.pressed.connect(_on_search_button_pressed)
	item_search.text_changed.connect(_on_search_text_changed)
	item_search.text_submitted.connect(_on_search_submitted)

	# Data manager signals
	if data_manager:
		data_manager.data_updated.connect(_on_data_updated)
		data_manager.api_error.connect(_on_api_error)

	# Notification manager signals
	if notification_manager:
		notification_manager.notification_triggered.connect(_on_notification)

	# Tab changed signal
	center_panel.tab_changed.connect(_on_tab_changed)

	print("All signals connected successfully")


func setup_left_panel_structure():
	"""Set up the left panel with search, watchlist, and order book"""
	# Current structure from .tscn:
	# LeftPanel (VSplitContainer)
	#   ├── SearchPanel (VBoxContainer)
	#   └── WatchlistPanel (VBoxContainer)

	# We need to change this to:
	# LeftPanel (VSplitContainer)
	#   ├── SearchWatchlistPanel (VBoxContainer with both search and watchlist)
	#   └── OrderBookPanel (VBoxContainer)

	# Get references to existing panels
	var search_panel = left_panel.get_node("SearchPanel")
	var watchlist_panel = left_panel.get_node("WatchlistPanel")

	# Create new top panel to hold both search and watchlist
	var search_watchlist_panel = VBoxContainer.new()
	search_watchlist_panel.name = "SearchWatchlistPanel"

	# Remove existing panels and re-add them to the combined panel
	left_panel.remove_child(search_panel)
	left_panel.remove_child(watchlist_panel)

	search_watchlist_panel.add_child(search_panel)
	search_watchlist_panel.add_child(watchlist_panel)

	# Add the combined panel back to left panel
	left_panel.add_child(search_watchlist_panel)

	# Create order book panel
	create_order_book_panel()

	# Adjust split - give more space to search/watchlist, less to order book
	left_panel.split_offset = 300  # Adjust based on your preference


func create_order_book_panel():
	"""Create order book panel for the left panel"""
	var order_book_panel = VBoxContainer.new()
	order_book_panel.name = "OrderBookPanel"
	left_panel.add_child(order_book_panel)

	# Header
	var header_container = HBoxContainer.new()
	order_book_panel.add_child(header_container)

	var header_label = Label.new()
	header_label.text = "Order Book"
	header_label.add_theme_color_override("font_color", Color.CYAN)
	header_label.add_theme_font_size_override("font_size", 14)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(header_label)

	# Refresh button for order book
	var refresh_orders_button = Button.new()
	refresh_orders_button.text = "↻"
	refresh_orders_button.custom_minimum_size = Vector2(24, 24)
	refresh_orders_button.tooltip_text = "Refresh Orders"
	refresh_orders_button.pressed.connect(_on_refresh_orders_pressed)
	header_container.add_child(refresh_orders_button)

	# Scrollable order list
	var order_scroll = ScrollContainer.new()
	order_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	order_book_panel.add_child(order_scroll)

	var order_book_list = VBoxContainer.new()
	order_book_list.name = "OrderBookList"
	order_scroll.add_child(order_book_list)

	print("Order book panel created in left panel")


func _on_refresh_orders_pressed():
	"""Refresh order book data"""
	if selected_item_id > 0 and data_manager:
		print("Refreshing order book for item: ", selected_item_id)
		data_manager.get_market_orders(current_region_id, selected_item_id)


func update_left_panel_order_book(item_data: Dictionary):
	"""Update the order book in the left panel"""
	var order_book_list = left_panel.get_node_or_null("OrderBookPanel/ScrollContainer/OrderBookList")
	if not order_book_list:
		print("Order book list not found in left panel")
		return

	# Clear existing orders
	for child in order_book_list.get_children():
		child.queue_free()

	# Create header
	create_left_panel_order_book_header(order_book_list)

	# Add buy orders (top 8)
	var buy_orders = item_data.get("buy_orders", [])
	buy_orders.sort_custom(func(a, b): return a.get("price", 0) > b.get("price", 0))

	for i in range(min(8, buy_orders.size())):
		create_left_panel_order_row(order_book_list, buy_orders[i], true)

	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separator", Color.GRAY)
	order_book_list.add_child(separator)

	# Add sell orders (top 8)
	var sell_orders = item_data.get("sell_orders", [])
	sell_orders.sort_custom(func(a, b): return a.get("price", 0) < b.get("price", 0))

	for i in range(min(8, sell_orders.size())):
		create_left_panel_order_row(order_book_list, sell_orders[i], false)


func create_left_panel_order_book_header(parent: VBoxContainer):
	"""Create order book header for left panel"""
	var header = HBoxContainer.new()
	parent.add_child(header)

	var price_header = Label.new()
	price_header.text = "Price"
	price_header.custom_minimum_size.x = 90
	price_header.add_theme_color_override("font_color", Color.CYAN)
	price_header.add_theme_font_size_override("font_size", 10)
	header.add_child(price_header)

	var volume_header = Label.new()
	volume_header.text = "Vol"
	volume_header.custom_minimum_size.x = 50
	volume_header.add_theme_color_override("font_color", Color.CYAN)
	volume_header.add_theme_font_size_override("font_size", 10)
	header.add_child(volume_header)

	var type_header = Label.new()
	type_header.text = "Type"
	type_header.custom_minimum_size.x = 40
	type_header.add_theme_color_override("font_color", Color.CYAN)
	type_header.add_theme_font_size_override("font_size", 10)
	header.add_child(type_header)


func create_left_panel_order_row(parent: VBoxContainer, order: Dictionary, is_buy: bool):
	"""Create order row for left panel (compact format)"""
	var row = HBoxContainer.new()
	parent.add_child(row)

	var price_label = Label.new()
	price_label.text = format_isk_compact(order.get("price", 0))
	price_label.custom_minimum_size.x = 90
	price_label.add_theme_color_override("font_color", Color.GREEN if is_buy else Color.RED)
	price_label.add_theme_font_size_override("font_size", 9)
	row.add_child(price_label)

	var volume_label = Label.new()
	volume_label.text = format_number_compact(order.get("volume", 0))
	volume_label.custom_minimum_size.x = 50
	volume_label.add_theme_color_override("font_color", Color.WHITE)
	volume_label.add_theme_font_size_override("font_size", 9)
	row.add_child(volume_label)

	var type_label = Label.new()
	type_label.text = "BUY" if is_buy else "SELL"
	type_label.custom_minimum_size.x = 40
	type_label.add_theme_color_override("font_color", Color.GREEN if is_buy else Color.RED)
	type_label.add_theme_font_size_override("font_size", 9)
	row.add_child(type_label)


func format_isk_compact(value: float) -> String:
	"""Compact ISK formatting for narrow displays"""
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	elif value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.0fK" % (value / 1000.0)
	else:
		return "%.0f" % value


func format_number_compact(value: int) -> String:
	"""Compact number formatting"""
	if value >= 1000000:
		return "%.0fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.0fK" % (value / 1000.0)
	else:
		return str(value)


func setup_right_panel():
	# Remove existing right panel content
	for child in right_panel.get_children():
		child.queue_free()

	print("Setting up right panel...")

	# Create enhanced trading panel
	var trading_panel = TradingRightPanel.new()
	trading_panel.name = "TradingRightPanel"
	trading_panel.data_manager = data_manager

	# Ensure no tooltips on the panel
	trading_panel.tooltip_text = ""
	trading_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	right_panel.add_child(trading_panel)

	print("Trading panel created and added to right panel")

	# Connect signals
	if trading_panel.has_signal("order_placed"):
		trading_panel.order_placed.connect(_on_trade_order_placed)
	if trading_panel.has_signal("alert_created"):
		trading_panel.alert_created.connect(_on_trade_alert_created)

	return trading_panel


func populate_region_selector():
	if not data_manager:
		return

	var regions = data_manager.get_major_trade_hubs()
	region_selector.clear()

	for region_name in regions.keys():
		region_selector.add_item(region_name)
		region_selector.set_item_metadata(region_selector.get_item_count() - 1, regions[region_name])

	# Select Jita by default
	region_selector.selected = 0


func setup_market_grid():
	print("Setting up Excel-like market grid...")

	var market_overview = center_panel.get_node("MarketOverview")

	# Remove existing grid
	var existing_grid = market_overview.get_node_or_null("MarketGrid")
	if existing_grid:
		existing_grid.queue_free()
		await existing_grid.tree_exited

	# Create new Excel-like market grid
	market_grid = SpreadsheetGrid.new()
	market_grid.name = "ExcelLikeGrid"
	market_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Pass reference to data manager
	market_grid.data_manager = data_manager

	# Set initial region info
	update_market_grid_region_info()

	market_overview.add_child(market_grid)

	# Connect signals
	market_grid.item_selected.connect(_on_market_item_selected)
	market_grid.progress_updated.connect(_on_market_progress_updated)
	market_grid.column_resized.connect(_on_column_resized)

	print("Excel-like market grid setup complete")


func setup_status_bar_with_progress():
	# The status bar already exists, let's add a progress bar to it
	# Find the spacer (Spacer2) and insert progress bar before version
	var spacer = status_bar.get_node("Spacer2")
	var version_label = status_bar.get_node("Version")

	# Create progress bar container
	var progress_container = HBoxContainer.new()
	progress_container.name = "ProgressContainer"
	status_bar.add_child(progress_container)
	status_bar.move_child(progress_container, status_bar.get_child_count() - 2)  # Before version

	# Progress label
	var progress_text = Label.new()
	progress_text.name = "ProgressText"
	progress_text.text = "Ready"
	progress_text.add_theme_font_size_override("font_size", 10)
	progress_container.add_child(progress_text)

	# Separator
	var separator = VSeparator.new()
	progress_container.add_child(separator)

	# Progress bar background
	var progress_bg = ColorRect.new()
	progress_bg.name = "ProgressBG"
	progress_bg.color = Color(0.2, 0.2, 0.2, 1)  # Dark gray
	progress_bg.custom_minimum_size = Vector2(100, 12)
	progress_container.add_child(progress_bg)

	# Progress bar fill
	var progress_fill = ColorRect.new()
	progress_fill.name = "ProgressFill"
	progress_fill.color = Color.YELLOW
	progress_fill.custom_minimum_size = Vector2(0, 18)
	progress_fill.position = Vector2(0, 1)
	progress_fill.anchors_preset = Control.PRESET_LEFT_WIDE
	progress_bg.add_child(progress_fill)

	# Another separator
	var separator2 = VSeparator.new()
	progress_container.add_child(separator2)


func configure_panel_constraints():
	# Set up responsive panel behavior
	main_content.split_offset = 280
	main_content.collapsed = false

	# Set minimum sizes to prevent overlap
	left_panel.custom_minimum_size = Vector2(200, 0)

	# Configure the vertical split for center-right panel
	if center_right_panel:
		center_right_panel.split_offset = 400  # Default height for center panel
		# Connect resize signals for responsive behavior
		center_right_panel.resized.connect(_on_center_right_panel_resized)

	# Set minimum height for chart panel
	if right_panel:
		right_panel.custom_minimum_size = Vector2(0, 200)

	# Connect main splitter resize
	main_content.resized.connect(_on_main_content_resized)


func _on_center_right_panel_resized():
	if not center_right_panel:
		return

	var total_height = center_right_panel.size.y
	var min_chart_height = 200
	var min_center_height = 300

	# Ensure chart panel doesn't get too small
	if center_right_panel.split_offset > (total_height - min_chart_height):
		center_right_panel.split_offset = total_height - min_chart_height

	# Ensure center panel doesn't get too small
	if center_right_panel.split_offset < min_center_height:
		center_right_panel.split_offset = min_center_height


func _on_main_content_resized():
	var total_width = main_content.size.x
	var min_left = 200
	var min_center_right = 600

	# Ensure minimum sizes are respected
	if total_width < (min_left + min_center_right):
		# Force minimum layout
		var left_width = min(main_content.split_offset, min_left)
		main_content.split_offset = left_width


func apply_theme():
	# Ensure config_manager exists before using it
	if not config_manager:
		print("Warning: config_manager not initialized, using default theme")
		apply_fallback_theme()
		return

	# Get theme name from settings
	var theme_name = config_manager.get_setting("ui_theme", "dark")
	var theme_path = config_manager.get_theme_path(theme_name)

	if FileAccess.file_exists(theme_path):
		var custom_theme = load(theme_path)
		if custom_theme:
			theme = custom_theme
			print("Applied theme: ", theme_path)
			return

	print("Theme file not found: ", theme_path, " - using fallback theme")
	apply_fallback_theme()


func apply_fallback_theme():
	# Create a basic dark theme programmatically
	var fallback_theme = Theme.new()

	# Create basic styles
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0.15, 0.15, 0.2, 1)
	button_normal.border_width_left = 1
	button_normal.border_width_top = 1
	button_normal.border_width_right = 1
	button_normal.border_width_bottom = 1
	button_normal.border_color = Color(0.3, 0.3, 0.4, 1)
	button_normal.corner_radius_top_left = 4
	button_normal.corner_radius_top_right = 4
	button_normal.corner_radius_bottom_right = 4
	button_normal.corner_radius_bottom_left = 4

	var button_hover = StyleBoxFlat.new()
	button_hover.bg_color = Color(0.2, 0.2, 0.25, 1)
	button_hover.border_width_left = 1
	button_hover.border_width_top = 1
	button_hover.border_width_right = 1
	button_hover.border_width_bottom = 1
	button_hover.border_color = Color(0.4, 0.4, 0.5, 1)
	button_hover.corner_radius_top_left = 4
	button_hover.corner_radius_top_right = 4
	button_hover.corner_radius_bottom_right = 4
	button_hover.corner_radius_bottom_left = 4

	# Apply styles to theme
	fallback_theme.set_stylebox("normal", "Button", button_normal)
	fallback_theme.set_stylebox("hover", "Button", button_hover)
	fallback_theme.set_color("font_color", "Button", Color(0.85, 0.85, 0.9, 1))
	fallback_theme.set_color("font_color", "Label", Color(0.85, 0.85, 0.9, 1))

	theme = fallback_theme
	print("Applied fallback theme")


func load_initial_data():
	# Load user settings (config_manager should call load_settings in its _ready)

	# Initialize database
	if database_manager:
		database_manager.initialize()

	# Start data refresh
	refresh_market_data()


# Signal Handlers
func _on_refresh_pressed():
	refresh_market_data()


func _on_alerts_pressed():
	alert_dialog.popup_centered()


func _on_settings_pressed():
	settings_dialog.popup_centered()


func _on_region_changed(index: int):
	current_region_id = region_selector.get_item_metadata(index)
	print("Changed to region: ", region_selector.get_item_text(index))

	# Clear the real-time chart when changing regions
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel and trading_panel.market_chart:
		trading_panel.market_chart.clear_data()
		print("Cleared chart data for region change")

	# Stop real-time updates when region changes
	if data_manager:
		data_manager.stop_realtime_updates()

	# Reset selected item
	selected_item_id = -1

	# Update the market grid region info
	update_market_grid_region_info()

	# Refresh market data
	refresh_market_data()


func _on_search_button_pressed():
	var search_text = item_search.text
	if search_text.length() >= 2:
		_on_search_submitted(search_text)


func _on_search_text_changed(new_text: String):
	if new_text.length() >= 3:
		# Trigger search with debounce
		search_items_debounced(new_text)


func _on_search_submitted(text: String):
	if text.length() >= 2 and data_manager:
		data_manager.search_items(text)


func _on_data_updated(data_type: String, data: Dictionary):
	print("=== MAIN DATA UPDATE ===")
	print("Type: ", data_type)

	match data_type:
		"market_orders":
			# Only update the grid - don't interfere with individual selections
			print("Updating main market display")
			update_market_display(data)
		"realtime_item_data":
			# Handle real-time individual item data
			print("Updating real-time item data")
			update_realtime_item_display(data)
		"market_history":
			# Handle historical market data for charts
			print("Updating market history for charts")
			update_chart_with_history(data)
		"item_search":
			update_search_results(data)
		"item_info":
			update_item_details(data)
		"item_name_updated":
			update_item_name_in_display(data)
			update_search_results_names(data)

	# Update status
	last_update.text = "Last update: " + Time.get_datetime_string_from_system()
	api_status.text = "API: Connected"
	connection_status.text = "Connected"


func update_chart_with_history(data: Dictionary):
	"""Handle historical market data for populating charts"""
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel and trading_panel.has_method("load_historical_chart_data"):
		trading_panel.load_historical_chart_data(data)


func _on_api_error(error_message: String):
	print("API Error: ", error_message)
	show_error_dialog("API Error", error_message)

	# Update status
	api_status.text = "API: Error"
	connection_status.text = "Connection issues"


func _on_notification(notification: Dictionary):
	# Handle various notification types
	match notification.get("type", 0):
		NotificationManager.NotificationType.PRICE_ALERT:
			show_price_alert(notification)
		NotificationManager.NotificationType.SYSTEM_ALERT:
			show_system_alert(notification)


func _on_tab_changed(tab_index: int):
	var tab_name = center_panel.get_tab_title(tab_index)
	print("Switched to tab: ", tab_name)

	# Refresh data based on active tab
	match tab_name:
		"Portfolio":
			refresh_portfolio_data()
		"Analytics":
			refresh_analytics_data()


func _on_market_item_selected(item_id: int, item_data: Dictionary):
	print("=== MAIN: ITEM SELECTED ===")
	print("Item ID: ", item_id)
	print("Item data keys: ", item_data.keys())
	print("Item name: ", item_data.get("item_name", "N/A"))
	print("Max buy: ", item_data.get("max_buy", "N/A"))
	print("Min sell: ", item_data.get("min_sell", "N/A"))

	selected_item_id = item_id

	# Clear the real-time chart when selecting a new item
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel and trading_panel.market_chart:
		trading_panel.market_chart.clear_data()
		print("Cleared chart data for new item selection")

	# Start real-time updates for this item
	if data_manager:
		data_manager.start_realtime_updates_for_item(current_region_id, item_id, item_data.get("item_name", "Unknown"))

	# Ensure the item data has all required fields for the trading panel
	var enhanced_item_data = item_data.duplicate()
	enhanced_item_data["region_id"] = current_region_id
	enhanced_item_data["region_name"] = get_current_region_name()
	enhanced_item_data["is_realtime"] = false

	# Make sure we have proper buy/sell order arrays if they're missing
	if not enhanced_item_data.has("buy_orders"):
		enhanced_item_data["buy_orders"] = []
	if not enhanced_item_data.has("sell_orders"):
		enhanced_item_data["sell_orders"] = []

	print("Enhanced item data keys: ", enhanced_item_data.keys())

	# Update enhanced right panel with the COMPLETE data
	if trading_panel:
		trading_panel.update_item_display(enhanced_item_data)
		print("Updated trading panel with enhanced item data")
	else:
		print("ERROR: Trading panel not found!")

	print("=== ITEM SELECTION COMPLETE ===")


func update_watchlist_add_button(item_data: Dictionary):
	var add_button = $UIManager/MainContent/LeftPanel/WatchlistPanel/WatchlistHeader/AddToWatchlistButton
	if add_button:
		var item_name = item_data.get("item_name", "Unknown")
		add_button.tooltip_text = "Add %s to watchlist" % item_name

		# Connect if not already connected
		if not add_button.pressed.is_connected(_on_add_to_watchlist_pressed):
			add_button.pressed.connect(_on_add_to_watchlist_pressed)


func _on_add_to_watchlist_pressed():
	if selected_item_id <= 0:
		show_error_dialog("No Selection", "Please select an item first")
		return

	var item_name = "Item %d" % selected_item_id
	if data_manager:
		item_name = data_manager.get_item_name(selected_item_id)

	# Add to database
	if database_manager:
		var success = database_manager.add_watchlist_item(selected_item_id, item_name, current_region_id)

		if success:
			refresh_watchlist_display()
			show_system_alert({"message": "Added %s to watchlist" % item_name})
		else:
			show_error_dialog("Error", "Failed to add item to watchlist")


func refresh_watchlist_display():
	if not database_manager:
		return

	var watchlist_container = $UIManager/MainContent/LeftPanel/WatchlistPanel/WatchlistContainer/WatchlistItems

	# Clear existing items
	for child in watchlist_container.get_children():
		child.queue_free()

	# Load from database
	var watchlist = database_manager.get_watchlist()

	for item in watchlist:
		create_watchlist_item_display(item, watchlist_container)


func create_watchlist_item_display(item: Dictionary, container: VBoxContainer):
	var item_container = HBoxContainer.new()
	item_container.custom_minimum_size.y = 25

	var name_label = Label.new()
	name_label.text = item.get("item_name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color.WHITE)
	item_container.add_child(name_label)

	var select_button = Button.new()
	select_button.text = "View"
	select_button.custom_minimum_size.x = 40
	var item_id = item.get("item_id", 0)
	select_button.pressed.connect(_on_watchlist_item_selected.bind(item_id))
	item_container.add_child(select_button)

	container.add_child(item_container)


func _on_watchlist_item_selected(item_id: int):
	# Same as search item selected
	_on_search_item_selected(item_id)


func _on_market_progress_updated(named_items: int, total_items: int, total_available: int):
	var region_name = get_current_region_name()
	update_progress_indicator(region_name, named_items, total_items, total_available)


func _on_trade_order_placed(order_data: Dictionary):
	print("Trade order placed: ", order_data)
	# Here you would integrate with EVE's ESI API for actual trading
	# For now, just add to database as a simulated trade
	if database_manager:
		database_manager.add_trade(order_data.item_id, order_data.item_name, "BUY" if order_data.is_buy else "SELL", order_data.quantity, order_data.price, 10000002, 0)  # region_id  # station_id


func _on_trade_alert_created(alert_data: Dictionary):
	print("Trade alert created: ", alert_data)
	if notification_manager:
		notification_manager.create_price_alert(alert_data.item_id, alert_data.item_name, alert_data.target_price, alert_data.condition)


func _on_column_resized(column_index: int, new_width: float):
	print("Column ", column_index, " resized to ", new_width)
	# Save column preferences if needed
	if config_manager:
		config_manager.set_setting("grid_column_%d_width" % column_index, new_width)


# Data Management
func refresh_market_data():
	if is_loading or not data_manager:
		return

	set_loading_state(true)

	# FOR DEBUGGING: Use debug method that only fetches popular items
	if data_manager.has_method("get_debug_market_data"):
		data_manager.get_debug_market_data(current_region_id)
	else:
		# Fallback to normal method
		data_manager.get_market_orders(current_region_id)

	# Re-enable refresh button after delay
	await get_tree().create_timer(2.0).timeout
	set_loading_state(false)


func search_items_debounced(search_text: String):
	# Simple debounce implementation
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(
		func():
			if data_manager:
				data_manager.search_items(search_text)
			timer.queue_free()
	)
	timer.start()


func refresh_portfolio_data():
	# Load portfolio from database
	if database_manager:
		var portfolio_data = database_manager.get_portfolio()
		# Update portfolio display


func refresh_analytics_data():
	# Refresh analytics calculations
	pass


func process_individual_item_orders(orders: Array, type_id: int, context: Dictionary) -> Dictionary:
	"""Process raw order data into structured format for charts"""
	var buy_orders = []
	var sell_orders = []
	var total_buy_volume = 0
	var total_sell_volume = 0
	var max_buy = 0.0
	var min_sell = 999999999.0

	# Sort orders into buy/sell
	for order in orders:
		if typeof(order) != TYPE_DICTIONARY:
			continue

		var price = order.get("price", 0.0)
		var volume = order.get("volume_remain", 0)
		var is_buy = order.get("is_buy_order", false)

		if is_buy:
			buy_orders.append({"price": price, "volume": volume})
			total_buy_volume += volume
			if price > max_buy:
				max_buy = price
		else:
			sell_orders.append({"price": price, "volume": volume})
			total_sell_volume += volume
			if price < min_sell:
				min_sell = price

	# Sort orders by price
	buy_orders.sort_custom(func(a, b): return a.price > b.price)
	sell_orders.sort_custom(func(a, b): return a.price < b.price)

	# Calculate metrics
	var spread = 0.0
	var margin = 0.0
	if max_buy > 0 and min_sell < 999999999.0:
		spread = min_sell - max_buy
		margin = (spread / max_buy) * 100.0 if max_buy > 0 else 0.0

	# Get item name
	var item_name = data_manager.get_item_name(type_id) if data_manager else "Item %d" % type_id

	return {
		"item_id": type_id,
		"item_name": item_name,
		"region_id": context.get("region_id", current_region_id),
		"region_name": context.get("region_name", get_current_region_name()),
		"buy_orders": buy_orders,
		"sell_orders": sell_orders,
		"max_buy": max_buy if max_buy > 0 else 0.0,
		"min_sell": min_sell if min_sell < 999999999.0 else 0.0,
		"spread": spread,
		"margin": margin,
		"total_buy_volume": total_buy_volume,
		"total_sell_volume": total_sell_volume,
		"volume": total_buy_volume + total_sell_volume,
		"timestamp": Time.get_ticks_msec(),
		"is_realtime": true
	}


# UI Updates
func update_market_display(data: Dictionary):
	print("Main: Updating market display...")
	print("Data structure: ", data.keys())

	if data.has("data"):
		print("Market orders count: ", data.data.size())

	if market_grid:
		# Make sure region info is current before updating data
		update_market_grid_region_info()
		market_grid.update_market_data(data)
		print("Market grid updated successfully")
	else:
		print("ERROR: market_grid is null!")


func update_realtime_item_display(data: Dictionary):
	"""Handle real-time data updates for selected item"""
	print("Main: Processing real-time item data...")

	var raw_orders = data.get("data", [])
	var context = data.get("context", {})
	var type_id = context.get("type_id", 0)

	if type_id != selected_item_id:
		print("Real-time data is for different item, ignoring")
		return

	# Process the raw orders into structured data
	var processed_data = process_individual_item_orders(raw_orders, type_id, context)

	# Update the right panel with fresh data - use the real-time update method
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel:
		# Use update_with_realtime_data instead of update_item_display
		trading_panel.update_with_realtime_data(processed_data)
		print("Updated trading panel with real-time data (chart preserved)")


func update_market_grid_region_info():
	if market_grid:
		var region_name = get_current_region_name()
		market_grid.set_region_info(current_region_id, region_name)

		# Also update the progress indicator
		update_progress_indicator(region_name, 0, 0, 0)


func update_item_name_in_display(data: Dictionary):
	var type_id = data.get("type_id", 0)
	var name = data.get("name", "Unknown")

	# print("Updating item name: ", type_id, " -> ", name)

	if market_grid:
		market_grid.update_item_name(type_id, name)


func update_charts(_data: Dictionary):
	# Update price/volume charts
	print("Updating charts with: ", _data.keys())


func update_search_results(data: Dictionary):
	var search_results_container = get_search_results_container()

	# Clear previous results
	for child in search_results_container.get_children():
		child.queue_free()

	var search_data = data.get("data", {})

	if search_data.has("inventory_type"):
		var items = search_data.inventory_type
		print("Found ", items.size(), " search results")

		# Limit to first 15 results for performance
		for i in range(min(15, items.size())):
			var item_id = items[i]
			add_search_result_item(item_id)
	else:
		# Show "no results" message
		var no_results = Label.new()
		no_results.text = "No items found"
		no_results.add_theme_color_override("font_color", Color.YELLOW)
		search_results_container.add_child(no_results)


func update_item_details_panel(item_data: Dictionary):
	var details_content = right_panel.get_node("TradeDetailsPanel/TradeDetailsContainer/TradeDetailsContent")
	var info_label = details_content.get_node("ItemInfoLabel")

	var details_text = (
		"""Item: %s (ID: %d)
Best Buy: %s ISK
Best Sell: %s ISK
Spread: %s ISK
Margin: %.2f%%
Volume: %s

Click to get detailed orders for this item."""
		% [
			item_data.get("item_name", "Unknown"),
			item_data.get("item_id", 0),
			format_isk(item_data.get("max_buy", 0)),
			format_isk(item_data.get("min_sell", 0)),
			format_isk(item_data.get("spread", 0)),
			item_data.get("margin", 0),
			format_number(item_data.get("volume", 0))
		]
	)

	info_label.text = details_text


func update_progress_indicator(region_name: String, named_items: int, total_items: int, total_available: int):
	var percentage = (named_items * 100) / total_items if total_items > 0 else 0

	# Update existing status bar text elements
	connection_status.text = "Connected - %s" % region_name

	if total_items > 0:
		api_status.text = "Loading names: %d/%d (%d%%)" % [named_items, total_items, percentage]

		# Color code the API status
		if percentage == 100:
			api_status.add_theme_color_override("font_color", Color.GREEN)
		elif percentage > 50:
			api_status.add_theme_color_override("font_color", Color.YELLOW)
		else:
			api_status.add_theme_color_override("font_color", Color.ORANGE)
	else:
		api_status.text = "API: Ready"
		api_status.add_theme_color_override("font_color", Color.WHITE)

	# Update progress bar
	var progress_container = status_bar.get_node_or_null("ProgressContainer")
	if progress_container:
		var progress_text = progress_container.get_node("ProgressText")
		var progress_fill = progress_container.get_node("ProgressBG/ProgressFill")
		var progress_bg = progress_container.get_node("ProgressBG")

		# Update progress text
		if total_items > 0:
			progress_text.text = "%d%%" % percentage
		else:
			progress_text.text = "Ready"

		# Update progress bar width
		var bar_width = (progress_bg.custom_minimum_size.x * percentage) / 100
		progress_fill.custom_minimum_size.x = max(0, bar_width)

		# Update progress bar color
		if percentage == 100:
			progress_fill.color = Color.GREEN
			progress_text.add_theme_color_override("font_color", Color.GREEN)
		elif percentage > 50:
			progress_fill.color = Color.YELLOW
			progress_text.add_theme_color_override("font_color", Color.YELLOW)
		else:
			progress_fill.color = Color.ORANGE
			progress_text.add_theme_color_override("font_color", Color.ORANGE)

	# Update last update with more info
	var timestamp = Time.get_datetime_string_from_system().substr(11, 8)
	last_update.text = "Updated: %s | Showing %d of %d items" % [timestamp, total_items, total_available]


func update_right_panel_with_market_data(market_data: Dictionary):
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel and trading_panel.has_method("handle_market_data_update"):
		trading_panel.handle_market_data_update(market_data)


func update_search_results_names(data: Dictionary):
	# Update search result names when item names are loaded
	var type_id = data.get("type_id", 0)
	var name = data.get("name", "Unknown")

	var search_results = get_search_results_container()
	for child in search_results.get_children():
		var name_label = child.get_node_or_null("HBoxContainer/NameLabel")
		if name_label and name_label.text.contains("Item %d" % type_id):
			name_label.text = name


func get_trading_hub_info(region_name: String) -> String:
	match region_name:
		"The Forge (Jita)":
			return "\n🔥 Major Trade Hub"
		"Domain (Amarr)":
			return "\n⭐ Major Trade Hub"
		"Sinq Laison (Dodixie)":
			return "\n💫 Major Trade Hub"
		"Metropolis (Rens)":
			return "\n🌟 Major Trade Hub"
		"Heimatar (Hek)":
			return "\n✨ Secondary Hub"
		_:
			return ""


func get_search_results_container() -> VBoxContainer:
	return $UIManager/MainContent/LeftPanel/SearchPanel/SearchResults/SearchResultsList


func add_search_result_item(item_id: int):
	var search_results_container = get_search_results_container()

	# Create a simple clickable button
	var item_button = Button.new()
	item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_button.custom_minimum_size.y = 30

	# Get item name
	var item_name = "Loading..."
	if data_manager:
		item_name = data_manager.get_item_name(item_id)

	item_button.text = "%s (ID: %d)" % [item_name, item_id]

	# Connect the button to selection
	item_button.pressed.connect(func(): _on_search_item_selected(item_id))

	search_results_container.add_child(item_button)


func _on_search_item_selected(item_id: int):
	print("Selected item from search: ", item_id)
	selected_item_id = item_id

	# For search results, we need to find the data in the grid
	# since search only gives us the item_id
	var existing_item_data = {}
	if market_grid:
		existing_item_data = market_grid.get_item_data(item_id)

	if existing_item_data.is_empty():
		# Create basic item data structure if not found in grid
		existing_item_data = {
			"item_id": item_id,
			"item_name": data_manager.get_item_name(item_id) if data_manager else "Item %d" % item_id,
			"max_buy": 0.0,
			"min_sell": 0.0,
			"spread": 0.0,
			"margin": 0.0,
			"volume": 0,
			"buy_orders": [],
			"sell_orders": [],
			"region_id": current_region_id,
			"region_name": get_current_region_name()
		}
		print("Created basic item data for search result")
	else:
		print("Found existing grid data for search result")

	# Update right panel
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if trading_panel:
		trading_panel.update_item_display(existing_item_data)


func _on_search_result_selected(item_id: int):
	selected_item_id = item_id
	print("Selected item: ", item_id)

	# Get detailed item info
	if data_manager:
		data_manager.get_item_info(item_id)
		data_manager.get_market_orders(current_region_id, item_id)


func update_item_details(data: Dictionary):
	# Update item information panel
	print("Updating item details with: ", data.keys())


func update_right_panel_for_item(item_id: int):
	var trading_panel = right_panel.get_node_or_null("TradingRightPanel")
	if not trading_panel:
		print("No trading panel found")
		return

	print("Updating right panel for item: ", item_id)

	# Try to find existing data for this item in the market grid
	var existing_item_data = find_item_data_in_grid(item_id)

	if existing_item_data.is_empty():
		# Create basic item data structure if not found
		existing_item_data = {
			"item_id": item_id,
			"item_name": data_manager.get_item_name(item_id) if data_manager else "Item %d" % item_id,
			"max_buy": 0.0,
			"min_sell": 0.0,
			"spread": 0.0,
			"margin": 0.0,
			"volume": 0,
			"buy_orders": [],
			"sell_orders": [],
			"region_id": current_region_id,
			"region_name": get_current_region_name()
		}

	trading_panel.update_item_display(existing_item_data)


func find_item_data_in_grid(item_id: int) -> Dictionary:
	# Get the existing item data from the market grid
	if market_grid and market_grid.has_method("get_item_data"):
		return market_grid.get_item_data(item_id)

	print("Market grid not available or doesn't have get_item_data method")
	return {}


# Dialog Management
func show_error_dialog(title: String, message: String):
	error_dialog.title = title
	error_dialog.dialog_text = message
	error_dialog.popup_centered()


func show_price_alert(alert: Dictionary):
	var message = "Price alert: %s has reached %s ISK" % [alert.get("item_name", "Unknown"), alert.get("price", 0)]
	show_system_alert({"message": message})


func show_system_alert(alert: Dictionary):
	alert_dialog.dialog_text = alert.get("message", "Alert")
	alert_dialog.popup_centered()


# Cleanup
func _exit_tree():
	# Save settings
	if config_manager:
		config_manager.save_settings()

	# Close database connections
	if database_manager:
		database_manager.close()

	print("Application cleanup completed")


# Utility Methods
func get_current_region_name() -> String:
	if region_selector.selected >= 0:
		return region_selector.get_item_text(region_selector.selected)
	return "Unknown Region"


func set_loading_state(loading: bool):
	is_loading = loading
	refresh_button.disabled = loading

	if loading:
		api_status.text = "API: Loading market data..."
		api_status.add_theme_color_override("font_color", Color.CYAN)
		connection_status.text = "Loading..."
	else:
		connection_status.text = "Connected"


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


func debug_data_structure(data, depth: int = 0):
	var indent = "  ".repeat(depth)

	match typeof(data):
		TYPE_ARRAY:
			print(indent, "Array[", data.size(), "]:")
			if data.size() > 0:
				print(indent, "  First item type: ", typeof(data[0]))
				if data.size() > 0 and typeof(data[0]) == TYPE_DICTIONARY:
					print(indent, "  First item keys: ", data[0].keys())
		TYPE_DICTIONARY:
			print(indent, "Dictionary keys: ", data.keys())
			for key in data.keys():
				print(indent, "  ", key, ": ", typeof(data[key]))
		_:
			print(indent, "Type: ", typeof(data), " Value: ", str(data).substr(0, 100))


func test_status_bar():
	print("=== TESTING STATUS BAR ===")

	if connection_status:
		connection_status.text = "TEST CONNECTION"
		connection_status.add_theme_color_override("font_color", Color.RED)
		print("Set connection status to TEST")

	if api_status:
		api_status.text = "TEST API STATUS"
		api_status.add_theme_color_override("font_color", Color.YELLOW)
		print("Set API status to TEST")

	if last_update:
		last_update.text = "TEST LAST UPDATE"
		last_update.add_theme_color_override("font_color", Color.CYAN)
		print("Set last update to TEST")

	print("========================")
