# scripts/ui/panels/TradingRightPanel.gd
class_name TradingRightPanel
extends VBoxContainer

signal order_placed(order_data: Dictionary)
signal alert_created(alert_data: Dictionary)

var selected_item_data: Dictionary = {}
var real_time_chart: RealtimeChart
var order_book_list: VBoxContainer
var quick_trade_panel: VBoxContainer

@onready var data_manager: DataManager


func _ready():
	setup_panels()
	setup_real_time_updates()


func setup_panels():
	# Clear existing content
	for child in get_children():
		child.queue_free()

	# 1. Item Info Header
	create_item_info_header()

	# 2. Real-time Price Chart
	create_real_time_chart()

	# 3. Order Book Display
	create_order_book_display()

	# 4. Quick Trading Panel
	create_quick_trading_panel()

	# 5. Alert Setup
	create_alert_panel()


func create_item_info_header():
	var header_panel = PanelContainer.new()
	header_panel.name = "ItemInfoPanel"
	header_panel.custom_minimum_size.y = 80
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


func create_real_time_chart():
	var chart_panel = PanelContainer.new()
	chart_panel.name = "ChartPanel"
	chart_panel.custom_minimum_size.y = 200
	add_child(chart_panel)

	var chart_vbox = VBoxContainer.new()
	chart_panel.add_child(chart_vbox)

	var chart_header = Label.new()
	chart_header.text = "Real-Time Price Chart"
	chart_header.add_theme_color_override("font_color", Color.CYAN)
	chart_vbox.add_child(chart_header)

	real_time_chart = RealtimeChart.new()
	real_time_chart.name = "RealtimeChart"
	real_time_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart_vbox.add_child(real_time_chart)


func create_order_book_display():
	var order_book_panel = PanelContainer.new()
	order_book_panel.name = "OrderBookPanel"
	order_book_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(order_book_panel)

	var order_book_vbox = VBoxContainer.new()
	order_book_panel.add_child(order_book_vbox)

	var order_book_header = Label.new()
	order_book_header.text = "Order Book"
	order_book_header.add_theme_color_override("font_color", Color.CYAN)
	order_book_vbox.add_child(order_book_header)

	var order_book_scroll = ScrollContainer.new()
	order_book_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	order_book_vbox.add_child(order_book_scroll)

	order_book_list = VBoxContainer.new()
	order_book_list.name = "OrderBookList"
	order_book_scroll.add_child(order_book_list)


func create_quick_trading_panel():
	var trading_panel = PanelContainer.new()
	trading_panel.name = "TradingPanel"
	trading_panel.custom_minimum_size.y = 150
	add_child(trading_panel)

	var trading_vbox = VBoxContainer.new()
	trading_panel.add_child(trading_vbox)

	var trading_header = Label.new()
	trading_header.text = "Quick Trade"
	trading_header.add_theme_color_override("font_color", Color.CYAN)
	trading_vbox.add_child(trading_header)

	# Quantity input
	var quantity_container = HBoxContainer.new()
	trading_vbox.add_child(quantity_container)

	var quantity_label = Label.new()
	quantity_label.text = "Quantity:"
	quantity_label.custom_minimum_size.x = 60
	quantity_container.add_child(quantity_label)

	var quantity_spinbox = SpinBox.new()
	quantity_spinbox.name = "QuantitySpinBox"
	quantity_spinbox.min_value = 1
	quantity_spinbox.max_value = 999999999
	quantity_spinbox.value = 1
	quantity_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_container.add_child(quantity_spinbox)

	# Price input
	var price_container = HBoxContainer.new()
	trading_vbox.add_child(price_container)

	var price_label = Label.new()
	price_label.text = "Price:"
	price_label.custom_minimum_size.x = 60
	price_container.add_child(price_label)

	var price_spinbox = SpinBox.new()
	price_spinbox.name = "PriceSpinBox"
	price_spinbox.min_value = 0.01
	price_spinbox.max_value = 999999999999.0
	price_spinbox.step = 0.01
	price_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_container.add_child(price_spinbox)

	# Buy/Sell buttons
	var button_container = HBoxContainer.new()
	trading_vbox.add_child(button_container)

	var buy_button = Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "Buy Order"
	buy_button.add_theme_color_override("font_color", Color.GREEN)
	buy_button.pressed.connect(_on_buy_button_pressed)
	button_container.add_child(buy_button)

	var sell_button = Button.new()
	sell_button.name = "SellButton"
	sell_button.text = "Sell Order"
	sell_button.add_theme_color_override("font_color", Color.RED)
	sell_button.pressed.connect(_on_sell_button_pressed)
	button_container.add_child(sell_button)


