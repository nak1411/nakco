# scripts/ui/components/chart/AnalysisTools.gd
class_name AnalysisTools
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData
var chart_math: ChartMath

var support_resistance_button: Button = null
var spread_analysis_button: Button = null

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

# Donchian Channel
var donchian_period: int = 20  # Default 20-period channel
var donchian_upper_line: Array[Vector2] = []
var donchian_lower_line: Array[Vector2] = []
var donchian_middle_line: Array[Vector2] = []

# Colors for Donchian channel
var donchian_upper_color: Color = Color(0.2, 0.8, 0.2, 1.0)
var donchian_lower_color: Color = Color(0.8, 0.2, 0.2, 1.0)
var donchian_middle_color: Color = Color(0.6, 0.6, 0.8, 0.8)

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


func set_toggle_buttons(sr_button: Button, sa_button: Button):
	support_resistance_button = sr_button
	spread_analysis_button = sa_button

	# Set initial button text based on current state
	update_button_texts()


func update_button_texts():
	"""Update button text to reflect current toggle states"""
	if support_resistance_button:
		support_resistance_button.text = "S/R Lines: %s" % ("ON" if parent_chart.show_support_resistance else "OFF")

	if spread_analysis_button:
		spread_analysis_button.text = "Spread Analysis: %s" % ("ON" if parent_chart.show_spread_analysis else "OFF")


func toggle_support_resistance():
	parent_chart.show_support_resistance = not parent_chart.show_support_resistance
	print("Support/Resistance lines: %s" % ("ON" if parent_chart.show_support_resistance else "OFF"))

	if parent_chart.show_support_resistance:
		update_price_levels()

	# Update button text
	update_button_texts()

	parent_chart.queue_redraw()


func toggle_spread_analysis():
	parent_chart.show_spread_analysis = not parent_chart.show_spread_analysis
	print("Spread analysis: %s" % ("ON" if parent_chart.show_spread_analysis else "OFF"))

	# Update button text
	update_button_texts()

	parent_chart.queue_redraw()


func draw_support_resistance_lines():
	if support_levels.is_empty() and resistance_levels.is_empty():
		update_price_levels()

	# Use EXACT same coordinate system as grid and Y-axis labels
	var chart_height = parent_chart.size.y * 0.7  # EXACT same as grid
	var chart_y_offset = parent_chart.size.y * 0.00  # EXACT same as grid
	var chart_bounds = chart_math.get_chart_boundaries()  # Only for left/right bounds

	var bounds = chart_math.get_current_window_bounds()
	var price_range = bounds.price_max - bounds.price_min

	if price_range <= 0:
		return

	# Draw support levels
	for level in support_levels:
		if level >= bounds.price_min and level <= bounds.price_max:
			var price_progress = (level - bounds.price_min) / price_range
			var y = chart_y_offset + chart_height - (price_progress * chart_height)

			parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), support_color, 1.0, false)

			# Draw support label
			var label_text = "S: %.2f" % level
			var font = ThemeDB.fallback_font
			var font_size = 10
			parent_chart.draw_string(font, Vector2(chart_bounds.right - 80, y - 5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, support_color)

	# Draw resistance levels
	for level in resistance_levels:
		if level >= bounds.price_min and level <= bounds.price_max:
			var price_progress = (level - bounds.price_min) / price_range
			var y = chart_y_offset + chart_height - (price_progress * chart_height)

			parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), resistance_color, 1.0, false)

			# Draw resistance label
			var label_text = "R: %.2f" % level
			var font = ThemeDB.fallback_font
			var font_size = 10
			parent_chart.draw_string(font, Vector2(chart_bounds.right - 80, y + 15), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, resistance_color)


func draw_donchian_channel():
	"""Draw Donchian channel bands"""
	if not parent_chart.show_donchian_channel:
		return

	var visible_data = _get_visible_candlestick_data()
	if visible_data.size() < donchian_period:
		print("Not enough data for Donchian channel (need %d, have %d)" % [donchian_period, visible_data.size()])
		return

	print("Drawing Donchian channel with %d periods" % donchian_period)

	var bounds = chart_math.get_current_window_bounds()
	var chart_bounds = chart_math.get_chart_boundaries()

	# Calculate Donchian channel lines
	_calculate_donchian_lines(visible_data, bounds, chart_bounds)

	# Draw the channel
	_draw_donchian_lines()


