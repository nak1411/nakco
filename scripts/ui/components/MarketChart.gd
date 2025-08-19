# scripts/ui/components/MarketChart.gd
class_name MarketChart
extends Control

signal price_level_clicked(price: float)
signal historical_data_requested

# Component references
var chart_data: ChartData
var chart_renderer: ChartRenderer
var chart_interaction: ChartInteraction
var chart_math: ChartMath
var analysis_tools: AnalysisTools

# Core data (delegated to ChartData)
var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var candlestick_data: Array[Dictionary] = []
var time_labels: Array[String] = []

# Display settings
var show_candlesticks: bool = true
var show_support_resistance: bool = false
var show_spread_analysis: bool = true

# Chart view state (delegated to ChartInteraction)
var zoom_level: float = 1.0
var chart_center_time: float = 0.0
var chart_center_price: float = 0.0
var chart_price_range: float = 0.0


func _ready():
	custom_minimum_size = Vector2(400, 150)

	# Initialize components
	_initialize_components()
	_connect_signals()

	# Set up initial state
	chart_center_time = Time.get_unix_time_from_system()
	chart_center_price = 1000.0
	chart_price_range = 500.0

	chart_data.set_day_start_time()


func _initialize_components():
	chart_data = ChartData.new()
	chart_renderer = ChartRenderer.new()
	chart_interaction = ChartInteraction.new()
	chart_math = ChartMath.new()
	analysis_tools = AnalysisTools.new()

	# Pass references between components
	chart_renderer.setup(self, chart_data, chart_math, analysis_tools)
	chart_interaction.setup(self, chart_data, chart_math)
	analysis_tools.setup(self, chart_data, chart_math)
	chart_math.setup(self, chart_data)
	chart_data.setup(self)  # MAKE SURE THIS LINE EXISTS

	print("All components initialized")

	# Set up data references for easy access
	price_data = chart_data.price_data
	volume_data = chart_data.volume_data
	candlestick_data = chart_data.candlestick_data
	time_labels = chart_data.time_labels


func _connect_signals():
	mouse_entered.connect(chart_interaction._on_mouse_entered)
	mouse_exited.connect(chart_interaction._on_mouse_exited)
	resized.connect(chart_interaction._on_chart_resized)


func _draw():
	chart_renderer.draw_chart()


func _gui_input(event):
	chart_interaction.handle_input(event)


# Public API methods (delegate to appropriate components)
func add_data_point(price: float, volume: int, time_label: String = ""):
	chart_data.add_data_point(price, volume, time_label)


func add_candlestick_data_point(open: float, high: float, low: float, close: float, volume: int, timestamp: float):
	chart_data.add_candlestick_data_point(open, high, low, close, volume, timestamp)


func set_station_trading_data(data: Dictionary):
	"""Set station trading data for spread analysis"""
	# Properly delegate to the chart_data component
	chart_data.set_station_trading_data(data)

	# Update spread analysis if enabled
	if show_spread_analysis:
		analysis_tools.update_spread_analysis(data)

	print("MarketChart: Station trading data set and analysis updated")


func update_spread_data(buy_price: float, sell_price: float):
	"""Update spread data for analysis"""
	print("Updating spread data: buy=%.2f, sell=%.2f" % [buy_price, sell_price])

	# Update current spread prices
	analysis_tools.current_buy_price = buy_price
	analysis_tools.current_sell_price = sell_price

	# Calculate spread and margin
	var spread = sell_price - buy_price
	var margin_percentage = (spread / buy_price) * 100.0 if buy_price > 0 else 0.0

	# Add to spread history
	var timestamp = Time.get_unix_time_from_system()
	var spread_data = {"timestamp": timestamp, "buy_price": buy_price, "sell_price": sell_price, "spread": spread, "margin_percentage": margin_percentage}

	analysis_tools.spread_history.append(spread_data)

	# Keep rolling window
	if analysis_tools.spread_history.size() > analysis_tools.max_spread_history:
		analysis_tools.spread_history.pop_front()

	print("Updated spread: %.2f ISK (%.2f%% margin)" % [spread, margin_percentage])

	# Redraw if spread analysis is enabled
	if show_spread_analysis:
		queue_redraw()


