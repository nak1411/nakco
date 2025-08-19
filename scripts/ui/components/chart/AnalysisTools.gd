# scripts/ui/components/chart/AnalysisTools.gd
class_name AnalysisTools
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData
var chart_math: ChartMath

# Support/Resistance
var support_levels: Array[float] = []
var resistance_levels: Array[float] = []
var moving_average_period: int = 10

# Spread analysis
var current_buy_price: float = 0.0
var current_sell_price: float = 0.0
var spread_history: Array[Dictionary] = []
var max_spread_history: int = 100
var is_hovering_spread_zone: bool = false
var spread_tooltip_position: Vector2 = Vector2.ZERO

# Colors
var support_color: Color = Color.GREEN
var resistance_color: Color = Color.RED
var moving_average_color: Color = Color.CYAN
var profitable_spread_color: Color = Color.GREEN
var marginal_spread_color: Color = Color.YELLOW
var poor_spread_color: Color = Color.RED
var spread_line_color: Color = Color.CYAN


func setup(chart: MarketChart, data: ChartData, math: ChartMath):
	parent_chart = chart
	chart_data = data
	chart_math = math


# scripts/ui/components/chart/AnalysisTools.gd (continued)


func draw_support_resistance_lines():
	if support_levels.is_empty() and resistance_levels.is_empty():
		update_price_levels()

	var chart_bounds = chart_math.get_chart_boundaries()
	var bounds = chart_math.get_current_window_bounds()
	var price_range = bounds.price_max - bounds.price_min

	if price_range <= 0:
		return

	# Draw support levels
	for level in support_levels:
		if level >= bounds.price_min and level <= bounds.price_max:
			var price_progress = (level - bounds.price_min) / price_range
			var y = chart_bounds.top + chart_bounds.height - (price_progress * chart_bounds.height)

			parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), support_color, 2.0, false)

			# Draw support label
			var label_text = "S: %.2f" % level
			var font = ThemeDB.fallback_font
			var font_size = 10
			parent_chart.draw_string(font, Vector2(chart_bounds.right - 80, y - 5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, support_color)

	# Draw resistance levels
	for level in resistance_levels:
		if level >= bounds.price_min and level <= bounds.price_max:
			var price_progress = (level - bounds.price_min) / price_range
			var y = chart_bounds.top + chart_bounds.height - (price_progress * chart_bounds.height)

			parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), resistance_color, 2.0, false)

			# Draw resistance label
			var label_text = "R: %.2f" % level
			var font = ThemeDB.fallback_font
			var font_size = 10
			parent_chart.draw_string(font, Vector2(chart_bounds.right - 80, y + 15), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, resistance_color)

	# Draw moving average
	_draw_moving_average()


func _draw_moving_average():
	if chart_data.price_history.size() < moving_average_period:
		return

	var bounds = chart_math.get_current_window_bounds()
	var chart_bounds = chart_math.get_chart_boundaries()
	var price_range = bounds.price_max - bounds.price_min

	if price_range <= 0:
		return

	var ma_points: PackedVector2Array = []

	# Calculate moving average points
	for i in range(moving_average_period - 1, chart_data.price_data.size()):
		var point_data = chart_data.price_data[i]

		# Check if point is in visible window
		if point_data.timestamp >= bounds.time_start and point_data.timestamp <= bounds.time_end:
			var ma_value = _calculate_moving_average_at_index(i)

			var time_progress = (point_data.timestamp - bounds.time_start) / (bounds.time_end - bounds.time_start)
			var x = chart_bounds.left + (time_progress * chart_bounds.width)

			var price_progress = (ma_value - bounds.price_min) / price_range
			var y = chart_bounds.top + chart_bounds.height - (price_progress * chart_bounds.height)

			ma_points.append(Vector2(x, y))

	# Draw moving average line
	if ma_points.size() > 1:
		for i in range(ma_points.size() - 1):
			var p1 = ma_points[i]
			var p2 = ma_points[i + 1]

			var clip_rect = Rect2(Vector2(chart_bounds.left, chart_bounds.top), Vector2(chart_bounds.width, chart_bounds.height))
			var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

			if clipped_line.has("start") and clipped_line.has("end"):
				parent_chart.draw_line(clipped_line.start, clipped_line.end, moving_average_color, 2.0, true)