func _get_visible_candlestick_data() -> Array:
	"""Get candlestick data within the current time window with zoom-aware buffer"""
	var bounds = chart_math.get_current_window_bounds()
	var visible_candles = []
	var zoom_level = parent_chart.zoom_level

	# CRITICAL FIX: Use much larger buffer for close zoom levels (same as MA lines)
	var time_window = bounds.time_end - bounds.time_start

	# Scale buffer based on zoom level - more zoomed in = larger buffer needed
	var buffer_multiplier = max(0.5, zoom_level / 10.0)  # Minimum 50%, scales up with zoom
	var buffer_time = time_window * buffer_multiplier

	print("Donchian data collection: zoom %.1fx, buffer %.0fs (%.1f%% of window)" % [zoom_level, buffer_time, buffer_multiplier * 100])

	var start_time = bounds.time_start - buffer_time
	var end_time = bounds.time_end + buffer_time

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= start_time and candle.timestamp <= end_time:
			visible_candles.append(candle)

	# Sort by timestamp
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	print("Found %d candles for Donchian calculation (with %.0fs buffer)" % [visible_candles.size(), buffer_time])

	return visible_candles


func _calculate_donchian_lines(candles: Array, bounds: Dictionary, chart_bounds: Dictionary):
	"""Calculate Donchian channel lines with zoom-aware data handling"""
	donchian_upper_line.clear()
	donchian_lower_line.clear()
	donchian_middle_line.clear()

	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var price_min = bounds.price_min
	var price_range = bounds.price_max - bounds.price_min
	var zoom_level = parent_chart.zoom_level

	if price_range <= 0 or candles.size() < donchian_period:
		print("Insufficient data for Donchian: price_range=%.2f, candles=%d, need_period=%d" % [price_range, candles.size(), donchian_period])
		return

	print("Calculating Donchian lines: %d candles, zoom %.1fx, period %d" % [candles.size(), zoom_level, donchian_period])

	# IMPROVED: Use zoom-aware calculation range
	var time_window = window_end - window_start
	var buffer_multiplier = max(0.5, zoom_level / 10.0)
	var calculation_buffer = time_window * buffer_multiplier

	for i in range(donchian_period - 1, candles.size()):
		var current_candle = candles[i]

		# IMPROVED: Use zoom-aware range checking
		if current_candle.timestamp < window_start - calculation_buffer:
			continue
		if current_candle.timestamp > window_end + calculation_buffer:
			break

		# Find highest high and lowest low in the period
		var highest_high = 0.0
		var lowest_low = 999999999999.0

		for j in range(max(0, i - donchian_period + 1), min(candles.size(), i + 1)):
			var candle = candles[j]
			var high = candle.get("high", 0.0)
			var low = candle.get("low", 0.0)

			if high > 0 and high > highest_high:
				highest_high = high
			if low > 0 and low < lowest_low:
				lowest_low = low

		# Skip if we don't have valid data
		if highest_high <= 0 or lowest_low >= 999999999999.0:
			continue

		# Calculate middle line (average of upper and lower)
		var middle_price = (highest_high + lowest_low) / 2.0

		# Convert to screen coordinates
		var time_progress = (current_candle.timestamp - window_start) / (window_end - window_start)
		var x = chart_bounds.left + (time_progress * chart_bounds.width)

		# IMPROVED: Use zoom-aware visibility range (same as MA lines)
		var visibility_buffer = 100.0 * max(1.0, zoom_level / 5.0)  # Scale buffer with zoom
		if x >= chart_bounds.left - visibility_buffer and x <= chart_bounds.right + visibility_buffer:
			# Upper line
			var upper_progress = (highest_high - price_min) / price_range
			var upper_y = chart_bounds.top + chart_bounds.height - (upper_progress * chart_bounds.height)
			donchian_upper_line.append(Vector2(x, upper_y))

			# Lower line
			var lower_progress = (lowest_low - price_min) / price_range
			var lower_y = chart_bounds.top + chart_bounds.height - (lower_progress * chart_bounds.height)
			donchian_lower_line.append(Vector2(x, lower_y))

			# Middle line
			var middle_progress = (middle_price - price_min) / price_range
			var middle_y = chart_bounds.top + chart_bounds.height - (middle_progress * chart_bounds.height)
			donchian_middle_line.append(Vector2(x, middle_y))

	print("Generated %d Donchian points with zoom-aware calculation" % donchian_upper_line.size())