func update_spread_data_realistic(buy_orders: Array, sell_orders: Array):
	"""Update spread data using more realistic prices (not extreme outliers)"""
	if buy_orders.size() < 2 or sell_orders.size() < 2:
		# Fall back to best prices if not enough orders
		var best_buy = buy_orders[0].get("price", 0.0) if buy_orders.size() > 0 else 0.0
		var best_sell = sell_orders[0].get("price", 0.0) if sell_orders.size() > 0 else 0.0
		update_spread_data(best_buy, best_sell)
		return

	# Use 2nd best prices to avoid outliers, or volume-weighted average of top 3
	var realistic_buy = buy_orders[1].get("price", 0.0)  # 2nd highest buy
	var realistic_sell = sell_orders[1].get("price", 0.0)  # 2nd lowest sell

	# Or calculate volume-weighted average of top 3 orders:
	var total_buy_volume = 0
	var weighted_buy_price = 0.0
	for i in range(min(3, buy_orders.size())):
		var volume = buy_orders[i].get("volume", 0)
		var price = buy_orders[i].get("price", 0.0)
		total_buy_volume += volume
		weighted_buy_price += price * volume

	var total_sell_volume = 0
	var weighted_sell_price = 0.0
	for i in range(min(3, sell_orders.size())):
		var volume = sell_orders[i].get("volume", 0)
		var price = sell_orders[i].get("price", 0.0)
		total_sell_volume += volume
		weighted_sell_price += price * volume

	if total_buy_volume > 0:
		realistic_buy = weighted_buy_price / total_buy_volume
	if total_sell_volume > 0:
		realistic_sell = weighted_sell_price / total_sell_volume

	update_spread_data(realistic_buy, realistic_sell)
	print("Using realistic prices: buy=%.2f, sell=%.2f (volume-weighted top 3)" % [realistic_buy, realistic_sell])


func clear_data():
	"""Clear all chart data"""
	print("=== CLEARING CHART DATA ===")
	print("Clearing %d price points, %d volume points, %d candlesticks" % [chart_data.price_data.size(), chart_data.volume_data.size(), chart_data.candlestick_data.size()])

	chart_data.price_data.clear()
	chart_data.volume_data.clear()
	chart_data.time_labels.clear()
	chart_data.price_history.clear()
	chart_data.candlestick_data.clear()
	chart_data.current_station_trading_data.clear()

	# Clear analysis data
	analysis_tools.support_levels.clear()
	analysis_tools.resistance_levels.clear()
	analysis_tools.current_buy_price = 0.0
	analysis_tools.current_sell_price = 0.0
	analysis_tools.spread_history.clear()

	# Reset historical data flags
	chart_data.has_loaded_historical = false
	chart_data.is_loading_historical = false

	queue_redraw()
	print("Chart data cleared - ready for new item")


func get_latest_price() -> float:
	return chart_data.get_latest_price()


func get_price_change() -> float:
	return chart_data.get_price_change()


func get_price_change_percent() -> float:
	return chart_data.get_price_change_percent()


func set_chart_style(style: String):
	chart_renderer.set_chart_style(style)


func toggle_support_resistance():
	analysis_tools.toggle_support_resistance()


func toggle_spread_analysis():
	analysis_tools.toggle_spread_analysis()


func set_moving_average_period(period: int):
	analysis_tools.set_moving_average_period(period)


func set_timeframe_hours(hours: float):
	"""Allow changing the timeframe"""
	chart_data.timeframe_hours = hours
	chart_data.data_retention_seconds = hours * 3600.0  # Convert to seconds

	# Clean up existing data that's outside new timeframe
	if not chart_data.price_data.is_empty():
		chart_data.cleanup_old_data()

	queue_redraw()
	print("Chart timeframe set to %.1f hours" % hours)


