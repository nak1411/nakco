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


func create_item_info_header():
	var header_panel = PanelContainer.new()
	header_panel.name = "ItemInfoPanel"
	header_panel.custom_minimum_size.y = 50
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
	chart_panel.custom_minimum_size.y = 300
	add_child(chart_panel)

	var chart_vbox = VBoxContainer.new()
	chart_panel.add_child(chart_vbox)

	var chart_header_container = HBoxContainer.new()
	chart_vbox.add_child(chart_header_container)

	var chart_header = Label.new()
	chart_header.text = "24-Hour Price Chart"
	chart_header.add_theme_color_override("font_color", Color.CYAN)
	chart_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_header_container.add_child(chart_header)

	var timeframe_label = Label.new()
	timeframe_label.name = "TimeframeLabel"
	timeframe_label.text = "24H Rolling"
	timeframe_label.add_theme_color_override("font_color", Color.YELLOW)
	timeframe_label.add_theme_font_size_override("font_size", 10)
	chart_header_container.add_child(timeframe_label)

	real_time_chart = RealtimeChart.new()
	real_time_chart.name = "RealtimeChart"
	real_time_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# EXPLICITLY disable any tooltip behavior
	real_time_chart.tooltip_text = ""
	real_time_chart.mouse_filter = Control.MOUSE_FILTER_PASS

	chart_vbox.add_child(real_time_chart)

	# Connect historical data request signal
	real_time_chart.historical_data_requested.connect(_on_historical_data_requested)


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

	# Only clear chart for genuinely NEW items
	if real_time_chart:
		real_time_chart.clear_data()
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

	# DON'T call update_item_display - that clears the chart!
	# Instead, just update the specific parts that need updating

	# Update selected_item_data with new real-time info
	selected_item_data.merge(realtime_data, true)

	# Update header info with new prices (without clearing chart)
	update_item_header(realtime_data)

	# Update chart with new price point (without clearing)
	update_realtime_chart_data(realtime_data)

	# Update order book with fresh orders
	update_order_book_realtime(realtime_data)

	print("Real-time update complete - chart data preserved")


func update_realtime_chart_data(data: Dictionary):
	"""Add new data point to real-time chart WITHOUT clearing existing data"""
	if not real_time_chart:
		print("ERROR: No real_time_chart available")
		return

	var max_buy = data.get("max_buy", 0.0)
	var min_sell = data.get("min_sell", 0.0)
	var total_buy_volume = data.get("total_buy_volume", 0)
	var total_sell_volume = data.get("total_sell_volume", 0)
	var total_volume = data.get("volume", total_buy_volume + total_sell_volume)

	# Calculate market price
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

	if market_price > 0:
		var time_label = Time.get_datetime_string_from_system().substr(11, 8)
		print("Adding real-time chart point: price=%.2f, volume=%d (preserving existing data)" % [market_price, total_volume])
		real_time_chart.add_data_point(market_price, total_volume, time_label)
	else:
		print("No valid market price for real-time update")


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


func _on_historical_data_requested():
	"""Handle request for historical data"""
	print("=== HISTORICAL DATA REQUESTED ===")

	if not selected_item_data.has("item_id"):
		print("No item selected, finishing without data")
		if real_time_chart:
			real_time_chart.finish_historical_data_load()
		return

	if not data_manager:
		print("No data manager available, finishing without data")
		if real_time_chart:
			real_time_chart.finish_historical_data_load()
		return

	var item_id = selected_item_data.get("item_id", 0)
	var region_id = selected_item_data.get("region_id", 10000002)

	print("Requesting historical market data for item %d in region %d" % [item_id, region_id])

	# Request market history for the past day
	data_manager.get_market_history(region_id, item_id)