func _draw_donchian_lines():
	"""Draw only the Donchian channel top and bottom lines (no fill)"""
	var chart_bounds = chart_math.get_chart_boundaries()
	var zoom_level = parent_chart.zoom_level

	# Use expanded clipping rectangle for better edge handling at high zoom
	var expanded_clip_rect = Rect2(Vector2(chart_bounds.left, chart_bounds.top), Vector2(chart_bounds.width, chart_bounds.height))
	var clip_rect = Rect2(Vector2(chart_bounds.left, chart_bounds.top), Vector2(chart_bounds.width, chart_bounds.height))

	print("Drawing Donchian lines (top/bottom only) with zoom level: %.1f" % zoom_level)

	# Draw upper line (resistance/top of channel)
	for i in range(donchian_upper_line.size() - 1):
		var p1 = donchian_upper_line[i]
		var p2 = donchian_upper_line[i + 1]

		# Use same logic as MA lines for gap handling
		var time_diff = _get_time_diff_for_donchian_points(i, i + 1)
		var max_time_gap = 86400.0 * 2  # Base: 2 days
		if zoom_level > 10:  # When zoomed in close
			max_time_gap = 86400.0 * 30  # Allow much larger gaps (30 days)

		if time_diff <= max_time_gap:
			if _is_point_in_rect(p1, expanded_clip_rect) or _is_point_in_rect(p2, expanded_clip_rect) or _line_intersects_rect(p1, p2, expanded_clip_rect):
				var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

				if clipped_line.has("start") and clipped_line.has("end"):
					parent_chart.draw_line(clipped_line.start, clipped_line.end, donchian_upper_color, 2.0, true)
				else:
					if _is_point_in_rect(p1, clip_rect) or _is_point_in_rect(p2, clip_rect):
						parent_chart.draw_line(p1, p2, donchian_upper_color, 2.0, true)

	# Draw lower line (support/bottom of channel)
	for i in range(donchian_lower_line.size() - 1):
		var p1 = donchian_lower_line[i]
		var p2 = donchian_lower_line[i + 1]

		var time_diff = _get_time_diff_for_donchian_points(i, i + 1)
		var max_time_gap = 86400.0 * 2  # Base: 2 days
		if zoom_level > 10:  # When zoomed in close
			max_time_gap = 86400.0 * 30  # Allow much larger gaps (30 days)

		if time_diff <= max_time_gap:
			if _is_point_in_rect(p1, expanded_clip_rect) or _is_point_in_rect(p2, expanded_clip_rect) or _line_intersects_rect(p1, p2, expanded_clip_rect):
				var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

				if clipped_line.has("start") and clipped_line.has("end"):
					parent_chart.draw_line(clipped_line.start, clipped_line.end, donchian_lower_color, 2.0, true)
				else:
					if _is_point_in_rect(p1, clip_rect) or _is_point_in_rect(p2, clip_rect):
						parent_chart.draw_line(p1, p2, donchian_lower_color, 2.0, true)


func _get_time_diff_for_donchian_points(index1: int, index2: int) -> float:
	"""Get time difference between two Donchian points (approximated from screen coordinates)"""

	var bounds = chart_math.get_current_window_bounds()
	var chart_bounds = chart_math.get_chart_boundaries()
	var time_window = bounds.time_end - bounds.time_start

	if donchian_upper_line.size() <= max(index1, index2):
		return 999999.0  # Return large value to skip

	var p1 = donchian_upper_line[index1]
	var p2 = donchian_upper_line[index2]

	# Convert screen X coordinates back to time difference
	var x_diff = abs(p2.x - p1.x)
	var chart_width = chart_bounds.width

	if chart_width > 0:
		var time_progress_diff = x_diff / chart_width
		return time_progress_diff * time_window

	return 0.0