func reset_zoom():
	"""Reset zoom to default level"""
	zoom_level = 1.0
	queue_redraw()
	print("Reset zoom to 1.0x")


func reset_to_current():
	"""Reset chart to current time and auto-fit price"""
	chart_center_time = Time.get_unix_time_from_system()
	zoom_level = 1.0
	initialize_price_center()
	queue_redraw()
	print("Reset to current time and auto price range")


func initialize_price_center():
	"""Initialize the price center based on current data"""
	print("Initializing price center...")

	# Get current visible price range
	var price_info = get_visible_price_range()

	if price_info.count > 0:
		chart_center_price = (price_info.min_price + price_info.max_price) / 2.0

		# FIX: Handle single point or zero range
		if price_info.range <= 0:
			chart_price_range = max(chart_center_price * 0.2, 10000000.0)  # 20% of price or 10M ISK minimum
			print("Single data point - created artificial range: %.2f" % chart_price_range)
		else:
			chart_price_range = price_info.range * 1.2  # Add 20% padding

		print("Set price center to %.2f, range %.2f (from data)" % [chart_center_price, chart_price_range])
	else:
		# Fallback: scan all available data
		var all_prices = []

		for point in chart_data.price_data:
			if point.price > 0:
				all_prices.append(point.price)

		for candle in chart_data.candlestick_data:
			var high = candle.get("high", 0.0)
			var low = candle.get("low", 0.0)
			if high > 0:
				all_prices.append(high)
			if low > 0:
				all_prices.append(low)

		if all_prices.size() > 0:
			var min_price = all_prices[0]
			var max_price = all_prices[0]
			for price in all_prices:
				if price < min_price:
					min_price = price
				if price > max_price:
					max_price = price

			chart_center_price = (min_price + max_price) / 2.0

			# FIX: Handle case where all prices are the same
			var price_range = max_price - min_price
			if price_range <= 0:
				chart_price_range = max(chart_center_price * 0.2, 10000000.0)  # 20% of price or 10M ISK
				print("All prices same - created artificial range: %.2f" % chart_price_range)
			else:
				chart_price_range = price_range * 1.2  # Add 20% padding

			print("Set price center to %.2f, range %.2f (from all data)" % [chart_center_price, chart_price_range])
		else:
			# Ultimate fallback
			chart_center_price = 1000.0
			chart_price_range = 500.0
			print("Using fallback price center/range")


func get_visible_price_range() -> Dictionary:
	"""Get the price range of currently visible data"""
	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end

	var visible_prices = []

	# Collect visible price data
	for point in chart_data.price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_prices.append(point.price)

	# Collect visible candlestick data
	for candle in chart_data.candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			var high = candle.get("high", 0.0)
			var low = candle.get("low", 0.0)
			if high > 0:
				visible_prices.append(high)
			if low > 0:
				visible_prices.append(low)

	if visible_prices.size() == 0:
		return {"count": 0, "min_price": 0.0, "max_price": 0.0, "range": 0.0}

	var min_price = visible_prices[0]
	var max_price = visible_prices[0]

	for price in visible_prices:
		if price < min_price:
			min_price = price
		if price > max_price:
			max_price = price

	return {"count": visible_prices.size(), "min_price": min_price, "max_price": max_price, "range": max_price - min_price}


# Replace the problematic add_historical_data_point method in MarketChart.gd
func add_historical_data_point(price: float, volume: int, timestamp: float):
	"""Add a historical data point"""
	chart_data.add_historical_data_point(price, volume, timestamp)

	# Update the references (since we're using references to the arrays)
	price_data = chart_data.price_data
	volume_data = chart_data.volume_data

	if chart_data.price_data.size() == 1:
		# Initialize chart center for first historical point
		chart_center_price = price
		chart_price_range = max(price * 0.2, 10000000.0)
		chart_center_time = timestamp
		print("Initialized chart center from historical data: price=%.2f, range=%.2f" % [chart_center_price, chart_price_range])


