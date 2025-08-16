# scripts/ui/panels/TradingRightPanel.gd
class_name TradingRightPanel
extends VBoxContainer

signal order_placed(order_data: Dictionary)
signal alert_created(alert_data: Dictionary)

var selected_item_data: Dictionary = {}
var current_market_data: Dictionary = {}
var real_time_chart: RealtimeChart
var order_book_list: VBoxContainer
var quick_trade_panel: VBoxContainer

@onready var data_manager: DataManager


func _ready():
	setup_panels()


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
	print("TradingRightPanel: update_item_display called with: ", item_data.keys())

	selected_item_data = item_data

	# Update header - using the correct path based on actual structure
	var item_name_label = get_node_or_null("ItemInfoPanel").get_child(0).get_node_or_null("ItemNameLabel")
	if item_name_label:
		var item_name = item_data.get("item_name", "Unknown Item")
		var item_id = item_data.get("item_id", 0)
		var realtime_indicator = " 🔴 LIVE" if item_data.get("is_realtime", false) else ""
		item_name_label.text = "%s (ID: %d)%s" % [item_name, item_id, realtime_indicator]

		# Color the indicator
		if item_data.get("is_realtime", false):
			item_name_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
		else:
			item_name_label.add_theme_color_override("font_color", Color.CYAN)

		print("Updated item name label to: ", item_name_label.text)
	else:
		print("ERROR: Could not find ItemNameLabel")

	# Update prices with animation for real-time data
	update_price_labels_with_animation(item_data)

	# Update trading defaults
	update_trading_defaults(item_data)

	# Update alert defaults
	update_alert_defaults(item_data)

	# Update order book
	update_order_book(item_data)

	# Update real-time chart
	update_real_time_chart(item_data)


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

	# Update the basic display
	update_item_display(realtime_data)

	# Update chart with new price point
	update_realtime_chart_data(realtime_data)

	# Update order book with fresh orders
	update_order_book_realtime(realtime_data)


func update_realtime_chart_data(data: Dictionary):
	"""Add new data point to real-time chart"""
	if not real_time_chart:
		return

	var max_buy = data.get("max_buy", 0.0)
	var min_sell = data.get("min_sell", 0.0)
	var volume = data.get("volume", 0)
	var timestamp = data.get("timestamp", Time.get_ticks_msec())

	# Use mid-point price for chart if we have both buy and sell
	var chart_price = 0.0
	if max_buy > 0 and min_sell > 0:
		chart_price = (max_buy + min_sell) / 2.0
	elif max_buy > 0:
		chart_price = max_buy
	elif min_sell > 0:
		chart_price = min_sell

	if chart_price > 0:
		var time_label = Time.get_datetime_string_from_system().substr(11, 8)
		real_time_chart.add_data_point(chart_price, volume, time_label)
		print("Added chart data point: price=", chart_price, " volume=", volume)


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
	var item_name_label = get_node_or_null("ItemInfoPanel/VBoxContainer/ItemNameLabel")
	if item_name_label:
		var item_name = item_data.get("item_name", "Unknown Item")
		var item_id = item_data.get("item_id", 0)
		item_name_label.text = "%s (ID: %d)" % [item_name, item_id]

	var buy_price_label = get_node_or_null("ItemInfoPanel/VBoxContainer/HBoxContainer/BuyPriceLabel")
	if buy_price_label:
		var max_buy = item_data.get("max_buy", 0)
		buy_price_label.text = "Buy: %s ISK" % format_isk(max_buy)
		buy_price_label.add_theme_color_override("font_color", Color.GREEN if max_buy > 0 else Color.GRAY)

	var sell_price_label = get_node_or_null("ItemInfoPanel/VBoxContainer/HBoxContainer/SellPriceLabel")
	if sell_price_label:
		var min_sell = item_data.get("min_sell", 0)
		sell_price_label.text = "Sell: %s ISK" % format_isk(min_sell)
		sell_price_label.add_theme_color_override("font_color", Color.RED if min_sell > 0 else Color.GRAY)

	var spread_label = get_node_or_null("ItemInfoPanel/VBoxContainer/HBoxContainer/SpreadLabel")
	if spread_label:
		var spread = item_data.get("spread", 0)
		var margin = item_data.get("margin", 0)
		spread_label.text = "Spread: %s ISK (%.1f%%)" % [format_isk(spread), margin]

		# Color code based on margin
		if margin > 10:
			spread_label.add_theme_color_override("font_color", Color.GREEN)
		elif margin > 5:
			spread_label.add_theme_color_override("font_color", Color.YELLOW)
		elif margin > 0:
			spread_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			spread_label.add_theme_color_override("font_color", Color.GRAY)


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


func update_real_time_chart(item_data: Dictionary):
	if real_time_chart:
		var price = item_data.get("max_buy", item_data.get("min_sell", 0))
		var volume = item_data.get("volume", 0)

		if price > 0:
			var timestamp = Time.get_datetime_string_from_system().substr(11, 8)
			real_time_chart.add_data_point(price, volume, timestamp)


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


func process_market_data_for_item(market_data: Dictionary, target_item_id: int) -> Dictionary:
	var orders = market_data.get("data", [])
	var buy_orders = []
	var sell_orders = []

	for order in orders:
		if order.get("type_id", 0) != target_item_id:
			continue

		if order.get("is_buy_order", false):
			buy_orders.append(order)
		else:
			sell_orders.append(order)

	if buy_orders.is_empty() and sell_orders.is_empty():
		return {}

	# Sort orders
	buy_orders.sort_custom(func(a, b): return a.get("price", 0) > b.get("price", 0))
	sell_orders.sort_custom(func(a, b): return a.get("price", 0) < b.get("price", 0))

	# Calculate metrics
	var max_buy = buy_orders[0].get("price", 0) if not buy_orders.is_empty() else 0
	var min_sell = sell_orders[0].get("price", 0) if not sell_orders.is_empty() else 0
	var spread = min_sell - max_buy if max_buy > 0 and min_sell > 0 else 0
	var margin = (spread / max_buy) * 100.0 if max_buy > 0 else 0

	var total_volume = 0
	for order in buy_orders + sell_orders:
		total_volume += order.get("volume_remain", 0)

	return {
		"item_id": target_item_id,
		"item_name": selected_item_data.get("item_name", "Unknown"),
		"max_buy": max_buy,
		"min_sell": min_sell,
		"spread": spread,
		"margin": margin,
		"volume": total_volume,
		"buy_orders": buy_orders.slice(0, 10),  # Top 10 orders
		"sell_orders": sell_orders.slice(0, 10)
	}


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
