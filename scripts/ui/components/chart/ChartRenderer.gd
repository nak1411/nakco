# scripts/ui/components/chart/ChartRenderer.gd
class_name ChartRenderer
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData
var chart_math: ChartMath
var analysis_tools: AnalysisTools

# Visual styling
var chart_color: Color = Color.GREEN
var background_color: Color = Color(0.1, 0.12, 0.15, 1)
var grid_color: Color = Color(0.3, 0.3, 0.4, 0.3)
var buy_color: Color = Color(0.2, 0.8, 0.2, 1)
var sell_color: Color = Color(0.8, 0.2, 0.2, 1)
var volume_color: Color = Color(0.4, 0.6, 1.0, 0.7)
var axis_label_color: Color = Color(0.7, 0.7, 0.8, 1)

# Candlestick styling
var candle_width: float = 12.0
var wick_width: float = 1.0
var candle_up_color: Color = Color(0.2, 0.8, 0.2, 0.9)
var candle_down_color: Color = Color(0.8, 0.2, 0.2, 0.9)
var candle_neutral_color: Color = Color(0.6, 0.6, 0.6, 0.9)
var wick_color: Color = Color(0.7, 0.7, 0.7, 1.0)

# Spread visualization colors
var profitable_spread_color: Color = Color.GREEN
var marginal_spread_color: Color = Color.YELLOW
var poor_spread_color: Color = Color.RED
var spread_line_color: Color = Color.CYAN

var chart_font: Font


func setup(chart: MarketChart, data: ChartData, math: ChartMath, tools: AnalysisTools):
	parent_chart = chart
	chart_data = data
	chart_math = math
	analysis_tools = tools
	chart_font = ThemeDB.fallback_font


func draw_chart():
	# Draw background
	parent_chart.draw_rect(Rect2(Vector2.ZERO, parent_chart.size), background_color)

	if chart_data.price_data.is_empty():
		_draw_no_data_message()
		return

	# Draw main chart components
	_draw_grid()
	_draw_price_line()
	_draw_volume_bars()
	_draw_axis_labels()

	# Draw analysis overlays
	if parent_chart.show_support_resistance:
		analysis_tools.draw_support_resistance_lines()

	if parent_chart.show_spread_analysis:
		analysis_tools.draw_spread_analysis()

	# Draw interaction elements
	_draw_crosshair()
	_draw_zoom_indicator()
	_draw_tooltips()


func _draw_no_data_message():
	var font_size = 16
	var text = "No market data available"
	var text_size = chart_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center_pos = parent_chart.size / 2
	var text_pos = center_pos - text_size / 2

	parent_chart.draw_string(chart_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)


func _draw_grid():
	# Use EXACT original chart dimensions
	var chart_height = parent_chart.size.y * 0.6
	var chart_y_offset = parent_chart.size.y * 0.05
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_top = chart_y_offset
	var chart_bottom = chart_y_offset + chart_height

	# Vertical grid lines (time)
	var time_window = chart_math.get_current_time_window()
	var window_days = time_window / 86400.0

	var grid_interval: float
	if window_days <= 1:
		grid_interval = 3600.0  # 1 hour
	elif window_days <= 7:
		grid_interval = 86400.0  # 1 day
	elif window_days <= 30:
		grid_interval = 86400.0 * 7  # 1 week
	else:
		grid_interval = 86400.0 * 30  # 1 month

	var window_bounds = chart_math.get_current_window_bounds()
	var start_time = window_bounds.time_start
	var end_time = window_bounds.time_end

	var grid_start = floor(start_time / grid_interval) * grid_interval
	var current_time = grid_start

	while current_time <= end_time:
		var time_progress = (current_time - start_time) / (end_time - start_time)
		var x = chart_bounds.left + (time_progress * chart_bounds.width)

		if x >= chart_bounds.left and x <= chart_bounds.right:
			parent_chart.draw_line(Vector2(x, chart_top), Vector2(x, chart_bottom), grid_color, 1.0, false)

		current_time += grid_interval

	# Horizontal grid lines (price)
	var price_range = window_bounds.price_max - window_bounds.price_min
	var price_grid_count = 8
	var price_step = price_range / price_grid_count

	for i in range(price_grid_count + 1):
		var price = window_bounds.price_min + (i * price_step)
		var price_progress = (price - window_bounds.price_min) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		if y >= chart_top and y <= chart_bottom:
			parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), grid_color, 1.0, false)


