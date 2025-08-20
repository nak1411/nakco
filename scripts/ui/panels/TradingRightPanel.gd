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

@onready var data_manager: DataManager

var sr_toggle: Button = null
var spread_toggle: Button = null


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

	var spacer = Control.new()
	spacer.custom_minimum_size.y = 5
	chart_vbox.add_child(spacer)

	var chart_header_container = HBoxContainer.new()
	chart_header_container.custom_minimum_size.y = 30
	chart_vbox.add_child(chart_header_container)

	var chart_header = Label.new()
	chart_header.text = "Station Trading Analysis"
	chart_header.add_theme_color_override("font_color", Color.CYAN)
	chart_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_header_container.add_child(chart_header)

	var timeframe_label = Label.new()
	timeframe_label.name = "TimeframeLabel"
	timeframe_label.text = "24H Rolling"
	timeframe_label.add_theme_color_override("font_color", Color.YELLOW)
	timeframe_label.add_theme_font_size_override("font_size", 10)
	chart_header_container.add_child(timeframe_label)

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
	"""Create chart control buttons"""
	var controls_container = HBoxContainer.new()
	controls_container.name = "ChartControls"

	# Spread Analysis Toggle Button
	spread_toggle = Button.new()
	spread_toggle.name = "SpreadToggle"
	spread_toggle.text = "Spread Analysis: OFF"
	spread_toggle.custom_minimum_size = Vector2(150, 25)
	spread_toggle.pressed.connect(_on_spread_analysis_toggle)
	controls_container.add_child(spread_toggle)

	# Support/Resistance Toggle Button (for future use)
	sr_toggle = Button.new()
	sr_toggle.name = "SRToggle"
	sr_toggle.text = "S/R Lines: OFF"
	sr_toggle.custom_minimum_size = Vector2(120, 25)
	sr_toggle.pressed.connect(_on_support_resistance_toggle)
	controls_container.add_child(sr_toggle)

	return controls_container


func _on_support_resistance_toggle():
	if market_chart:
		market_chart.toggle_support_resistance()
		_update_button_texts()


func _on_spread_analysis_toggle():
	if market_chart:
		market_chart.toggle_spread_analysis()
		_update_button_texts()


func _update_button_texts():
	"""Update button text to reflect current toggle states"""
	if not market_chart:
		return

	if sr_toggle:
		sr_toggle.text = "S/R Lines: %s" % ("ON" if market_chart.show_support_resistance else "OFF")

	if spread_toggle:
		spread_toggle.text = "Spread Analysis: %s" % ("ON" if market_chart.show_spread_analysis else "OFF")


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
	print("New item: ", item_data.get("item_name", "Unknown"))

	selected_item_data = item_data

	if market_chart:
		market_chart.set_station_trading_data(item_data)
		print("Called set_station_trading_data with keys: %s" % item_data.keys())

		# Set initial spread data if available
		var max_buy = item_data.get("max_buy", 0.0)
		var min_sell = item_data.get("min_sell", 0.0)
		if max_buy > 0 and min_sell > 0:
			market_chart.update_spread_data(max_buy, min_sell)

		print("Chart cleared for new item selection")

	# Update all displays for new item
	update_item_header(item_data)
	update_trading_defaults(item_data)
	update_alert_defaults(item_data)
	update_order_book(item_data)

	print("New item display setup complete")


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

		market_chart.set_station_trading_data(
			{
				"your_buy_price": your_buy_order_price,
				"your_sell_price": your_sell_order_price,
				"cost_with_fees": cost_per_unit,
				"income_after_taxes": income_per_unit,
				"profit_per_unit": profit_per_unit,
				"profit_margin": profit_margin,
				"market_gap": market_gap,
				"actual_best_buy": current_highest_buy,
				"actual_best_sell": current_lowest_sell
			}
		)
	else:
		print("  ❌ Not profitable after fees (%.2f%% margin too low)" % profit_margin)
		# Clear the station trading data but keep the spread visible
		market_chart.set_station_trading_data({})


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
		if market_chart:
			market_chart.finish_historical_data_load()
		return

	if not data_manager:
		print("No data manager available, finishing without data")
		if market_chart:
			market_chart.finish_historical_data_load()
		return

	var item_id = selected_item_data.get("item_id", 0)
	var region_id = selected_item_data.get("region_id", 10000002)

	print("Requesting historical market data for item %d in region %d" % [item_id, region_id])

	# Request market history for the past day
	data_manager.get_market_history(region_id, item_id)


func load_historical_chart_data(history_data: Dictionary):
	"""Load historical market data into the chart as candlesticks - REAL EVE DATA ONLY"""
	print("=== LOADING REAL HISTORICAL CHART DATA AS CANDLESTICKS ===")

	if not market_chart:
		print("ERROR: No market_chart available")
		return

	var history_entries = history_data.get("data", [])
	var context = history_data.get("context", {})
	var item_id = context.get("type_id", 0)

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
		var real_daily_volume = entry.get("volume", 0)
		var real_highest = entry.get("highest", real_avg_price)
		var real_lowest = entry.get("lowest", real_avg_price)

		if real_avg_price <= 0:
			print("Skipping entry with invalid price: %s" % entry.get("date", ""))
			continue

		# Skip if this point would be in the future
		if day_timestamp > current_time:
			continue

		var days_ago = (current_time - day_timestamp) / 86400.0
		print("  Adding REAL data: %.1f days ago, avg=%.2f, H=%.2f, L=%.2f, vol=%d" % [days_ago, real_avg_price, real_highest, real_lowest, real_daily_volume])

		# Add the moving average data point
		market_chart.add_historical_data_point(real_avg_price, real_daily_volume, day_timestamp)

		# Add the candlestick data point (using available OHLC data from EVE)
		# Note: EVE API doesn't provide open/close, so we'll use high/low/average creatively
		var open_price = real_avg_price  # Use average as open (placeholder)
		var close_price = real_avg_price  # Use average as close (placeholder)
		market_chart.add_candlestick_data_point(open_price, real_highest, real_lowest, close_price, real_daily_volume, day_timestamp)

		points_added += 1

	print("=== HISTORICAL DATA LOADING COMPLETE ===")
	print("Total points added: %d (daily historical + candlestick data)" % points_added)
	market_chart.finish_historical_data_load()


func parse_eve_date(date_str: String) -> float:
	"""Parse EVE date format (YYYY-MM-DD) to unix timestamp at 11:00 UTC (Eve downtime)"""
	var parts = date_str.split("-")
	if parts.size() != 3:
		print("Invalid date format: %s" % date_str)
		return 0.0

	var year = int(parts[0])
	var month = int(parts[1])
	var day = int(parts[2])

	# Validate date components
	if year < 2000 or year > 2030 or month < 1 or month > 12 or day < 1 or day > 31:
		print("Invalid date components: %d-%d-%d" % [year, month, day])
		return 0.0

	# Set to 11:00 UTC - Eve Online's daily downtime/reset time
	var datetime = {"year": year, "month": month, "day": day, "hour": 11, "minute": 0, "second": 0}

	var timestamp = Time.get_unix_time_from_datetime_dict(datetime)
	print("Parsed '%s' to EVE downtime timestamp %f (%s)" % [date_str, timestamp, Time.get_datetime_string_from_unix_time(timestamp)])
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