func load_historical_chart_data(history_data: Dictionary):
	"""Load historical market data into the chart - EXTENDED VERSION"""
	print("=== LOADING EXTENDED HISTORICAL CHART DATA ===")

	if not real_time_chart:
		print("ERROR: No real_time_chart available")
		return

	var history_entries = history_data.get("data", [])
	var context = history_data.get("context", {})
	var item_id = context.get("type_id", 0)

	print("History entries count: ", history_entries.size())

	if typeof(history_entries) != TYPE_ARRAY or history_entries.size() == 0:
		print("No valid historical data available")
		real_time_chart.finish_historical_data_load()
		return

	var current_time = Time.get_unix_time_from_system()
	var max_window_start = current_time - 432000.0  # 5 days ago (to support max zoom)
	var points_added = 0

	print("Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))
	print("Max window start (5 days ago): %s" % Time.get_datetime_string_from_unix_time(max_window_start))

	# Process ALL available historical entries (not just most recent)
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

	print("Found %d valid historical entries within 5 days" % valid_entries.size())

	# Create data points for each historical day
	for entry_info in valid_entries:
		var entry = entry_info.data
		var base_timestamp = entry_info.timestamp

		var avg_price = entry.get("average", 0.0)
		var daily_volume = entry.get("volume", 0)
		var highest = entry.get("highest", avg_price)
		var lowest = entry.get("lowest", avg_price)

		if avg_price <= 0:
			print("Skipping entry with invalid price: %s" % entry.get("date", ""))
			continue

		if daily_volume <= 0:
			daily_volume = 100000  # Default volume

		print("Processing entry: %s, price=%.2f, volume=%d" % [entry.get("date", ""), avg_price, daily_volume])

		# Create multiple data points throughout each day (every hour = 24 points per day)
		var points_per_day = 24
		for hour_offset in range(points_per_day):
			var point_timestamp = base_timestamp + (hour_offset * 3600.0)  # Every 1 hour

			# Skip if this point would be in the future
			if point_timestamp > current_time:
				continue

			# Simulate price variation throughout the day
			var time_factor = float(hour_offset) / points_per_day
			var price_variation = (highest - lowest) * 0.4
			var point_price = avg_price + (sin(time_factor * PI * 3) * price_variation)
			point_price = clamp(point_price, lowest * 0.95, highest * 1.05)

			# Simulate MORE REALISTIC volume variation throughout the day
			var hour_of_day = hour_offset % 24
			var volume_multiplier = 1.0

			# Create realistic trading volume patterns based on EVE Online peak hours
			if hour_of_day >= 18 and hour_of_day <= 23:  # Peak evening hours (6PM-11PM UTC)
				volume_multiplier = randf_range(2.5, 4.0)
			elif hour_of_day >= 12 and hour_of_day <= 17:  # Afternoon hours
				volume_multiplier = randf_range(1.5, 2.5)
			elif hour_of_day >= 8 and hour_of_day <= 11:  # Morning hours
				volume_multiplier = randf_range(1.0, 1.8)
			elif hour_of_day >= 0 and hour_of_day <= 7:  # Late night/early morning
				volume_multiplier = randf_range(0.3, 0.8)

			# Add some random variation to make it look more realistic
			volume_multiplier *= randf_range(0.7, 1.3)

			# Calculate hourly volume as a portion of daily volume
			var base_hourly_volume = daily_volume / 24.0
			var point_volume = int(base_hourly_volume * volume_multiplier)
			if daily_volume < 2400:  # If daily volume is very low (less than 100/hour average)
				# For low-volume items, create more realistic small volumes
				point_volume = max(int(randf_range(1, 50)), point_volume)
			else:
				# For normal items, use reasonable minimum
				point_volume = max(100, point_volume)

			var hours_ago = (current_time - point_timestamp) / 3600.0
			print("  Creating point: %.1fh ago, price=%.2f, volume=%d (mult=%.2f)" % [hours_ago, point_price, point_volume, volume_multiplier])

			real_time_chart.add_historical_data_point(point_price, point_volume, point_timestamp)
			points_added += 1

	# FILL THE GAP: Create interpolated data points between most recent historical data and now
	var most_recent_historical = current_time - 86400.0  # 1 day ago (approximate)

	# Get the last historical price and volume for interpolation base
	var base_price = 1000.0  # Default fallback
	var base_volume = 10000  # Default fallback

	# Find the actual most recent historical data point and get its values
	if valid_entries.size() > 0:
		var last_entry = valid_entries[-1]
		most_recent_historical = last_entry.timestamp + 86400.0  # End of last historical day
		base_price = last_entry.data.get("average", 1000.0)
		base_volume = last_entry.data.get("volume", 100000) / 24  # Divide by 24 points per day

	# Fill gap from most recent historical data ALL THE WAY to current time
	# Only fill gap if it's significant (more than 2 hours)
	if (current_time - most_recent_historical) > 7200.0:
		print("FILLING GAP: From %s to %s" % [Time.get_datetime_string_from_unix_time(most_recent_historical), Time.get_datetime_string_from_unix_time(current_time)])

		# Create data points every hour in the gap, going all the way to now
		var gap_duration = current_time - most_recent_historical
		var gap_points = int(gap_duration / 3600.0)  # One point per hour

		for i in range(gap_points):
			var gap_timestamp = most_recent_historical + (i * 3600.0)  # Every hour

			# Don't go into the future, but get close to current time
			if gap_timestamp >= current_time - 1800.0:  # Stop 30 minutes before now to leave room for real-time data
				break

			# Simulate gradual price evolution toward current market conditions
			var evolution_factor = float(i) / gap_points
			var price_drift = randf_range(-0.05, 0.05)  # ±5% random drift
			var gap_price = base_price * (1.0 + (evolution_factor * price_drift))

			# Simulate realistic volume patterns
			var hour_of_day = int(fmod(gap_timestamp, 86400.0) / 3600.0)
			var volume_multiplier = 1.0

			# Use same realistic volume patterns as historical data
			if hour_of_day >= 18 and hour_of_day <= 23:  # Peak evening hours
				volume_multiplier = randf_range(2.5, 4.0)
			elif hour_of_day >= 12 and hour_of_day <= 17:  # Afternoon hours
				volume_multiplier = randf_range(1.5, 2.5)
			elif hour_of_day >= 8 and hour_of_day <= 11:  # Morning hours
				volume_multiplier = randf_range(1.0, 1.8)
			elif hour_of_day >= 0 and hour_of_day <= 7:  # Late night/early morning
				volume_multiplier = randf_range(0.3, 0.8)

			volume_multiplier *= randf_range(0.7, 1.3)  # Add random variation

			var gap_volume = int(base_volume * volume_multiplier)
			if base_volume < 100:  # If base volume is very low
				gap_volume = max(int(randf_range(1, 20)), gap_volume)
			else:
				gap_volume = max(100, gap_volume)

			var hours_ago = (current_time - gap_timestamp) / 3600.0
			print("  Gap fill point: %.1fh ago, price=%.2f, volume=%d" % [hours_ago, gap_price, gap_volume])

			real_time_chart.add_historical_data_point(gap_price, gap_volume, gap_timestamp)
			points_added += 1

	print("=== EXTENDED HISTORICAL LOADING COMPLETE ===")
	print("Total points added: %d" % points_added)
	real_time_chart.finish_historical_data_load()


func parse_eve_date(date_str: String) -> float:
	"""Parse EVE date format (YYYY-MM-DD) to unix timestamp"""
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

	var datetime = {"year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0}  # Noon UTC

	var timestamp = Time.get_unix_time_from_datetime_dict(datetime)
	print("Parsed '%s' to timestamp %f (%s)" % [date_str, timestamp, Time.get_datetime_string_from_unix_time(timestamp)])
	return timestamp


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