func _draw_price_line():
	print("=== DRAWING PRICE LINE (EXACT ORIGINAL) ===")
	print("Price data size: %d, Candlestick data size: %d" % [chart_data.price_data.size(), chart_data.candlestick_data.size()])

	if chart_data.price_data.size() < 1:
		print("No price data to draw")
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	print("Drawing bounds: time %.0f-%.0f, price %.2f-%.2f" % [window_start, window_end, min_price, max_price])

	# Get visible data (EXACT original logic)
	var visible_points = []
	var visible_candles = []

	# Extend the window slightly to include adjacent points for line continuation (EXACT original)
	var time_window = window_end - window_start
	var buffer_time = time_window * 0.1  # 10% buffer on each side

	for point in chart_data.price_data:
		if point.timestamp >= (window_start - buffer_time) and point.timestamp <= (window_end + buffer_time):
			visible_points.append(point)

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= (window_start - buffer_time) and candle.timestamp <= (window_end + buffer_time):
			visible_candles.append(candle)

	print("Visible points: %d, Visible candles: %d" % [visible_points.size(), visible_candles.size()])

	if visible_points.size() < 1:
		print("No visible points in current window")
		return

	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Use EXACT original chart dimensions
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_height = parent_chart.size.y * 0.6  # EXACT original proportion
	var chart_y_offset = parent_chart.size.y * 0.05  # EXACT original offset
	var chart_top = chart_y_offset
	var chart_bottom = chart_y_offset + chart_height

	print("Chart dimensions: height %.1f, y_offset %.1f" % [chart_height, chart_y_offset])
	print("Chart bounds: top %.1f, bottom %.1f" % [chart_top, chart_bottom])

	# Draw candlesticks first (if enabled)
	if parent_chart.show_candlesticks and visible_candles.size() > 0:
		print("Drawing %d candlesticks" % visible_candles.size())
		_draw_candlesticks(visible_candles, window_start, window_end, min_price, price_range, chart_height, chart_y_offset)

	# Draw moving average line (EXACT original)
	var points: PackedVector2Array = []
	for i in range(visible_points.size()):
		var point_data = visible_points[i]
		var time_progress = (point_data.timestamp - window_start) / (window_end - window_start)
		var chart_width = chart_bounds.right - chart_bounds.left
		var x = chart_bounds.left + (time_progress * chart_width)

		if i < 3:
			print("Data point %d: timestamp=%.0f, progress=%.6f, chart_left=%.1f, width=%.1f, x=%.1f" % [i, point_data.timestamp, time_progress, chart_bounds.left, chart_width, x])

		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		# DON'T clamp here - keep original positions for proper line math
		points.append(Vector2(x, y))

		if i < 3:  # Debug first few points
			print("Point %d: time %.0f, price %.2f -> x %.1f, y %.1f" % [i, point_data.timestamp, point_data.price, x, y])

	print("Generated %d drawing points" % points.size())

	# Draw lines between points with proper clipping (EXACT original)
	for i in range(points.size() - 1):
		var current_point_data = visible_points[i]
		var next_point_data = visible_points[i + 1]
		var time_diff = next_point_data.timestamp - current_point_data.timestamp

		if time_diff <= 86400.0 * 2:  # Within 2 days
			var p1 = points[i]
			var p2 = points[i + 1]

			# Clip line to chart bounds
			var clip_rect = Rect2(Vector2(chart_bounds.left, chart_top), Vector2(chart_bounds.width, chart_height))
			var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

			if clipped_line.has("start") and clipped_line.has("end"):
				var current_is_historical = current_point_data.get("is_historical", false)
				var next_is_historical = next_point_data.get("is_historical", false)

				var line_color = Color(0.6, 0.8, 1.0, 0.6) if (current_is_historical and next_is_historical) else Color.YELLOW
				var line_width = 1.5 if (current_is_historical and next_is_historical) else 2.0
				parent_chart.draw_line(clipped_line.start, clipped_line.end, line_color, line_width, true)

				if i < 3:  # Debug first few lines
					print("Drew clipped line %d: from (%.1f,%.1f) to (%.1f,%.1f)" % [i, clipped_line.start.x, clipped_line.start.y, clipped_line.end.x, clipped_line.end.y])

	# Draw data points (EXACT original)
	for i in range(points.size()):
		var point_data = visible_points[i]
		var point = points[i]

		# Only draw points within chart bounds
		if point.y >= chart_top and point.y <= chart_bottom and point.x >= chart_bounds.left and point.x <= chart_bounds.right:
			var is_historical = point_data.get("is_historical", false)
			var volume = point_data.get("volume", 0)

			var circle_color = Color(0.9, 0.9, 0.4, 0.8) if is_historical else Color.ORANGE
			var circle_radius = 4.0

			if volume > 0:
				parent_chart.draw_circle(point, circle_radius + 1.0, Color.WHITE, true)
				parent_chart.draw_circle(point, circle_radius, circle_color, true)

			if i < 3:  # Debug first few circles
				print("Drew circle %d at (%.1f,%.1f) color %s" % [i, point.x, point.y, circle_color])