func _rebuild_sorted_volume_data():
	"""Rebuild volume_data array to match the sorted price_data order"""
	# Create a temporary array with the correct order
	var temp_volume_data = []
	for point in price_data:
		temp_volume_data.append(point.volume)

	# Clear and refill the original array
	volume_data.clear()
	for vol in temp_volume_data:
		volume_data.append(vol)


func finish_historical_data_load():
	"""Called when historical data loading is complete"""
	print("=== FINISHING HISTORICAL DATA LOAD ===")
	chart_data.has_loaded_historical = true
	chart_data.is_loading_historical = false

	print("Historical data loaded: %d price points, %d volume points, %d candlesticks" % [chart_data.price_data.size(), chart_data.volume_data.size(), chart_data.candlestick_data.size()])

	# Initialize price center based on all data
	initialize_price_center()

	queue_redraw()


func request_historical_data():
	"""Request historical market data"""
	if chart_data.is_loading_historical:
		print("Already loading historical data, skipping...")
		return

	chart_data.is_loading_historical = true
	print("Requesting historical data for chart...")

	# Emit signal to request historical data
	emit_signal("historical_data_requested")


# Additional utility methods that were in the original
func get_timeframe_info() -> String:
	return "Market Data View"


func debug_chart_data():
	print("=== MARKET CHART DEBUG ===")
	var current_time = Time.get_unix_time_from_system()
	print("Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))
	print("Price data points: %d" % chart_data.price_data.size())
	print("Volume data points: %d" % chart_data.volume_data.size())
	print("Candlestick data points: %d" % chart_data.candlestick_data.size())
	print("Zoom level: %.2f" % zoom_level)
	print("Chart center time: %.0f" % chart_center_time)
	print("Chart center price: %.2f" % chart_center_price)
	print("Chart price range: %.2f" % chart_price_range)
	print("Has loaded historical: %s" % chart_data.has_loaded_historical)
	print("Is loading historical: %s" % chart_data.is_loading_historical)
	print("========================")


func debug_data_status():
	print("=== MARKET CHART DATA STATUS ===")
	print("Price data points: %d" % chart_data.price_data.size())
	print("Volume data points: %d" % chart_data.volume_data.size())
	print("Candlestick data points: %d" % chart_data.candlestick_data.size())
	print("Chart center time: %.0f" % chart_center_time)
	print("Chart center price: %.2f" % chart_center_price)
	print("Chart price range: %.2f" % chart_price_range)
	print("Chart size: %.1fx%.1f" % [size.x, size.y])

	if chart_data.price_data.size() > 0:
		print("First price point: %.2f at %.0f" % [chart_data.price_data[0].price, chart_data.price_data[0].timestamp])
		print("Last price point: %.2f at %.0f" % [chart_data.price_data[-1].price, chart_data.price_data[-1].timestamp])

	var bounds = chart_math.get_current_window_bounds()
	print("Window bounds: time %.0f-%.0f, price %.2f-%.2f" % [bounds.time_start, bounds.time_end, bounds.price_min, bounds.price_max])
	print("================================")


# Delegate mathematical functions
func get_current_time_window() -> float:
	return chart_math.get_current_time_window()


func get_time_at_pixel(x_pixel: float) -> float:
	return chart_math.get_time_at_pixel(x_pixel)


func get_price_at_pixel(y_pixel: float) -> float:
	return chart_math.get_price_at_pixel(y_pixel)


# Compatibility methods for any code that might reference these directly
func cleanup_old_data():
	chart_data.cleanup_old_data()


func get_min_price() -> float:
	return chart_data.get_min_price()


func get_max_price() -> float:
	return chart_data.get_max_price()


func get_max_volume() -> int:
	return chart_data.get_max_volume()


func get_station_trading_data() -> Dictionary:
	"""Get the current station trading data"""
	return chart_data.current_station_trading_data