func draw_spread_analysis():
	if chart_data.current_station_trading_data.is_empty():
		return

	var chart_bounds = chart_math.get_chart_boundaries()
	var bounds = chart_math.get_current_window_bounds()
	var price_range = bounds.price_max - bounds.price_min

	if price_range <= 0:
		return

	# Get current buy/sell prices from station data
	var buy_orders = chart_data.current_station_trading_data.get("buy_orders", [])
	var sell_orders = chart_data.current_station_trading_data.get("sell_orders", [])

	if buy_orders.size() > 0 and sell_orders.size() > 0:
		current_buy_price = buy_orders[0].get("price", 0.0)
		current_sell_price = sell_orders[0].get("price", 0.0)

		# Draw buy/sell price lines
		_draw_spread_lines(current_buy_price, current_sell_price, bounds, chart_bounds, price_range)

		# Draw spread zone
		_draw_spread_zone(current_buy_price, current_sell_price, bounds, chart_bounds, price_range)

		# Draw spread info
		_draw_spread_info(current_buy_price, current_sell_price)


func _draw_spread_lines(buy_price: float, sell_price: float, bounds: Dictionary, chart_bounds: Dictionary, price_range: float):
	# Draw buy price line
	if buy_price >= bounds.price_min and buy_price <= bounds.price_max:
		var buy_progress = (buy_price - bounds.price_min) / price_range
		var buy_y = chart_bounds.top + chart_bounds.height - (buy_progress * chart_bounds.height)

		parent_chart.draw_line(Vector2(chart_bounds.left, buy_y), Vector2(chart_bounds.right, buy_y), Color.GREEN, 2.0, true)

		# Buy label
		var font = ThemeDB.fallback_font
		var font_size = 10
		var buy_text = "BUY: %.2f" % buy_price
		parent_chart.draw_string(font, Vector2(chart_bounds.left + 10, buy_y - 5), buy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)

	# Draw sell price line
	if sell_price >= bounds.price_min and sell_price <= bounds.price_max:
		var sell_progress = (sell_price - bounds.price_min) / price_range
		var sell_y = chart_bounds.top + chart_bounds.height - (sell_progress * chart_bounds.height)

		parent_chart.draw_line(Vector2(chart_bounds.left, sell_y), Vector2(chart_bounds.right, sell_y), Color.RED, 2.0, true)

		# Sell label
		var font = ThemeDB.fallback_font
		var font_size = 10
		var sell_text = "SELL: %.2f" % sell_price
		parent_chart.draw_string(font, Vector2(chart_bounds.left + 10, sell_y + 15), sell_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.RED)


func _draw_spread_zone(buy_price: float, sell_price: float, bounds: Dictionary, chart_bounds: Dictionary, price_range: float):
	if buy_price >= bounds.price_max or sell_price <= bounds.price_min:
		return

	var buy_progress = (buy_price - bounds.price_min) / price_range
	var sell_progress = (sell_price - bounds.price_min) / price_range

	var buy_y = chart_bounds.top + chart_bounds.height - (buy_progress * chart_bounds.height)
	var sell_y = chart_bounds.top + chart_bounds.height - (sell_progress * chart_bounds.height)

	# Clamp to chart bounds
	buy_y = max(chart_bounds.top, min(buy_y, chart_bounds.bottom))
	sell_y = max(chart_bounds.top, min(sell_y, chart_bounds.bottom))

	if sell_y < buy_y:  # Ensure sell is above buy
		var spread_height = buy_y - sell_y
		var spread_rect = Rect2(chart_bounds.left, sell_y, chart_bounds.width, spread_height)

		# Color based on spread percentage
		var spread_percent = ((sell_price - buy_price) / buy_price) * 100.0 if buy_price > 0 else 0.0
		var spread_color: Color

		if spread_percent > 5.0:
			spread_color = profitable_spread_color
		elif spread_percent > 2.0:
			spread_color = marginal_spread_color
		else:
			spread_color = poor_spread_color

		spread_color.a = 0.2  # Semi-transparent
		parent_chart.draw_rect(spread_rect, spread_color, true)