func _draw_candlesticks(visible_candles: Array, window_start: float, window_end: float, min_price: float, price_range: float, chart_height: float, chart_y_offset: float):
	var scale_factors = chart_math.get_zoom_scale_factor()
	var scaled_candle_width = candle_width * scale_factors.volume_scale
	var scaled_wick_width = max(2.0, wick_width * scale_factors.volume_scale)

	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_top = chart_bounds.top
	var chart_bottom = chart_bounds.bottom

	for i in range(visible_candles.size()):
		var candle = visible_candles[i]

		var time_progress = (candle.timestamp - window_start) / (window_end - window_start)
		var chart_width = chart_bounds.right - chart_bounds.left
		var x = chart_bounds.left + (time_progress * chart_width)

		var open_price = candle.get("open", 0.0)
		var high_price = candle.get("high", 0.0)
		var low_price = candle.get("low", 0.0)
		var close_price = candle.get("close", 0.0)

		if high_price <= 0 or low_price <= 0:
			continue

		var open_y = chart_y_offset + chart_height - ((open_price - min_price) / price_range * chart_height)
		var high_y = chart_y_offset + chart_height - ((high_price - min_price) / price_range * chart_height)
		var low_y = chart_y_offset + chart_height - ((low_price - min_price) / price_range * chart_height)
		var close_y = chart_y_offset + chart_height - ((close_price - min_price) / price_range * chart_height)

		# Determine colors
		var candle_color: Color
		var wick_trend_color: Color
		var previous_close = 0.0

		if i > 0:
			previous_close = visible_candles[i - 1].get("close", 0.0)

		var day_change = close_price - previous_close if previous_close > 0 else 0.0

		# Body color (open vs close)
		var price_diff = close_price - open_price
		if price_diff > 0.01:
			candle_color = Color(0.1, 0.8, 0.1, 0.9)
		elif price_diff < -0.01:
			candle_color = Color(0.8, 0.1, 0.1, 0.9)
		else:
			candle_color = Color(0.6, 0.6, 0.6, 0.9)

		# Wick color (day-to-day movement)
		if day_change > 0.01:
			wick_trend_color = Color(0.0, 0.9, 0.0, 1.0)
		elif day_change < -0.01:
			wick_trend_color = Color(0.9, 0.0, 0.0, 1.0)
		else:
			wick_trend_color = Color(0.7, 0.7, 0.7, 1.0)

		# Check visibility
		var min_candle_y = min(high_y, min(open_y, min(close_y, low_y)))
		var max_candle_y = max(high_y, max(open_y, max(close_y, low_y)))

		if not (max_candle_y < chart_top or min_candle_y > chart_bottom):
			# Draw candlestick body
			var body_top = min(open_y, close_y)
			var body_bottom = max(open_y, close_y)
			var body_height = max(body_bottom - body_top, 3.0)

			var clipped_body_top = max(body_top, chart_top)
			var clipped_body_bottom = min(body_bottom, chart_bottom)
			var clipped_body_height = max(clipped_body_bottom - clipped_body_top, 0.0)

			if clipped_body_height > 0:
				var body_rect = Rect2(x - scaled_candle_width / 2, clipped_body_top, scaled_candle_width, clipped_body_height)
				parent_chart.draw_rect(body_rect, candle_color, true)

				var border_color = wick_trend_color.darkened(0.3)
				parent_chart.draw_rect(body_rect, border_color, false, 1.0)

			# Draw wicks
			if x >= chart_bounds.left and x <= chart_bounds.right:
				# Upper wick
				if high_y < body_top:
					var wick_start_y = max(high_y, chart_top)
					var wick_end_y = min(body_top, chart_bottom)

					if wick_start_y < wick_end_y:
						parent_chart.draw_line(Vector2(x, wick_start_y), Vector2(x, wick_end_y), wick_trend_color, scaled_wick_width, false)

				# Lower wick
				if low_y > body_bottom:
					var wick_start_y = max(body_bottom, chart_top)
					var wick_end_y = min(low_y, chart_bottom)

					if wick_start_y < wick_end_y:
						parent_chart.draw_line(Vector2(x, wick_start_y), Vector2(x, wick_end_y), wick_trend_color, scaled_wick_width, false)


