# Main.gd
class_name Main
extends Control

# Constants
const VERSION = "1.0.0"
const APP_NAME = "EVE Trader"

# Application state
var current_region_id: int = 10000002  # Jita by default
var selected_item_id: int = -1
var is_loading: bool = false

# Core managers
@onready var data_manager: DataManager
@onready var config_manager: ConfigManager
@onready var notification_manager: NotificationManager
@onready var database_manager: DatabaseManager

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
@onready var center_panel: TabContainer = $UIManager/MainContent/CenterPanel
@onready var right_panel: VBoxContainer = $UIManager/MainContent/RightPanel

# Search and watchlist
@onready var item_search: LineEdit = $UIManager/MainContent/LeftPanel/SearchPanel/ItemSearch
@onready var watchlist_items: VBoxContainer = $UIManager/MainContent/LeftPanel/WatchlistPanel/WatchlistContainer/WatchlistItems

# Status bar elements
@onready var connection_status: Label = $UIManager/StatusBar/ConnectionStatus
@onready var api_status: Label = $UIManager/StatusBar/APIStatus
@onready var last_update: Label = $UIManager/StatusBar/LastUpdate

# Dialogs
@onready var error_dialog: AcceptDialog = $DialogLayer/ErrorDialog
@onready var settings_dialog: AcceptDialog = $DialogLayer/SettingsDialog
@onready var alert_dialog: AcceptDialog = $DialogLayer/AlertDialog


func _ready():
	setup_application()
	setup_managers()
	setup_ui()
	setup_signals()
	load_initial_data()


func setup_application():
	# Set window properties
	get_window().title = "%s v%s" % [APP_NAME, VERSION]
	get_window().min_size = Vector2i(1200, 800)

	# Setup theme
	apply_theme()


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

	print("Managers initialized")


func setup_ui():
	# Configure toolbar buttons
	refresh_button.text = "Refresh"
	refresh_button.icon = preload("res://assets/icons/ui/refresh.svg")

	alerts_button.text = "Alerts"
	alerts_button.icon = preload("res://assets/icons/ui/alert.svg")

	settings_button.text = "Settings"
	settings_button.icon = preload("res://assets/icons/ui/settings.svg")

	# Setup region selector
	populate_region_selector()

	# Configure search
	item_search.placeholder_text = "Search items..."
	item_search.clear_button_enabled = true

	# Setup tab container
	center_panel.tab_alignment = TabBar.ALIGNMENT_LEFT

	# Configure status bar
	connection_status.text = "Connecting..."
	api_status.text = "API: Initializing"
	last_update.text = "Last update: Never"

	# Set panel sizes
	main_content.split_offset = 300  # Left panel width
	left_panel.split_offset = 200  # Search vs watchlist


func setup_signals():
	# Toolbar signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	alerts_button.pressed.connect(_on_alerts_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	region_selector.item_selected.connect(_on_region_changed)

	# Search signals
	item_search.text_changed.connect(_on_search_text_changed)
	item_search.text_submitted.connect(_on_search_submitted)

	# Data manager signals
	data_manager.data_updated.connect(_on_data_updated)
	data_manager.api_error.connect(_on_api_error)

	# Notification manager signals
	notification_manager.notification_triggered.connect(_on_notification)

	# Tab changed signal
	center_panel.tab_changed.connect(_on_tab_changed)


func populate_region_selector():
	var regions = data_manager.get_major_trade_hubs()
	region_selector.clear()

	for region_name in regions.keys():
		region_selector.add_item(region_name)
		region_selector.set_item_metadata(region_selector.get_item_count() - 1, regions[region_name])

	# Select Jita by default
	region_selector.selected = 0


func apply_theme():
	# Load and apply theme
	var theme_path = config_manager.get_setting("ui_theme", "res://assets/themes/dark_theme.tres")
	if FileAccess.file_exists(theme_path):
		var custom_theme = load(theme_path)
		if custom_theme:
			theme = custom_theme


func load_initial_data():
	# Load user settings
	config_manager.load_settings()

	# Initialize database
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
	refresh_market_data()


func _on_search_text_changed(new_text: String):
	if new_text.length() >= 3:
		# Trigger search with debounce
		search_items_debounced(new_text)


func _on_search_submitted(text: String):
	if text.length() >= 2:
		data_manager.search_items(text)


func _on_data_updated(data_type: String, data: Dictionary):
	match data_type:
		"market_orders":
			update_market_display(data)
		"market_history":
			update_charts(data)
		"item_search":
			update_search_results(data)
		"item_info":
			update_item_details(data)

	# Update status
	last_update.text = "Last update: " + Time.get_datetime_string_from_system()
	api_status.text = "API: Connected"
	connection_status.text = "Connected"


func _on_api_error(error_message: String):
	print("API Error: ", error_message)
	show_error_dialog("API Error", error_message)

	# Update status
	api_status.text = "API: Error"
	connection_status.text = "Connection issues"


func _on_notification(notification: Dictionary):
	# Handle various notification types
	match notification.type:
		"price_alert":
			show_price_alert(notification)
		"system_alert":
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


# Data Management


func refresh_market_data():
	if is_loading:
		return

	is_loading = true
	refresh_button.disabled = true

	# Get market data for current region
	data_manager.get_market_orders(current_region_id)

	# Re-enable refresh button after delay
	await get_tree().create_timer(2.0).timeout
	refresh_button.disabled = false
	is_loading = false


func search_items_debounced(search_text: String):
	# Simple debounce implementation
	if has_method("_search_timer"):
		return

	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(
		func():
			data_manager.search_items(search_text)
			timer.queue_free()
	)
	timer.start()


func refresh_portfolio_data():
	# Load portfolio from database
	var portfolio_data = database_manager.get_portfolio()
	# Update portfolio display


func refresh_analytics_data():
	# Refresh analytics calculations
	pass


# UI Updates


func update_market_display(_data: Dictionary):
	# Update the market overview panel
	pass


func update_charts(_data: Dictionary):
	# Update price/volume charts

	pass


func update_search_results(_data: Dictionary):
	pass


func update_item_details(_data: Dictionary):
	# Update item information panel

	pass


# Dialog Management


func show_error_dialog(title: String, message: String):
	error_dialog.title = title
	error_dialog.dialog_text = message
	error_dialog.popup_centered()


func show_price_alert(alert: Dictionary):
	var message = "Price alert: %s has reached %s ISK" % [alert.item_name, alert.price]
	show_system_alert({"message": message})


func show_system_alert(alert: Dictionary):
	alert_dialog.dialog_text = alert.message
	alert_dialog.popup_centered()


# Cleanup


func _exit_tree():
	# Save settings
	config_manager.save_settings()

	# Close database connections
	database_manager.close()

	print("Application cleanup completed")


# Utility Methods


func get_current_region_name() -> String:
	if region_selector.selected >= 0:
		return region_selector.get_item_text(region_selector.selected)
	return "Unknown"


func set_loading_state(loading: bool):
	is_loading = loading
	refresh_button.disabled = loading
	# Could add a loading spinner here


func format_number(value: float, decimals: int = 2) -> String:
	return "%.{0}f".format([decimals]) % value