func draw_spread_analysis():
	"""Draw spread analysis with dashed lines and hover tooltips"""
	if not parent_chart.show_spread_analysis:
		return

	if current_buy_price <= 0 or current_sell_price <= 0:
		return

	# Get current window bounds
	var bounds = chart_math.get_current_window_bounds()
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	if price_range <= 0:
		return

	# Get chart boundaries
	var chart_bounds = chart_math.get_chart_boundaries()

	# Draw buy/sell price lines with dashed lines
	_draw_spread_lines_with_dashes(current_buy_price, current_sell_price, bounds, chart_bounds, price_range)

	# Draw spread zone
	_draw_spread_zone(current_buy_price, current_sell_price, bounds, chart_bounds, price_range)

	# Draw hover tooltip if hovering spread zone
	if is_hovering_spread_zone:
		var spread = current_sell_price - current_buy_price
		var margin_pct = (spread / current_sell_price) * 100.0 if current_sell_price > 0 else 0.0
		_draw_spread_hover_tooltip(spread, margin_pct)


func _draw_spread_lines(buy_price: float, sell_price: float, bounds: Dictionary, chart_bounds: Dictionary, price_range: float):
	"""Draw buy and sell price lines"""
	print("=== DRAWING SPREAD LINES ===")
	var font = ThemeDB.fallback_font
	var font_size = 10

	# Draw buy price line
	if buy_price >= bounds.price_min and buy_price <= bounds.price_max:
		var buy_progress = (buy_price - bounds.price_min) / price_range
		var buy_y = chart_bounds.top + chart_bounds.height - (buy_progress * chart_bounds.height)

		print("Drawing BUY line at y=%.1f (price=%.2f, progress=%.3f)" % [buy_y, buy_price, buy_progress])
		_draw_dashed_line(Vector2(chart_bounds.left, buy_y), Vector2(chart_bounds.right, buy_y), Color.GREEN, 1.0)

		# Buy label
		var buy_text = "BUY: %s" % _format_price_compact(buy_price)
		parent_chart.draw_string(font, Vector2(chart_bounds.left + 10, buy_y - 5), buy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)
		print("Drew BUY label: %s" % buy_text)
	else:
		print("BUY price %.2f outside visible range %.2f-%.2f" % [buy_price, bounds.price_min, bounds.price_max])

	# Draw sell price line
	if sell_price >= bounds.price_min and sell_price <= bounds.price_max:
		var sell_progress = (sell_price - bounds.price_min) / price_range
		var sell_y = chart_bounds.top + chart_bounds.height - (sell_progress * chart_bounds.height)

		print("Drawing SELL line at y=%.1f (price=%.2f, progress=%.3f)" % [sell_y, sell_price, sell_progress])
		_draw_dashed_line(Vector2(chart_bounds.left, sell_y), Vector2(chart_bounds.right, sell_y), Color.RED, 1.0)

		# Sell label
		var sell_text = "SELL: %s" % _format_price_compact(sell_price)
		parent_chart.draw_string(font, Vector2(chart_bounds.left + 10, sell_y + 15), sell_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.RED)
		print("Drew SELL label: %s" % sell_text)
	else:
		print("SELL price %.2f outside visible range %.2f-%.2f" % [sell_price, bounds.price_min, bounds.price_max])

	print("=== SPREAD LINES DRAWING COMPLETE ===")