func _draw_volume_bars():
	print("=== DRAWING VOLUME BARS WITH EXACT ORIGINAL LAYOUT ===")

	if chart_data.volume_data.size() == 0 or chart_data.price_data.size() == 0:
		print("No volume or price data to draw")
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end

	# Get zoom-based scaling (EXACT original)
	var scale_factors = chart_math.get_zoom_scale_factor()
	var volume_scale = scale_factors.volume_scale

	# Get EXACT original chart boundaries
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_bottom = chart_bounds.bottom

	# EXACT original volume area calculation
	var x_track_height = 25
	var volume_area_height = parent_chart.size.y - chart_bottom
	var volume_base_y = chart_bottom

	# Ensure minimum volume area (EXACT original)
	if volume_area_height < 20:
		volume_area_height = 20
		volume_base_y = parent_chart.size.y - x_track_height - volume_area_height

	print("Volume area: starts at Y=%.1f, height=%.1f" % [volume_base_y, volume_area_height])

	# Collect visible volume data (EXACT original logic)
	var visible_volume_data = []
	var visible_timestamps = []
	var visible_historical_flags = []
	var visible_indices = []
	var historical_max = 0
	var all_max = 0

	for i in range(min(chart_data.volume_data.size(), chart_data.price_data.size())):
		var timestamp = chart_data.price_data[i].timestamp
		if timestamp >= window_start and timestamp <= window_end:
			var volume = chart_data.volume_data[i]
			var is_historical = chart_data.price_data[i].get("is_historical", false)

			visible_volume_data.append(volume)
			visible_timestamps.append(timestamp)
			visible_historical_flags.append(is_historical)
			visible_indices.append(i)

			# Track maximums for scaling (EXACT original)
			if volume > all_max:
				all_max = volume
			if is_historical and volume > historical_max:
				historical_max = volume

	if visible_volume_data.size() == 0:
		print("No visible volume data in time window")
		return

	# Use historical max for scaling, fall back to all max if no historical data (EXACT original)
	var scaling_max = historical_max if historical_max > 0 else all_max
	var volume_percentile_95 = _calculate_volume_percentile(visible_volume_data, 95.0)
	var volume_cap = volume_percentile_95 * 1.5  # EXACT original cap

	# EXACT original volume area height calculation
	var volume_height_scale = volume_area_height * 0.8  # Use 80% of available volume area
	var base_bar_width = 30.0 * volume_scale  # Apply zoom scaling to bar width

	print("Volume scaling: max=%d, height_scale=%.1f, bar_width=%.1f" % [scaling_max, volume_height_scale, base_bar_width])

	# Draw all visible volume bars (EXACT original logic)
	for i in range(visible_volume_data.size()):
		var volume = visible_volume_data[i]
		var timestamp = visible_timestamps[i]
		var is_historical = visible_historical_flags[i]
		var original_index = visible_indices[i]

		if not is_historical:
			continue

		# EXACT original X calculation
		var time_progress = (timestamp - window_start) / (window_end - window_start)
		var chart_width = chart_bounds.right - chart_bounds.left
		var x = chart_bounds.left + (time_progress * chart_width)

		# Skip if outside visible area
		if x < -base_bar_width or x > parent_chart.size.x + base_bar_width:
			continue

		# Cap extreme volumes for display consistency (EXACT original)
		var display_volume = volume
		if not is_historical and volume > volume_cap:
			display_volume = volume_cap

		# Scale volume to bar height using volume area (EXACT original)
		var normalized_volume = float(display_volume) / scaling_max if scaling_max > 0 else 0.0
		var bar_height = normalized_volume * volume_height_scale

		# Ensure minimum visibility (EXACT original)
		if bar_height < 2.0:
			bar_height = 2.0

		# Cap maximum height to available volume area (EXACT original)
		if bar_height > volume_area_height:
			bar_height = volume_area_height

		# Position bar in the volume area below chart (EXACT original)
		var y = volume_base_y + (volume_area_height - bar_height)
		y = max(y, volume_base_y)  # Ensure bar doesn't go above volume area
		y = min(y + bar_height, volume_base_y + volume_area_height) - bar_height
		var bar_rect = Rect2(x - base_bar_width / 2, y, base_bar_width, bar_height)

		# EXACT original color coding
		var bar_color: Color
		if is_historical:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.2, 0.4, 0.8, 0.8) * volume_intensity
		else:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.8, 0.9, 0.2, 0.9) * volume_intensity

		# Draw the volume bar
		parent_chart.draw_rect(bar_rect, bar_color)

		# Add subtle border (EXACT original)
		if bar_height > 2:
			var border_height = max(1.0, 1.0 * volume_scale)
			parent_chart.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x, border_height)), Color.WHITE * 0.2)

	print("Drew volume bars in area Y: %.1f-%.1f" % [volume_base_y, parent_chart.size.y])