func create_alert_panel():
	var alert_panel = PanelContainer.new()
	alert_panel.name = "AlertPanel"
	alert_panel.custom_minimum_size.y = 100
	add_child(alert_panel)

	var alert_vbox = VBoxContainer.new()
	alert_panel.add_child(alert_vbox)

	var alert_header = Label.new()
	alert_header.text = "Price Alerts"
	alert_header.add_theme_color_override("font_color", Color.CYAN)
	alert_vbox.add_child(alert_header)

	var alert_container = HBoxContainer.new()
	alert_vbox.add_child(alert_container)

	var alert_label = Label.new()
	alert_label.text = "Target:"
	alert_label.custom_minimum_size.x = 50
	alert_container.add_child(alert_label)

	var alert_price_input = SpinBox.new()
	alert_price_input.name = "AlertPriceInput"
	alert_price_input.min_value = 0.01
	alert_price_input.max_value = 999999999999.0
	alert_price_input.step = 0.01
	alert_price_input.value = 100.0  # Default value instead of placeholder
	alert_price_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert_container.add_child(alert_price_input)

	var condition_selector = OptionButton.new()
	condition_selector.name = "ConditionSelector"
	condition_selector.add_item("Above")
	condition_selector.add_item("Below")
	condition_selector.selected = 0
	alert_container.add_child(condition_selector)

	var create_alert_button = Button.new()
	create_alert_button.text = "Create"
	create_alert_button.pressed.connect(_on_create_alert_pressed)
	alert_container.add_child(create_alert_button)


func update_item_display(item_data: Dictionary):
	selected_item_data = item_data

	# Update header
	var item_name_label = get_node("ItemInfoPanel/VBoxContainer/ItemNameLabel")
	if item_name_label:
		item_name_label.text = item_data.get("item_name", "Unknown Item")

	var buy_price_label = get_node("ItemInfoPanel/VBoxContainer/HBoxContainer/BuyPriceLabel")
	if buy_price_label:
		buy_price_label.text = "Buy: %s ISK" % format_isk(item_data.get("max_buy", 0))

	var sell_price_label = get_node("ItemInfoPanel/VBoxContainer/HBoxContainer/SellPriceLabel")
	if sell_price_label:
		sell_price_label.text = "Sell: %s ISK" % format_isk(item_data.get("min_sell", 0))

	var spread_label = get_node("ItemInfoPanel/VBoxContainer/HBoxContainer/SpreadLabel")
	if spread_label:
		spread_label.text = "Spread: %s ISK" % format_isk(item_data.get("spread", 0))

	# Update trading panel with current prices
	var price_spinbox = get_node("TradingPanel/VBoxContainer/HBoxContainer2/PriceSpinBox")
	if price_spinbox:
		# Set default price to current best buy price
		price_spinbox.value = item_data.get("max_buy", 100.0)

	var alert_price_input = get_node("AlertPanel/VBoxContainer/HBoxContainer/AlertPriceInput")
	if alert_price_input:
		# Set default alert price to current sell price
		alert_price_input.value = item_data.get("min_sell", 100.0)

	# Update chart
	if real_time_chart:
		var price = item_data.get("max_buy", 0)
		var volume = item_data.get("volume", 0)
		real_time_chart.add_data_point(price, volume, Time.get_datetime_string_from_system())

	# Update order book
	update_order_book(item_data)


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


func setup_real_time_updates():
	# Set up timer for real-time updates
	var timer = Timer.new()
	timer.wait_time = 5.0  # Update every 5 seconds
	timer.timeout.connect(_update_real_time_data)
	add_child(timer)
	timer.start()


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


func format_isk(value: float) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return "%.0f" % value