func _draw_spread_zone(buy_price: float, sell_price: float, bounds: Dictionary, chart_bounds: Dictionary, price_range: float):
	"""Draw spread zone using EXACT same coordinate system as grid"""
	if buy_price >= bounds.price_max or sell_price <= bounds.price_min:
		return

	var buy_progress = (buy_price - bounds.price_min) / price_range
	var sell_progress = (sell_price - bounds.price_min) / price_range

	var buy_y = chart_bounds.top + chart_bounds.height - (buy_progress * chart_bounds.height)
	var sell_y = chart_bounds.top + chart_bounds.height - (sell_progress * chart_bounds.height)

	# Determine the visible portion of the spread zone
	var zone_top = max(min(buy_y, sell_y), chart_bounds.top)
	var zone_bottom = min(max(buy_y, sell_y), chart_bounds.bottom)

	# Only draw if there's a visible portion
	if zone_bottom > zone_top:
		var spread = sell_price - buy_price
		var margin_pct = (spread / sell_price) * 100.0 if sell_price > 0 else 0.0

		var zone_color = _get_spread_color(margin_pct)
		zone_color.a = 0.15  # Make it semi-transparent

		# Use chart_bounds for horizontal positioning but our calculated Y positions
		var zone_rect = Rect2(Vector2(chart_bounds.left, zone_top), Vector2(chart_bounds.width, zone_bottom - zone_top))
		parent_chart.draw_rect(zone_rect, zone_color)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float):
	"""Draw a dashed line"""
	print("Drawing dashed line from (%.1f,%.1f) to (%.1f,%.1f) color %s" % [from.x, from.y, to.x, to.y, color])

	var dash_length = 8.0
	var gap_length = 4.0
	var direction = (to - from).normalized()
	var total_length = from.distance_to(to)
	var current_pos = from
	var distance_traveled = 0.0
	var drawing = true
	var segments_drawn = 0

	while distance_traveled < total_length:
		var remaining_distance = total_length - distance_traveled
		var segment_length = min(dash_length if drawing else gap_length, remaining_distance)
		var end_pos = current_pos + direction * segment_length

		if drawing:
			parent_chart.draw_line(current_pos, end_pos, color, width, false)
			segments_drawn += 1

		current_pos = end_pos
		distance_traveled += segment_length
		drawing = not drawing

	print("Drew %d dashed line segments" % segments_drawn)


func _get_spread_color(margin_pct: float) -> Color:
	"""Get color based on spread margin percentage"""
	if margin_pct >= 10.0:
		return profitable_spread_color  # Excellent - 10%+ margin
	if margin_pct >= 5.0:
		return marginal_spread_color  # Good - 5-10% margin
	if margin_pct >= 2.0:
		return Color.ORANGE  # Marginal - 2-5% margin

	return poor_spread_color  # Poor - <2% margin


func _store_spread_zone_info(zone_rect: Rect2, spread: float, margin_pct: float):
	"""Store spread zone information for hover detection"""
	# Store in parent chart for hover detection
	if parent_chart.chart_interaction:
		parent_chart.chart_interaction.spread_zone_rect = zone_rect
		parent_chart.chart_interaction.spread_value = spread
		parent_chart.chart_interaction.spread_margin = margin_pct