func _draw_spread_info(buy_price: float, sell_price: float):
	if buy_price <= 0 or sell_price <= 0:
		return

	var spread = sell_price - buy_price
	var spread_percent = (spread / buy_price) * 100.0

	var info_text = "Spread: %.2f (%.1f%%)" % [spread, spread_percent]
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text_size = font.get_string_size(info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var bg_rect = Rect2(10, 10, text_size.x + 16, text_size.y + 8)
	var bg_color = Color(0.1, 0.1, 0.15, 0.9)

	parent_chart.draw_rect(bg_rect, bg_color)
	parent_chart.draw_rect(bg_rect, spread_line_color, false, 1.0)
	parent_chart.draw_string(font, Vector2(bg_rect.position.x + 8, bg_rect.position.y + text_size.y + 2), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func update_price_levels():
	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end

	support_levels.clear()
	resistance_levels.clear()

	var visible_points = []
	var visible_candles = []

	for point in chart_data.price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_points.append(point)

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			visible_candles.append(candle)

	if visible_points.size() < 5:
		return

	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Collect all prices with volume weighting
	var all_prices = []
	var volume_weighted_prices = {}

	for point in visible_points:
		all_prices.append(point.price)
		var volume = point.get("volume", 1)
		var price_key = int(point.price / 5.0) * 5.0  # Group into 5 ISK buckets
		if not volume_weighted_prices.has(price_key):
			volume_weighted_prices[price_key] = 0
		volume_weighted_prices[price_key] += volume

	for candle in visible_candles:
		var high = candle.get("high", 0.0)
		var low = candle.get("low", 0.0)
		var volume = candle.get("volume", 1)

		if high > 0:
			all_prices.append(high)
			var price_key = int(high / 5.0) * 5.0
			if not volume_weighted_prices.has(price_key):
				volume_weighted_prices[price_key] = 0
			volume_weighted_prices[price_key] += volume

		if low > 0:
			all_prices.append(low)
			var price_key = int(low / 5.0) * 5.0
			if not volume_weighted_prices.has(price_key):
				volume_weighted_prices[price_key] = 0
			volume_weighted_prices[price_key] += volume

	if all_prices.size() < 5:
		return

	# Find the top volume-weighted price levels
	var sorted_volume_prices = []
	for price_key in volume_weighted_prices.keys():
		sorted_volume_prices.append({"price": price_key, "volume": volume_weighted_prices[price_key]})

	sorted_volume_prices.sort_custom(func(a, b): return a.volume > b.volume)

	# Get current price for classification
	var current_price = chart_data.get_latest_price()
	if current_price <= 0 and all_prices.size() > 0:
		current_price = all_prices[-1]

	# Classify levels as support or resistance
	for i in range(min(4, sorted_volume_prices.size())):
		var level_price = sorted_volume_prices[i].price

		if level_price < current_price:
			support_levels.append(level_price)
		else:
			resistance_levels.append(level_price)

	print("Updated S/R levels - Support: %s, Resistance: %s" % [support_levels, resistance_levels])


func update_spread_analysis(data: Dictionary):
	# Store spread data for historical analysis
	var timestamp = Time.get_unix_time_from_system()
	var buy_orders = data.get("buy_orders", [])
	var sell_orders = data.get("sell_orders", [])

	if buy_orders.size() > 0 and sell_orders.size() > 0:
		var buy_price = buy_orders[0].get("price", 0.0)
		var sell_price = sell_orders[0].get("price", 0.0)
		var spread = sell_price - buy_price
		var spread_percent = (spread / buy_price) * 100.0 if buy_price > 0 else 0.0

		var spread_data = {"timestamp": timestamp, "buy_price": buy_price, "sell_price": sell_price, "spread": spread, "spread_percent": spread_percent}

		spread_history.append(spread_data)

		# Keep only recent spread history
		while spread_history.size() > max_spread_history:
			spread_history.pop_front()


func _calculate_moving_average_at_index(index: int) -> float:
	if index < moving_average_period - 1:
		return 0.0

	var sum = 0.0
	var start_index = index - moving_average_period + 1

	for i in range(start_index, index + 1):
		sum += chart_data.price_history[i]

	return sum / moving_average_period


func toggle_support_resistance():
	parent_chart.show_support_resistance = not parent_chart.show_support_resistance
	print("Support/Resistance lines: %s" % ("ON" if parent_chart.show_support_resistance else "OFF"))

	if parent_chart.show_support_resistance:
		update_price_levels()

	parent_chart.queue_redraw()


func toggle_spread_analysis():
	parent_chart.show_spread_analysis = not parent_chart.show_spread_analysis
	print("Spread analysis: %s" % ("ON" if parent_chart.show_spread_analysis else "OFF"))
	parent_chart.queue_redraw()


func set_moving_average_period(period: int):
	moving_average_period = max(1, period)
	print("Moving average period set to: ", moving_average_period)


func check_spread_zone_hover(mouse_position: Vector2):
	# Check if mouse is hovering over spread zone
	if chart_data.current_station_trading_data.is_empty():
		return

	var buy_orders = chart_data.current_station_trading_data.get("buy_orders", [])
	var sell_orders = chart_data.current_station_trading_data.get("sell_orders", [])

	if buy_orders.size() > 0 and sell_orders.size() > 0:
		var buy_price = buy_orders[0].get("price", 0.0)
		var sell_price = sell_orders[0].get("price", 0.0)

		var mouse_price = chart_math.get_price_at_pixel(mouse_position.y)

		if mouse_price >= buy_price and mouse_price <= sell_price:
			is_hovering_spread_zone = true
			spread_tooltip_position = mouse_position
		else:
			is_hovering_spread_zone = false