func _calculate_volume_percentile(volume_data: Array, percentile: float) -> float:
	"""Calculate the Nth percentile of volume data for outlier detection (EXACT original)"""
	if volume_data.is_empty():
		return 0.0

	var sorted_volumes = volume_data.duplicate()
	sorted_volumes.sort()

	var index = int((percentile / 100.0) * (sorted_volumes.size() - 1))
	index = clamp(index, 0, sorted_volumes.size() - 1)

	return sorted_volumes[index]


func _draw_axis_labels():
	var font_size = 11
	var bounds = chart_math.get_current_window_bounds()
	var chart_bounds = chart_math.get_chart_boundaries()

	# Use EXACT original chart dimensions
	var chart_height = parent_chart.size.y * 0.6
	var chart_y_offset = parent_chart.size.y * 0.05
	var chart_top = chart_y_offset
	var chart_bottom = chart_y_offset + chart_height

	# Price labels (Y-axis) - EXACT original
	var price_range = bounds.price_max - bounds.price_min
	var label_count = 8
	var price_step = price_range / label_count

	for i in range(label_count + 1):
		var price = bounds.price_min + (i * price_step)
		var price_progress = (price - bounds.price_min) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		var price_text = _format_price_label(price)
		var text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		parent_chart.draw_string(chart_font, Vector2(5, y + text_size.y / 2 - 2), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)

	# Time labels (X-axis) - EXACT original position
	var time_window = chart_math.get_current_time_window()
	var window_days = time_window / 86400.0

	var time_label_count = 6
	var time_step = (bounds.time_end - bounds.time_start) / time_label_count

	for i in range(time_label_count + 1):
		var timestamp = bounds.time_start + (i * time_step)
		var time_progress = (timestamp - bounds.time_start) / (bounds.time_end - bounds.time_start)
		var x = chart_bounds.left + (time_progress * chart_bounds.width)

		var time_text = _format_time_label(timestamp, window_days)
		var text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		# Position at EXACT original Y position (below chart area)
		parent_chart.draw_string(chart_font, Vector2(x - text_size.x / 2, chart_bottom + 15), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func _draw_crosshair():
	if not parent_chart.chart_interaction.show_crosshair:
		return

	var chart_bounds = chart_math.get_chart_boundaries()
	var mouse_pos = parent_chart.chart_interaction.mouse_position

	if mouse_pos.x < chart_bounds.left or mouse_pos.x > chart_bounds.right or mouse_pos.y < chart_bounds.top or mouse_pos.y > chart_bounds.bottom:
		return

	# Draw crosshair lines
	parent_chart.draw_line(Vector2(chart_bounds.left, mouse_pos.y), Vector2(chart_bounds.right, mouse_pos.y), Color.DIM_GRAY, 1.0, false)
	parent_chart.draw_line(Vector2(mouse_pos.x, chart_bounds.top), Vector2(mouse_pos.x, chart_bounds.bottom), Color.DIM_GRAY, 1.0, false)

	# Draw crosshair labels
	if chart_data.price_data.size() > 0:
		var bounds = chart_math.get_current_window_bounds()
		var price_range = bounds.price_max - bounds.price_min
		var time_span = bounds.time_end - bounds.time_start

		if price_range > 0 and time_span > 0:
			var time_at_mouse = chart_math.get_time_at_pixel(mouse_pos.x)
			var price_at_mouse = chart_math.get_price_at_pixel(mouse_pos.y)

			var time_window = chart_math.get_current_time_window()
			var window_days = time_window / 86400.0

			var price_text = _format_price_label(price_at_mouse)
			var time_text = _format_time_label(time_at_mouse, window_days)

			var font_size = 11
			var padding = Vector2(4, 2)

			# Price label
			var price_text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var price_bg_rect = Rect2(Vector2(2, mouse_pos.y - price_text_size.y / 2 - padding.y), Vector2(price_text_size.x + padding.x * 2, price_text_size.y + padding.y * 2))

			parent_chart.draw_rect(price_bg_rect, Color(0.1, 0.1, 0.15, 0.9))
			parent_chart.draw_rect(price_bg_rect, axis_label_color, false, 1.0)
			parent_chart.draw_string(
				chart_font,
				Vector2(price_bg_rect.position.x + padding.x, price_bg_rect.position.y + padding.y + price_text_size.y - 4),
				price_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				Color.WHITE
			)

			# Time label
			var time_text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var chart_bottom = parent_chart.size.y * 0.7
			var time_x = mouse_pos.x - time_text_size.x / 2
			time_x = max(0, min(time_x, parent_chart.size.x - time_text_size.x))

			var time_bg_rect = Rect2(Vector2(time_x - padding.x, chart_bottom + 2), Vector2(time_text_size.x + padding.x * 2, time_text_size.y + padding.y * 2))

			parent_chart.draw_rect(time_bg_rect, Color(0.1, 0.1, 0.15, 0.9))
			parent_chart.draw_rect(time_bg_rect, axis_label_color, false, 1.0)
			parent_chart.draw_string(
				chart_font, Vector2(time_bg_rect.position.x + padding.x, time_bg_rect.position.y + padding.y + time_text_size.y - 4), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE
			)


func _draw_zoom_indicator():
	var font_size = 10
	var time_window = chart_math.get_current_time_window()
	var window_days = time_window / 86400.0

	var zoom_text = ""
	if window_days < 1.0:
		zoom_text = "%.1f hours" % (window_days * 24.0)
	elif window_days < 7.0:
		zoom_text = "%.1f days" % window_days
	elif window_days < 30.0:
		zoom_text = "%.1f weeks" % (window_days / 7.0)
	elif window_days < 365.0:
		zoom_text = "%.1f months" % (window_days / 30.0)
	else:
		zoom_text = "%.1f years" % (window_days / 365.0)

	var text_size = chart_font.get_string_size(zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding = Vector2(8, 4)

	var bg_rect = Rect2(parent_chart.size.x - text_size.x - padding.x * 2 - 5, 5, text_size.x + padding.x * 2, text_size.y + padding.y * 2)
	var bg_color = Color(0.1, 0.1, 0.15, 0.8)
	var text_color = Color.YELLOW if parent_chart.zoom_level != 1.0 else Color.WHITE

	parent_chart.draw_rect(bg_rect, bg_color)
	parent_chart.draw_rect(bg_rect, Color(0.3, 0.3, 0.4, 0.8), false, 1.0)
	parent_chart.draw_string(
		chart_font, Vector2(bg_rect.position.x + (padding.x - 2), bg_rect.position.y + padding.y + text_size.y - 4), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color
	)


func _draw_tooltips():
	# Tooltip drawing logic would go here
	pass


func _format_price_label(price: float) -> String:
	if price >= 1000000000:
		return "%.1fB" % (price / 1000000000.0)
	elif price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	elif price >= 1000:
		return "%.1fK" % (price / 1000.0)
	else:
		return "%.2f" % price


func _format_time_label(timestamp: float, window_days: float) -> String:
	var datetime = Time.get_datetime_dict_from_unix_time(timestamp)

	if window_days <= 1:
		return "%02d:%02d" % [datetime.hour, datetime.minute]
	elif window_days <= 7:
		return "%d/%d" % [datetime.month, datetime.day]
	elif window_days <= 30:
		return "%d/%d" % [datetime.month, datetime.day]
	else:
		return "%d/%d" % [datetime.month, datetime.year % 100]


func set_chart_style(style: String):
	match style:
		"bullish":
			chart_color = Color.GREEN
			background_color = Color(0.05, 0.15, 0.05, 1)
		"bearish":
			chart_color = Color.RED
			background_color = Color(0.15, 0.05, 0.05, 1)
		"neutral":
			chart_color = Color.CYAN
			background_color = Color(0.1, 0.12, 0.15, 1)

	parent_chart.queue_redraw()