func _draw_spread_hover_tooltip(spread: float, margin_pct: float):
	"""Draw station trading information tooltip when hovering spread zone"""
	var font = ThemeDB.fallback_font
	var font_size = 12

	var lines = []

	# Always show the larger detailed tooltip format
	lines = [
		"STATION TRADING OPPORTUNITY",
		"",
		"Your Buy Order: %s ISK" % _format_price_label(current_buy_price),
		"Your Sell Order: %s ISK" % _format_price_label(current_sell_price),
		"",
		"Cost (with fees): %s ISK" % _format_price_label(current_buy_price),
		"Income (after taxes): %s ISK" % _format_price_label(current_sell_price),
		"",
		"Profit: %s ISK per unit" % _format_price_label(spread),
		"Margin: %.2f%%" % margin_pct,
		"",
		_get_station_trading_quality_text(margin_pct)
	]

	var max_width = 0.0
	var line_height = 16

	# Calculate tooltip dimensions
	for line in lines:
		if line.length() > 0:
			var text_size = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			max_width = max(max_width, text_size.x)

	var padding = Vector2(12, 8)
	var tooltip_width = max_width + padding.x * 2
	var tooltip_height = lines.size() * line_height + padding.y * 2

	# Position tooltip near mouse, but keep it on screen
	var tooltip_pos = spread_tooltip_position + Vector2(15, -tooltip_height / 2)

	# Keep tooltip within screen bounds
	if tooltip_pos.x + tooltip_width > parent_chart.size.x:
		tooltip_pos.x = spread_tooltip_position.x - tooltip_width - 15
	if tooltip_pos.y < 0:
		tooltip_pos.y = 5
	if tooltip_pos.y + tooltip_height > parent_chart.size.y:
		tooltip_pos.y = parent_chart.size.y - tooltip_height - 5

	# Background with profit quality color border
	var bg_color = Color(0.05, 0.08, 0.12, 0.95)
	var border_color = _get_station_trading_color(margin_pct)

	parent_chart.draw_rect(Rect2(tooltip_pos, Vector2(tooltip_width, tooltip_height)), bg_color)
	parent_chart.draw_rect(Rect2(tooltip_pos, Vector2(tooltip_width, tooltip_height)), border_color, false, 2.0)

	# Draw text lines
	for i in range(lines.size()):
		var line = lines[i]
		if line.length() == 0:
			continue

		var text_pos = tooltip_pos + Vector2(padding.x, padding.y + (i + 1) * line_height)
		var text_color = Color.WHITE

		# Color code different lines
		if i == 0:  # Header
			text_color = Color.CYAN
		elif line.contains("Profit:") or line.contains("Margin:"):
			text_color = _get_station_trading_color(margin_pct)
		elif line.contains("EXCELLENT") or line.contains("GOOD") or line.contains("MARGINAL") or line.contains("POOR"):
			text_color = _get_station_trading_color(margin_pct)
		elif line.contains("Your Buy Order:"):
			text_color = Color.GREEN
		elif line.contains("Your Sell Order:"):
			text_color = Color.RED
		elif line.contains("Cost"):
			text_color = Color.ORANGE
		elif line.contains("Income"):
			text_color = Color.LIGHT_GREEN

		parent_chart.draw_string(font, text_pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


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


func _draw_spread_lines_with_dashes(buy_price: float, sell_price: float, bounds: Dictionary, chart_bounds: Dictionary, price_range: float):
	"""Draw dashed lines for buy and sell prices using EXACT same coordinate system as grid"""

	# Draw buy price line (dashed)
	if buy_price >= bounds.price_min and buy_price <= bounds.price_max:
		var buy_progress = (buy_price - bounds.price_min) / price_range
		var buy_y = chart_bounds.top + chart_bounds.height - (buy_progress * chart_bounds.height)

		_draw_dotted_horizontal_line(buy_y, Color.GREEN, "BUY: %s" % _format_price_label(buy_price))

	# Draw sell price line (dashed)
	if sell_price >= bounds.price_min and sell_price <= bounds.price_max:
		var sell_progress = (sell_price - bounds.price_min) / price_range
		var sell_y = chart_bounds.top + chart_bounds.height - (sell_progress * chart_bounds.height)

		_draw_dotted_horizontal_line(sell_y, Color.RED, "SELL: %s" % _format_price_label(sell_price))


func _draw_dotted_horizontal_line(y_pos: float, line_color: Color, label_text: String):
	"""Draw a dotted horizontal line across the chart with a label"""
	var dash_length = 8.0
	var gap_length = 4.0
	var x = 0.0
	var chart_bounds = chart_math.get_chart_boundaries()

	# Draw dotted line
	while x < chart_bounds.width:
		var dash_end = min(x + dash_length, chart_bounds.width)
		parent_chart.draw_line(Vector2(chart_bounds.left + x, y_pos), Vector2(chart_bounds.left + dash_end, y_pos), line_color, 1.5)
		x += dash_length + gap_length

	# Draw label on the right side
	var font = ThemeDB.fallback_font
	var font_size = 10
	var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding = Vector2(6, 3)

	# Position label on the right side
	var label_x = chart_bounds.right - text_size.x - padding.x * 2 - 5
	var label_y = y_pos - text_size.y / 2 - padding.y

	# Background for label
	var bg_rect = Rect2(Vector2(label_x, label_y), Vector2(text_size.x + padding.x * 2, text_size.y + padding.y * 2))
	parent_chart.draw_rect(bg_rect, Color(0.1, 0.1, 0.15, 0.9))
	parent_chart.draw_rect(bg_rect, line_color, false, 1.0)

	# Draw label text
	var text_y = label_y + padding.y + text_size.y - 2
	parent_chart.draw_string(font, Vector2(label_x + padding.x, text_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func update_price_levels():
	"""Calculate support and resistance levels from ALL available data, not just visible data"""
	print("Calculating S/R levels from all available data...")

	# ALWAYS clear previous levels first
	support_levels.clear()
	resistance_levels.clear()

	# Use ALL available data, not just visible data
	var all_points = chart_data.price_data
	var all_candles = chart_data.candlestick_data

	if all_points.size() < 10:  # Need minimum data for meaningful levels
		print("Not enough total data points (%d) for support/resistance calculation" % all_points.size())
		return

	# Collect ALL prices from the entire dataset
	var all_prices = []
	var volume_weighted_prices = {}

	# Get all price data
	for point in all_points:
		all_prices.append(point.price)
		var volume = point.get("volume", 1)
		var price_key = int(point.price / 100.0) * 100.0  # Group into 100 ISK buckets
		if not volume_weighted_prices.has(price_key):
			volume_weighted_prices[price_key] = 0
		volume_weighted_prices[price_key] += volume

	# Add all candlestick data
	for candle in all_candles:
		var high = candle.get("high", 0.0)
		var low = candle.get("low", 0.0)
		var volume = candle.get("volume", 1)

		if high > 0:
			all_prices.append(high)
			var price_key = int(high / 100.0) * 100.0
			if not volume_weighted_prices.has(price_key):
				volume_weighted_prices[price_key] = 0
			volume_weighted_prices[price_key] += volume

		if low > 0:
			all_prices.append(low)
			var price_key = int(low / 100.0) * 100.0
			if not volume_weighted_prices.has(price_key):
				volume_weighted_prices[price_key] = 0
			volume_weighted_prices[price_key] += volume

	if all_prices.size() == 0:
		return

	all_prices.sort()

	# Calculate stable support/resistance using percentiles of ALL data
	var support_candidates = []
	var resistance_candidates = []

	# Use 20th and 80th percentiles as base levels (more stable than visible-only data)
	var percentile_20_idx = int(all_prices.size() * 0.2)
	var percentile_80_idx = int(all_prices.size() * 0.8)

	support_candidates.append(all_prices[percentile_20_idx])
	resistance_candidates.append(all_prices[percentile_80_idx])

	# Add volume-weighted significant levels from ALL data
	var total_volume = 0
	for volume in volume_weighted_prices.values():
		total_volume += volume

	if total_volume > 0:
		var global_min_price = all_prices[0]
		var global_max_price = all_prices[-1]
		var global_midpoint = (global_min_price + global_max_price) / 2.0

		for price_key in volume_weighted_prices.keys():
			var volume = volume_weighted_prices[price_key]
			var volume_percentage = float(volume) / total_volume

			if volume_percentage > 0.05:  # Significant volume (5%+) from ALL data
				if price_key < global_midpoint:  # Lower half = support candidate
					support_candidates.append(price_key)
				else:  # Upper half = resistance candidate
					resistance_candidates.append(price_key)

	# Select best stable levels
	if support_candidates.size() > 0:
		support_candidates.sort()
		# Use the highest support level that has significant volume
		var best_support = support_candidates[-1]  # Highest support
		support_levels.append(best_support)

	if resistance_candidates.size() > 0:
		resistance_candidates.sort()
		# Use the lowest resistance level that has significant volume
		var best_resistance = resistance_candidates[0]  # Lowest resistance
		resistance_levels.append(best_resistance)

	print(
		(
			"Stable S/R levels calculated - Support: %.2f, Resistance: %.2f (from %d total price points)"
			% [support_levels[0] if support_levels.size() > 0 else 0.0, resistance_levels[0] if resistance_levels.size() > 0 else 0.0, all_prices.size()]
		)
	)


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


func set_moving_average_period(period: int):
	moving_average_period = max(1, period)
	print("Moving average period set to: ", moving_average_period)


func check_spread_zone_hover(mouse_position: Vector2):
	"""Check if mouse is hovering over the spread zone using EXACT same coordinate system as grid"""
	# Don't show spread tooltip if already hovering a data point or volume bar
	if parent_chart.chart_interaction.hovered_point_index != -1 or parent_chart.chart_interaction.hovered_volume_index != -1:
		is_hovering_spread_zone = false
		return

	if current_buy_price <= 0 or current_sell_price <= 0:
		is_hovering_spread_zone = false
		return

	# Use the same bounds calculation as drawing
	var bounds = chart_math.get_current_window_bounds()
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	if price_range <= 0:
		is_hovering_spread_zone = false
		return

	# Use EXACT same coordinate system as grid and Y-axis labels
	var chart_bounds = chart_math.get_chart_boundaries()

	# Calculate Y positions using EXACT same formula as grid
	var buy_ratio = (current_buy_price - min_price) / price_range
	var sell_ratio = (current_sell_price - min_price) / price_range
	var buy_y = chart_bounds.top + chart_bounds.height - (buy_ratio * chart_bounds.height)
	var sell_y = chart_bounds.top + chart_bounds.height - (sell_ratio * chart_bounds.height)

	# Determine the visible portion of the spread zone
	var zone_top = max(min(buy_y, sell_y), chart_bounds.top)
	var zone_bottom = min(max(buy_y, sell_y), chart_bounds.bottom)

	# Only check hover if there's a visible portion
	if zone_bottom <= zone_top:
		is_hovering_spread_zone = false
		return

	var zone_rect = Rect2(Vector2(chart_bounds.left, zone_top), Vector2(chart_bounds.width, zone_bottom - zone_top))

	var was_hovering = is_hovering_spread_zone
	is_hovering_spread_zone = zone_rect.has_point(mouse_position)

	if is_hovering_spread_zone:
		spread_tooltip_position = mouse_position

	# Redraw if hover state changed
	if was_hovering != is_hovering_spread_zone:
		parent_chart.queue_redraw()


func _format_price_compact(price: float) -> String:
	"""Format price in compact form"""
	if price >= 1000000000:
		return "%.1fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.1fK" % (price / 1000.0)

	return "%.0f" % price


func _format_price_label(price: float) -> String:
	"""Format price with appropriate scale (K, M, B)"""
	if price >= 1000000000:
		return "%.1fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.1fK" % (price / 1000.0)

	return "%.2f" % price


func _get_station_trading_color(margin_pct: float) -> Color:
	"""Get color based on station trading profit quality"""
	if margin_pct >= 10.0:
		return Color.GREEN  # Excellent - 10%+ profit
	if margin_pct >= 5.0:
		return Color.YELLOW  # Good - 5-10% profit
	if margin_pct >= 2.0:
		return Color.ORANGE  # Marginal - 2-5% profit

	return Color.RED  # Poor - <2% profit


func _get_station_trading_quality_text(margin_pct: float) -> String:
	"""Get text description of station trading opportunity quality"""
	if margin_pct >= 10.0:
		return "EXCELLENT OPPORTUNITY"
	if margin_pct >= 5.0:
		return "GOOD OPPORTUNITY"
	if margin_pct >= 2.0:
		return "MARGINAL OPPORTUNITY"

	return "POOR OPPORTUNITY"


func _get_spread_quality_text(margin_pct: float) -> String:
	"""Get text description of spread quality"""
	if margin_pct >= 5.0:
		return "EXCELLENT"
	if margin_pct >= 2.0:
		return "DECENT"
	if margin_pct >= 1.0:
		return "MARGINAL"

	return "POOR"


func _is_point_in_rect(point: Vector2, rect: Rect2) -> bool:
	"""Check if a point is inside a rectangle"""
	return point.x >= rect.position.x and point.x <= rect.position.x + rect.size.x and point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y


func _is_line_visible(p1: Vector2, p2: Vector2, chart_bounds: Dictionary) -> bool:
	"""Check if a line segment is potentially visible in the chart area"""
	var expanded_rect = Rect2(Vector2(chart_bounds.left, chart_bounds.top), Vector2(chart_bounds.width, chart_bounds.height))

	return _is_point_in_rect(p1, expanded_rect) or _is_point_in_rect(p2, expanded_rect) or _line_intersects_rect(p1, p2, expanded_rect)


func _line_intersects_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	"""Check if a line intersects with a rectangle"""
	# Simple bounding box check first
	var line_min_x = min(p1.x, p2.x)
	var line_max_x = max(p1.x, p2.x)
	var line_min_y = min(p1.y, p2.y)
	var line_max_y = max(p1.y, p2.y)

	var rect_min_x = rect.position.x
	var rect_max_x = rect.position.x + rect.size.x
	var rect_min_y = rect.position.y
	var rect_max_y = rect.position.y + rect.size.y

	# Check if bounding boxes overlap
	return not (line_max_x < rect_min_x or line_min_x > rect_max_x or line_max_y < rect_min_y or line_min_y > rect_max_y)
