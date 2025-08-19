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
	var bounds = chart_math.get_chart_boundaries()

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
		var x = bounds.left + (time_progress * bounds.width)

		if x >= bounds.left and x <= bounds.right:
			parent_chart.draw_line(Vector2(x, bounds.top), Vector2(x, bounds.bottom), grid_color, 1.0, false)

		current_time += grid_interval

	# Horizontal grid lines (price)
	var price_range = window_bounds.price_max - window_bounds.price_min
	var price_grid_count = 8
	var price_step = price_range / price_grid_count

	for i in range(price_grid_count + 1):
		var price = window_bounds.price_min + (i * price_step)
		var price_progress = (price - window_bounds.price_min) / price_range
		var y = bounds.top + bounds.height - (price_progress * bounds.height)

		if y >= bounds.top and y <= bounds.bottom:
			parent_chart.draw_line(Vector2(bounds.left, y), Vector2(bounds.right, y), grid_color, 1.0, false)


func _draw_price_line():
	if chart_data.price_data.size() < 1:
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	# Get visible data
	var visible_points = []
	var visible_candles = []

	var time_window = window_end - window_start
	var buffer_time = time_window * 0.1

	for point in chart_data.price_data:
		if point.timestamp >= (window_start - buffer_time) and point.timestamp <= (window_end + buffer_time):
			visible_points.append(point)

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= (window_start - buffer_time) and candle.timestamp <= (window_end + buffer_time):
			visible_candles.append(candle)

	if visible_points.size() < 1:
		return

	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_height = chart_bounds.height
	var chart_y_offset = chart_bounds.top

	# Draw candlesticks first
	if parent_chart.show_candlesticks and visible_candles.size() > 0:
		_draw_candlesticks(visible_candles, window_start, window_end, min_price, price_range, chart_height, chart_y_offset)

	# Draw price line
	var points: PackedVector2Array = []
	for i in range(visible_points.size()):
		var point_data = visible_points[i]
		var time_progress = (point_data.timestamp - window_start) / (window_end - window_start)
		var chart_width = chart_bounds.right - chart_bounds.left
		var x = chart_bounds.left + (time_progress * chart_width)

		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		points.append(Vector2(x, y))

	# Draw lines between points with clipping
	for i in range(points.size() - 1):
		var current_point_data = visible_points[i]
		var next_point_data = visible_points[i + 1]
		var time_diff = next_point_data.timestamp - current_point_data.timestamp

		if time_diff <= 86400.0 * 2:  # Within 2 days
			var p1 = points[i]
			var p2 = points[i + 1]

			var clip_rect = Rect2(Vector2(chart_bounds.left, chart_bounds.top), Vector2(chart_bounds.width, chart_bounds.height))
			var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

			if clipped_line.has("start") and clipped_line.has("end"):
				var current_is_historical = current_point_data.get("is_historical", false)
				var next_is_historical = next_point_data.get("is_historical", false)

				var line_color = Color(0.6, 0.8, 1.0, 0.6) if (current_is_historical and next_is_historical) else Color.YELLOW
				var line_width = 1.5 if (current_is_historical and next_is_historical) else 2.0
				parent_chart.draw_line(clipped_line.start, clipped_line.end, line_color, line_width, true)

	# Draw data points
	for i in range(points.size()):
		var point_data = visible_points[i]
		var point = points[i]

		if point.y >= chart_bounds.top and point.y <= chart_bounds.bottom and point.x >= chart_bounds.left and point.x <= chart_bounds.right:
			var is_historical = point_data.get("is_historical", false)
			var volume = point_data.get("volume", 0)

			var circle_color = Color(0.9, 0.9, 0.4, 0.8) if is_historical else Color.ORANGE
			var circle_radius = 4.0

			if volume > 0:
				parent_chart.draw_circle(point, circle_radius + 1.0, Color.WHITE, true)
				parent_chart.draw_circle(point, circle_radius, circle_color, true)


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
	if chart_data.volume_data.size() == 0 or chart_data.price_data.size() == 0:
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end

	var visible_data = []
	for i in range(min(chart_data.price_data.size(), chart_data.volume_data.size())):
		var point = chart_data.price_data[i]
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_data.append({"timestamp": point.timestamp, "volume": chart_data.volume_data[i], "is_historical": point.get("is_historical", false)})

	if visible_data.size() == 0:
		return

	var max_volume = chart_data.get_max_volume()
	if max_volume <= 0:
		return

	var chart_bounds = chart_math.get_chart_boundaries()
	var volume_area_height = parent_chart.size.y * 0.25
	var volume_area_bottom = parent_chart.size.y * 0.95
	var volume_area_top = volume_area_bottom - volume_area_height

	var time_span = window_end - window_start
	var bar_width = max(1.0, chart_bounds.width / max(visible_data.size(), 1))

	for i in range(visible_data.size()):
		var data = visible_data[i]
		var time_progress = (data.timestamp - window_start) / time_span
		var x = chart_bounds.left + (time_progress * chart_bounds.width)

		var volume_ratio = float(data.volume) / float(max_volume)
		var bar_height = volume_ratio * volume_area_height
		var bar_y = volume_area_bottom - bar_height

		var bar_color = Color(0.3, 0.6, 1.0, 0.4) if data.is_historical else Color(1.0, 0.8, 0.2, 0.6)

		var bar_rect = Rect2(x - bar_width / 2, bar_y, bar_width, bar_height)
		parent_chart.draw_rect(bar_rect, bar_color, true)


func _draw_axis_labels():
	var font_size = 11
	var bounds = chart_math.get_current_window_bounds()
	var chart_bounds = chart_math.get_chart_boundaries()

	# Price labels (Y-axis)
	var price_range = bounds.price_max - bounds.price_min
	var label_count = 8
	var price_step = price_range / label_count

	for i in range(label_count + 1):
		var price = bounds.price_min + (i * price_step)
		var price_progress = (price - bounds.price_min) / price_range
		var y = chart_bounds.top + chart_bounds.height - (price_progress * chart_bounds.height)

		var price_text = _format_price_label(price)
		var text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		parent_chart.draw_string(chart_font, Vector2(5, y + text_size.y / 2 - 2), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)

	# Time labels (X-axis)
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

		parent_chart.draw_string(chart_font, Vector2(x - text_size.x / 2, chart_bounds.bottom + 15), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


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
