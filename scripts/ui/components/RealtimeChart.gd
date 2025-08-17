# scripts/ui/components/RealtimeChart.gd
class_name RealtimeChart
extends Control

signal price_level_clicked(price: float)
signal historical_data_requested

var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var time_labels: Array[String] = []
var max_data_points: int = 365
var timeframe_hours: float = 8760.0  # 1 year timeframe (365 * 24)
var data_retention_seconds: float = 31536000.0  # 1 year in seconds (365 * 24 * 3600)
var base_time_window: float = 31536000.0  # 1 year in seconds (base window)
var max_data_retention: float = 31536000.0  # 1 year in seconds
var day_start_timestamp: float = 0.0
var current_day_data: Array = []
var has_loaded_historical: bool = false
var is_loading_historical: bool = false

var chart_color: Color = Color.GREEN
var background_color: Color = Color(0.1, 0.12, 0.15, 1)
var grid_color: Color = Color(0.3, 0.3, 0.4, 0.3)
var buy_color: Color = Color(0.2, 0.8, 0.2, 1)
var sell_color: Color = Color(0.8, 0.2, 0.2, 1)
var volume_color: Color = Color(0.4, 0.6, 1.0, 0.7)
var chart_font: Font
var axis_label_color: Color = Color(0.7, 0.7, 0.8, 1)

# Candlestick
var candlestick_data: Array[Dictionary] = []  # Store OHLC data for candlesticks
var show_candlesticks: bool = true
var candle_width: float = 12.0  # Base width for candlestick bodies
var wick_width: float = 1.0  # Width of candlestick wicks
var candle_up_color: Color = Color(0.2, 0.8, 0.2, 0.9)  # Green for up candles
var candle_down_color: Color = Color(0.8, 0.2, 0.2, 0.9)  # Red for down candles
var candle_neutral_color: Color = Color(0.6, 0.6, 0.6, 0.9)  # Gray for neutral candles
var wick_color: Color = Color(0.7, 0.7, 0.7, 1.0)  # Gray for wicks

# Price level indicators
var support_levels: Array[float] = []
var resistance_levels: Array[float] = []
var moving_average_period: int = 10  # Number of data points for moving average
var price_history: Array[float] = []  # Store raw prices for moving average calculation

# Mouse interaction
var mouse_position: Vector2 = Vector2.ZERO
var show_crosshair: bool = false
var zoom_level: float = 1.0
var min_zoom: float = 1.0  # 1x = 1 year (full view)
var max_zoom: float = 365.0  # 365x = 1 day (most zoomed in)
var zoom_sensitivity: float = 1.2  # Multiplicative zoom factor (20% change per step)

var hovered_point_index: int = -1
var hovered_volume_index: int = -1
var tooltip_content: String = ""
var tooltip_position: Vector2 = Vector2.ZERO
var point_hover_radius: float = 8.0  # Radius for hover detection
var point_visual_radius: float = 4.0  # Visual radius of points


func _ready():
	custom_minimum_size = Vector2(400, 200)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# DISABLE built-in tooltip system
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = ""  # Clear any default tooltip

	chart_font = ThemeDB.fallback_font

	# Initialize day start time
	set_day_start_time()


func _on_mouse_entered():
	show_crosshair = true


func _on_mouse_exited():
	show_crosshair = false
	hovered_point_index = -1
	hovered_volume_index = -1  # Clear hovered volume bar when mouse leaves
	queue_redraw()


func _gui_input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position

		# Check for point hovering first (priority over crosshair)
		check_point_hover(mouse_position)

		# Always accept the event to prevent default tooltip behavior
		get_viewport().set_input_as_handled()

		if show_crosshair:
			queue_redraw()

	# Prevent any other input from triggering tooltips
	if event is InputEventMouseButton:
		# Handle zoom with mouse wheel
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out(event.position)
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()


func check_point_hover(mouse_pos: Vector2):
	"""Check if mouse is hovering over any data point, volume bar, or candlestick"""
	var old_hovered_index = hovered_point_index
	var old_hovered_volume = hovered_volume_index
	hovered_point_index = -1
	hovered_volume_index = -1
	tooltip_text = ""

	if price_data.size() < 1:
		if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
			queue_redraw()
		return

	# Get zoom scaling for consistent hover detection
	var scale_factors = get_zoom_scale_factor()
	var scaled_hover_radius = max(point_hover_radius * scale_factors.point_scale, 6.0)  # Scale hover radius with zoom, minimum 6px
	var scaled_candle_width = candle_width * scale_factors.volume_scale

	# Use current zoom window
	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	# Get visible points and candlesticks
	var visible_points = []
	var visible_candles = []

	for point in price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_points.append(point)

	for candle in candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			visible_candles.append(candle)

	if visible_points.size() == 0 and visible_candles.size() == 0:
		if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
			queue_redraw()
		return

	# Sort and get actual data time range
	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	var data_start_time = window_start
	var data_end_time = window_end
	var data_time_span = time_window

	if visible_points.size() > 0:
		data_start_time = visible_points[0].timestamp
		data_end_time = visible_points[-1].timestamp
		data_time_span = data_end_time - data_start_time

		# Use the exact same logic as draw_price_line
		if data_time_span < 60.0:
			data_start_time = window_start
			data_end_time = window_end
			data_time_span = time_window

	# Get visible price range
	var price_info = get_visible_price_range()
	var min_price = price_info.min_price
	var max_price = price_info.max_price
	var price_range = price_info.range

	if price_range == 0:
		price_range = max_price * 0.1
		min_price = max_price - price_range / 2
		max_price = max_price + price_range / 2

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# # Check for candlestick hover first (highest priority)
	# if visible_candles.size() > 0:
	# 	for i in range(visible_candles.size()):
	# 		var candle = visible_candles[i]
	# 		var timestamp = candle.timestamp

	# 		var time_progress = (timestamp - data_start_time) / data_time_span
	# 		var x = time_progress * size.x

	# 		var high_price = candle.get("high", 0.0)
	# 		var low_price = candle.get("low", 0.0)
	# 		var high_y = chart_y_offset + chart_height - ((high_price - min_price) / price_range * chart_height)
	# 		var low_y = chart_y_offset + chart_height - ((low_price - min_price) / price_range * chart_height)

	# 		# Scale candlestick hover area with zoom
	# 		var hover_width = max(scaled_candle_width * 1.5, 15.0)  # At least 15px, scales with zoom
	# 		var candle_rect = Rect2(x - hover_width / 2, high_y, hover_width, low_y - high_y + 4)  # Add 4px vertical padding

	# 		if candle_rect.has_point(mouse_pos):
	# 			hovered_candlestick_index = i
	# 			tooltip_position = mouse_pos

	# 			var hours_ago = (current_time - timestamp) / 3600.0
	# 			var time_text = format_time_ago(hours_ago)

	# 			var open_price = candle.get("open", 0.0)
	# 			var close_price = candle.get("close", 0.0)
	# 			var volume = candle.get("volume", 0)

	# 			# Calculate daily change
	# 			var daily_change = close_price - open_price
	# 			var daily_change_percent = (daily_change / open_price) * 100.0 if open_price > 0 else 0.0
	# 			var change_sign = "+" if daily_change >= 0 else ""

	# 			# Determine trend
	# 			var trend_text = "Bullish" if daily_change > 0 else ("Bearish" if daily_change < 0 else "Neutral")
	# 			var trend_color = "🟢" if daily_change > 0 else ("🔴" if daily_change < 0 else "⚪")

	# 			tooltip_text = (
	# 				"Daily Candlestick %s\n" % trend_color
	# 				+ "Open: %s ISK\n" % format_price_label(open_price)
	# 				+ "High: %s ISK\n" % format_price_label(high_price)
	# 				+ "Low: %s ISK\n" % format_price_label(low_price)
	# 				+ "Close: %s ISK\n" % format_price_label(close_price)
	# 				+ "Range: %s ISK (%.1f%%)\n" % [format_price_label(high_price - low_price), ((high_price - low_price) / low_price) * 100.0 if low_price > 0 else 0.0]
	# 				+ "Change: %s%s ISK (%.1f%%)\n" % [change_sign, format_price_label(abs(daily_change)), abs(daily_change_percent)]
	# 				+ "Volume: %s\n" % format_number(volume)
	# 				+ "Trend: %s\n" % trend_text
	# 				+ "Time: %s" % time_text
	# 			)
	# 			break

	# Volume bar hover check (second priority) - only if no candlestick hovered
	if hovered_volume_index == -1:
		var base_bar_width = 30.0 * scale_factors.volume_scale  # Use scaled bar width for hover detection
		var volume_height_scale = size.y * 0.3

		var historical_max = 0
		var all_max = 0
		for i in range(min(volume_data.size(), price_data.size())):
			var timestamp = price_data[i].timestamp
			if timestamp >= window_start and timestamp <= window_end:
				var volume = volume_data[i]
				var is_historical = price_data[i].get("is_historical", false)

				if volume > all_max:
					all_max = volume
				if is_historical and volume > historical_max:
					historical_max = volume

		var scaling_max = historical_max if historical_max > 0 else all_max
		var volume_cap = scaling_max * 3

		for i in range(min(volume_data.size(), price_data.size())):
			var point = price_data[i]
			var timestamp = point.timestamp

			if timestamp < window_start or timestamp > window_end:
				continue

			var time_progress = (timestamp - data_start_time) / data_time_span
			var x = time_progress * size.x
			var volume = volume_data[i]
			var is_historical = point.get("is_historical", false)

			var display_volume = volume
			if not is_historical and volume > volume_cap:
				display_volume = volume_cap

			var normalized_volume = float(display_volume) / scaling_max
			var bar_height = normalized_volume * volume_height_scale

			if bar_height < 1.0:
				bar_height = 1.0

			var max_bar_height = size.y * 0.15
			if bar_height > max_bar_height:
				bar_height = max_bar_height

			var bar_y = size.y - bar_height
			# Use scaled bar width for hover detection
			var bar_rect = Rect2(x - base_bar_width / 2, bar_y, base_bar_width, bar_height)

			if bar_rect.has_point(mouse_pos):
				hovered_volume_index = i
				tooltip_position = mouse_pos

				var hours_ago = (current_time - timestamp) / 3600.0
				var time_text = format_time_ago(hours_ago)
				var data_type = "Historical" if is_historical else "Real-time"
				var price = point.get("price", 0.0)

				# Additional volume context
				var volume_intensity = "Low"
				if normalized_volume > 0.8:
					volume_intensity = "Very High"
				elif normalized_volume > 0.6:
					volume_intensity = "High"
				elif normalized_volume > 0.4:
					volume_intensity = "Medium"
				elif normalized_volume > 0.2:
					volume_intensity = "Low"
				else:
					volume_intensity = "Very Low"

				tooltip_text = (
					"%s Volume Data\n" % data_type
					+ "Volume: %s\n" % format_number(volume)
					+ "Intensity: %s\n" % volume_intensity
					+ "Price: %s ISK\n" % format_price_label(price)
					+ "Time: %s" % time_text
				)
				break

	# Moving average point hover (lowest priority) - only if nothing else hovered
	# Use SCALED hover radius here for consistent detection
	if hovered_volume_index == -1:
		var closest_distance = scaled_hover_radius + 1  # Use scaled radius
		var closest_index = -1

		for i in range(visible_points.size()):
			var point = visible_points[i]
			var timestamp = point.timestamp

			var time_progress = (timestamp - data_start_time) / data_time_span
			var x = time_progress * size.x

			var normalized_price = (point.price - min_price) / price_range
			var y = chart_y_offset + chart_height * (1.0 - normalized_price)

			var point_pos = Vector2(x, y)
			var distance = mouse_pos.distance_to(point_pos)

			# Use scaled hover radius for detection
			if distance <= scaled_hover_radius and distance < closest_distance:
				closest_distance = distance
				closest_index = i

		if closest_index != -1:
			hovered_point_index = closest_index
			tooltip_position = mouse_pos

			var point = visible_points[closest_index]
			var hours_ago = (current_time - point.timestamp) / 3600.0
			var time_text = format_time_ago(hours_ago)
			var volume = volume_data[closest_index] if closest_index < volume_data.size() else 0
			var raw_price = point.get("raw_price", point.price)

			# Find corresponding candlestick data for high/low values
			var high_low_text = ""
			for candle in candlestick_data:
				# Check if this candlestick is close in time to the current data point
				if abs(candle.timestamp - point.timestamp) < 86400:  # Within 24 hours
					var high_price = candle.get("high", 0.0)
					var low_price = candle.get("low", 0.0)
					if high_price > 0 and low_price > 0:
						high_low_text = "High: %s ISK\nLow: %s ISK\n" % [format_price_label(high_price), format_price_label(low_price)]
					break

			tooltip_text = (
				"MA Price: %s ISK\n" % format_price_label(point.price)
				+ "Raw Price: %s ISK\n" % format_price_label(raw_price)
				+ high_low_text  # Add high/low info here
				+ "Volume: %s\n" % format_number(volume)
				+ "Time: %s" % time_text
			)

	# Redraw if hover state changed
	if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
		queue_redraw()


func _draw():
	draw_background()
	draw_y_axis_labels()
	draw_x_axis_labels()
	draw_grid()
	draw_price_line()
	draw_volume_bars()
	draw_price_levels()
	draw_zoom_indicator()  # Add this line

	# Only draw one type of tooltip at a time
	if hovered_point_index != -1:
		draw_tooltip()  # Priority: data point tooltip
	elif show_crosshair:
		draw_crosshair()


func draw_background():
	draw_rect(Rect2(Vector2.ZERO, size), background_color)


func draw_tooltip():
	"""Draw enhanced tooltip with color coding and better formatting"""
	if (hovered_point_index == -1 and hovered_volume_index == -1) or tooltip_text.is_empty():
		return

	var font = ThemeDB.fallback_font
	var font_size = 11
	var line_height = 14
	var padding = Vector2(10, 12)

	# Split tooltip text into lines
	var lines = tooltip_text.split("\n")
	var max_width = 0.0

	# Calculate tooltip dimensions
	for line in lines:
		var text_size = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if text_size.x > max_width:
			max_width = text_size.x

	var tooltip_size = Vector2(max_width + padding.x * 2, lines.size() * line_height + padding.y * 2)

	# Position tooltip near cursor, but keep it on screen
	var tooltip_pos = tooltip_position + Vector2(15, -tooltip_size.y / 2)

	# Keep tooltip within screen bounds
	if tooltip_pos.x + tooltip_size.x > size.x:
		tooltip_pos.x = tooltip_position.x - tooltip_size.x - 15
	if tooltip_pos.y < 0:
		tooltip_pos.y = 0
	if tooltip_pos.y + tooltip_size.y > size.y:
		tooltip_pos.y = size.y - tooltip_size.y

	# Draw tooltip background with subtle gradient
	var tooltip_rect = Rect2(tooltip_pos, tooltip_size)
	var bg_color = Color(0.08, 0.1, 0.12, 0.95)
	var border_color = Color(0.4, 0.45, 0.5, 1.0)
	var header_color = Color(0.12, 0.15, 0.18, 1.0)

	# Main background
	draw_rect(tooltip_rect, bg_color)

	# Header background for first line
	if lines.size() > 0:
		var header_rect = Rect2(tooltip_pos, Vector2(tooltip_size.x, line_height + 4))
		draw_rect(header_rect, header_color)

	# Border
	draw_rect(tooltip_rect, border_color, false, 1.5)

	# Draw tooltip text with color coding
	var text_pos = tooltip_pos + padding
	for i in range(lines.size()):
		var line = lines[i]
		var line_pos = text_pos + Vector2(0, i * line_height + 10)
		var text_color = Color.WHITE
		var is_bold = false

		# Color code different types of information
		if i == 0:  # Header line
			text_color = Color.CYAN
		elif line.contains("Open:") or line.contains("MA Price:"):
			text_color = Color.LIGHT_GREEN
		elif line.contains("High:"):
			text_color = Color.GREEN
		elif line.contains("Low:"):
			text_color = Color.ORANGE_RED
		elif line.contains("Close:") or line.contains("Raw Price:"):
			text_color = Color.YELLOW
		elif line.contains("Change:") and line.contains("+"):
			text_color = Color.LIGHT_GREEN
		elif line.contains("Change:") and line.contains("-"):
			text_color = Color.LIGHT_CORAL
		elif line.contains("Volume:"):
			text_color = Color.LIGHT_BLUE
		elif line.contains("Range:"):
			text_color = Color.VIOLET
		elif line.contains("Trend:"):
			if line.contains("Rising") or line.contains("Bullish"):
				text_color = Color.LIGHT_GREEN
			elif line.contains("Falling") or line.contains("Bearish"):
				text_color = Color.LIGHT_CORAL
			else:
				text_color = Color.LIGHT_GRAY
		elif line.contains("Time:"):
			text_color = Color.LIGHT_STEEL_BLUE
		elif line.contains("Intensity:"):
			text_color = Color.MAGENTA

		# Use slightly larger font for header
		var actual_font_size = font_size + (2 if is_bold else 0)

		draw_string(font, line_pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_font_size, text_color)


func draw_grid():
	# Get consistent divisions that match the axis labels
	var grid_divisions_x = 6  # Match X-axis label count
	var grid_divisions_y = 3  # Match Y-axis label count

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# Vertical grid lines (time) - aligned with X-axis labels
	for i in range(grid_divisions_x + 1):
		var x = (float(i) / grid_divisions_x) * size.x
		draw_line(Vector2(x, 0), Vector2(x, size.y * 0.8), grid_color, 1.0)

	# Horizontal grid lines (price) - aligned with Y-axis labels using same calculation
	for i in range(grid_divisions_y + 1):
		var y = chart_y_offset + (float(i) / grid_divisions_y) * chart_height
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)


# Modify the draw_price_line function (around line 200) to include candlestick drawing
func draw_price_line():
	print("=== DRAWING PRICE LINE WITH CANDLESTICKS ===")
	print("Data points: %d, Candlestick data: %d, Time window: %.1f hours" % [price_data.size(), candlestick_data.size(), get_current_time_window() / 3600.0])

	if price_data.size() < 1:
		print("No price data to draw")
		return

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	# Get visible points and price range
	var visible_points = []
	var visible_candles = []

	for i in range(price_data.size()):
		var timestamp = price_data[i].timestamp
		if timestamp >= window_start and timestamp <= window_end:
			visible_points.append(price_data[i])

	# Get visible candlestick data
	for i in range(candlestick_data.size()):
		var timestamp = candlestick_data[i].timestamp
		if timestamp >= window_start and timestamp <= window_end:
			visible_candles.append(candlestick_data[i])

	if visible_points.size() < 1:
		print("No data points in current time window")
		return

	# Use the same price range calculation as Y-axis labels
	var price_info = get_visible_price_range()
	var min_price = price_info.min_price
	var max_price = price_info.max_price
	var price_range = price_info.range

	print("Visible points: %d, Visible candles: %d, Price range: %.2f - %.2f" % [visible_points.size(), visible_candles.size(), min_price, max_price])

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var points: PackedVector2Array = []

	# Sort visible points by timestamp
	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Find the actual data time range (not the window range)
	var data_start_time = visible_points[0].timestamp
	var data_end_time = visible_points[-1].timestamp
	var data_time_span = data_end_time - data_start_time

	# If we only have one point or very close times, use the full window
	if data_time_span < 60.0:  # Less than 1 minute span
		data_start_time = window_start
		data_end_time = window_end
		data_time_span = time_window

	# Draw candlesticks first (behind the moving average line)
	if show_candlesticks and visible_candles.size() > 0:
		draw_candlesticks(visible_candles, data_start_time, data_time_span, min_price, price_range, chart_height, chart_y_offset)

	# Create drawing points for moving average line using actual data range
	for i in range(visible_points.size()):
		var point_data = visible_points[i]

		# X position: map timestamp to chart width using data span (not window span)
		var time_progress = (point_data.timestamp - data_start_time) / data_time_span
		var x = time_progress * size.x

		# Y position: map price to chart height using same range as Y-axis
		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		points.append(Vector2(x, y))

	print("Generated %d drawing points for moving average" % points.size())

	# Draw moving average lines between consecutive data points
	for i in range(points.size() - 1):
		var current_point_data = visible_points[i]
		var next_point_data = visible_points[i + 1]

		# Check if these are consecutive real data points
		var time_diff = next_point_data.timestamp - current_point_data.timestamp
		var is_real_connection = time_diff <= 31536000.0  # Within reasonable time gap

		# Only draw connecting lines between real consecutive data points
		if is_real_connection:
			var current_is_historical = current_point_data.get("is_historical", false)
			var next_is_historical = next_point_data.get("is_historical", false)

			# Both points are historical = historical line
			if current_is_historical and next_is_historical:
				var line_color = Color(0.6, 0.8, 1.0, 0.6)  # More transparent since candlesticks show price
				var line_width = 1.5
				draw_line(points[i], points[i + 1], line_color, line_width, true)
			# One or both are real-time = real-time line
			else:
				var line_color = Color.YELLOW
				var line_width = 2.0
				draw_line(points[i], points[i + 1], line_color, line_width, true)

	# Draw smaller data point circles for moving average (since candlesticks show actual price points)
	for i in range(points.size()):
		var point_data = visible_points[i]
		var is_historical = point_data.get("is_historical", false)
		var volume = point_data.get("volume", 0)

		# Find original index for hover detection
		var original_index = -1
		for j in range(price_data.size()):
			if price_data[j].timestamp == point_data.timestamp:
				original_index = j
				break

		var is_hovered = i == hovered_point_index

		# Get zoom-based scaling
		var scale_factors = get_zoom_scale_factor()
		var base_point_scale = scale_factors.point_scale

		# Smaller circles since candlesticks show the main price data
		var circle_radius = (point_visual_radius * 0.7) * base_point_scale  # 70% of original size
		var circle_color: Color
		var outline_color = Color.WHITE
		var outline_width = 1.0 * base_point_scale

		# Different styling for moving average points
		if volume > 0:
			# Real data point - moving average indicator
			circle_color = Color(0.9, 0.9, 0.4, 0.8) if is_historical else Color.ORANGE
		else:
			# Gap fill / interpolated point
			circle_color = Color(0.5, 0.5, 0.6, 0.6)
			outline_color = Color.GRAY

		# Highlight hovered point
		if is_hovered:
			circle_radius *= 1.5
			outline_width = 1.5
			outline_color = Color.CYAN

		# Ensure minimum visibility
		circle_radius = max(circle_radius, 2.0)
		outline_width = max(outline_width, 0.5)

		# Draw circle with outline
		draw_circle(points[i], circle_radius + outline_width, outline_color, true)
		draw_circle(points[i], circle_radius, circle_color, true)

		# Inner highlight for real data only
		if volume > 0 and (not is_historical or is_hovered):
			var highlight_color = Color.WHITE
			highlight_color.a = 0.4 if is_hovered else 0.2
			draw_circle(points[i], circle_radius * 0.6, highlight_color, true)


# Add this new function after draw_price_line
func draw_candlesticks(visible_candles: Array, data_start_time: float, data_time_span: float, min_price: float, price_range: float, chart_height: float, chart_y_offset: float):
	"""Draw candlestick chart with trend-colored high/low wicks"""
	print("Drawing %d candlesticks with trend-colored wicks" % visible_candles.size())

	# Get zoom scaling
	var scale_factors = get_zoom_scale_factor()
	var scaled_candle_width = candle_width * scale_factors.volume_scale
	var scaled_wick_width = max(2.0, wick_width * scale_factors.volume_scale)

	for i in range(visible_candles.size()):
		var candle = visible_candles[i]
		var timestamp = candle.timestamp

		# Calculate X position using same method as price line
		var time_progress = (timestamp - data_start_time) / data_time_span
		var x = time_progress * size.x

		# Get OHLC prices
		var open_price = candle.get("open", 0.0)
		var high_price = candle.get("high", 0.0)
		var low_price = candle.get("low", 0.0)
		var close_price = candle.get("close", 0.0)

		if high_price <= 0 or low_price <= 0:
			continue

		# Calculate Y positions
		var open_y = chart_y_offset + chart_height - ((open_price - min_price) / price_range * chart_height)
		var high_y = chart_y_offset + chart_height - ((high_price - min_price) / price_range * chart_height)
		var low_y = chart_y_offset + chart_height - ((low_price - min_price) / price_range * chart_height)
		var close_y = chart_y_offset + chart_height - ((close_price - min_price) / price_range * chart_height)

		# Determine trend colors based on close vs open
		var candle_color: Color
		var wick_trend_color: Color
		var price_diff = close_price - open_price

		if price_diff > 0.01:  # Bullish trend
			candle_color = Color(0.1, 0.8, 0.1, 0.9)  # Green body
			wick_trend_color = Color(0.0, 0.9, 0.0, 1.0)  # GREEN wicks for upward trend
		elif price_diff < -0.01:  # Bearish trend
			candle_color = Color(0.8, 0.1, 0.1, 0.9)  # Red body
			wick_trend_color = Color(0.9, 0.0, 0.0, 1.0)  # RED wicks for downward trend
		else:  # Neutral/Doji
			candle_color = Color(0.6, 0.6, 0.6, 0.9)  # Gray body
			wick_trend_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray wicks for neutral

		# Draw the body first
		var body_top = min(open_y, close_y)
		var body_bottom = max(open_y, close_y)
		var body_height = max(body_bottom - body_top, 3.0)
		var body_rect = Rect2(x - scaled_candle_width / 2, body_top, scaled_candle_width, body_height)

		draw_rect(body_rect, candle_color, true)

		# Draw HIGH wick with trend color (from high to top of body)
		if high_y < body_top:
			draw_line(Vector2(x, high_y), Vector2(x, body_top), wick_trend_color, scaled_wick_width, false)

		# Draw LOW wick with trend color (from bottom of body to low)
		if low_y > body_bottom:
			draw_line(Vector2(x, body_bottom), Vector2(x, low_y), wick_trend_color, scaled_wick_width, false)

		# Add border to body
		var border_color = wick_trend_color.darkened(0.3)
		draw_rect(body_rect, border_color, false, 1.0)


# Modify draw_volume_bars to maintain consistent bar width
func draw_volume_bars():
	print("=== DRAWING VOLUME BARS WITH ZOOM SCALING ===")
	print("Volume data size: %d, Time window: %.1f days" % [volume_data.size(), get_current_time_window() / 86400.0])

	if volume_data.size() == 0 or price_data.size() == 0:
		print("No volume or price data to draw")
		return

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	# Get zoom-based scaling
	var scale_factors = get_zoom_scale_factor()
	var volume_scale = scale_factors.volume_scale

	# Collect all volume data within the time window
	var visible_volume_data = []
	var visible_timestamps = []
	var visible_historical_flags = []
	var visible_indices = []
	var historical_max = 0
	var all_max = 0

	for i in range(min(volume_data.size(), price_data.size())):
		var timestamp = price_data[i].timestamp
		if timestamp >= window_start and timestamp <= window_end:
			var volume = volume_data[i]
			var is_historical = price_data[i].get("is_historical", false)

			visible_volume_data.append(volume)
			visible_timestamps.append(timestamp)
			visible_historical_flags.append(is_historical)
			visible_indices.append(i)

			# Track maximums for scaling
			if volume > all_max:
				all_max = volume
			if is_historical and volume > historical_max:
				historical_max = volume

	if visible_volume_data.size() == 0:
		print("No visible volume data in time window")
		return

	print("Visible volume bars: %d, Volume scale: %.2f" % [visible_volume_data.size(), volume_scale])

	# Find the actual data time range for full-width scaling
	var data_start_time = visible_timestamps[0]
	var data_end_time = visible_timestamps[-1]
	var data_time_span = data_end_time - data_start_time

	# If we only have one point or very close times, use the full window
	if data_time_span < 60.0:  # Less than 1 minute span
		data_start_time = window_start
		data_end_time = window_end
		data_time_span = time_window

	# Use historical max for scaling, fall back to all max if no historical data
	var scaling_max = historical_max if historical_max > 0 else all_max
	var volume_cap = scaling_max * 3  # Cap for real-time spikes

	var volume_height_scale = size.y * 0.3
	var base_bar_width = 30.0 * volume_scale  # Apply zoom scaling to bar width
	var bars_drawn = 0

	# Draw all visible volume bars
	for i in range(visible_volume_data.size()):
		var volume = visible_volume_data[i]
		var timestamp = visible_timestamps[i]
		var is_historical = visible_historical_flags[i]
		var original_index = visible_indices[i]

		# Calculate X position based on data time span (not window span)
		var time_progress = (timestamp - data_start_time) / data_time_span
		var x = time_progress * size.x

		# Skip if somehow outside visible area
		if x < -base_bar_width or x > size.x + base_bar_width:
			continue

		# Cap extreme volumes for display consistency
		var display_volume = volume
		if not is_historical and volume > volume_cap:
			display_volume = volume_cap

		# Scale volume to bar height
		var normalized_volume = float(display_volume) / scaling_max
		var bar_height = normalized_volume * volume_height_scale

		# Ensure minimum visibility
		if bar_height < 1.0:
			bar_height = 1.0

		# Cap maximum height
		var max_bar_height = size.y * 0.15
		if bar_height > max_bar_height:
			bar_height = max_bar_height

		var y = size.y - bar_height
		var bar_rect = Rect2(x - base_bar_width / 2, y, base_bar_width, bar_height)

		# Color coding based on data type and age
		var bar_color: Color
		if is_historical:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.2, 0.4, 0.8, 0.8) * volume_intensity
		else:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.8, 0.9, 0.2, 0.9) * volume_intensity

		# Draw the volume bar
		draw_rect(bar_rect, bar_color)

		# Add highlight when hovered
		if hovered_volume_index == original_index:
			# Draw highlight overlay
			var highlight_color = Color(1.0, 1.0, 1.0, 0.3)  # White with transparency
			draw_rect(bar_rect, highlight_color)

			# Draw highlight border
			var border_color = Color.CYAN
			var border_width = max(1.0, 2.0 * volume_scale)
			draw_rect(bar_rect, border_color, false, border_width)

		# Add subtle border (scaled) - only for non-hovered bars
		elif bar_height > 1:
			var border_height = max(1.0, 1.0 * volume_scale)
			draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x, border_height)), Color.WHITE * 0.2)

		# Draw volume label ONLY when this bar is hovered
		if hovered_volume_index == original_index:
			var font = ThemeDB.fallback_font
			var font_size = max(8, int(10 * volume_scale))  # Scale font size too
			var volume_text = format_number(volume)
			var text_size = font.get_string_size(volume_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			# Position label above the bar
			var label_x = x - text_size.x / 2
			var label_y = y - 6

			# Ensure label stays within bounds
			if label_x >= 0 and label_x + text_size.x <= size.x and label_y > text_size.y:
				# Draw volume label with background for better visibility when highlighted
				var bg_padding = Vector2(4, 2)
				var label_bg_rect = Rect2(Vector2(label_x - bg_padding.x, label_y - text_size.y - bg_padding.y), Vector2(text_size.x + bg_padding.x * 2, text_size.y + bg_padding.y * 2))

				# Draw text
				var text_color = Color.WHITE
				draw_string(font, Vector2(label_x, label_y), volume_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

		bars_drawn += 1

	print("Drew %d volume bars with %.2f scale factor" % [bars_drawn, volume_scale])


func draw_price_levels():
	"""Draw exactly one support line and one resistance line"""
	if price_data.is_empty():
		return

	# Get the visible price range
	var price_info = get_visible_price_range()
	if price_info.count == 0:
		return

	var min_price = price_info.min_price
	var max_price = price_info.max_price
	var price_range = price_info.range

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# Draw exactly ONE support level
	if support_levels.size() > 0:
		var support_level = support_levels[0]

		# Only draw if within visible range
		if support_level >= min_price and support_level <= max_price:
			var price_ratio = (support_level - min_price) / price_range
			var y = chart_y_offset + chart_height - (price_ratio * chart_height)

			# Draw support line
			draw_line(Vector2(0, y), Vector2(size.x, y), Color.GREEN, 1.0, false)

			# Draw support label
			var font = ThemeDB.fallback_font
			var font_size = 10
			var label_text = "S: %s" % format_price_label(support_level)
			var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var label_x = 10
			var label_y = y - 6

			# Draw label background
			var bg_rect = Rect2(Vector2(label_x - 3, label_y - text_size.y - 2), Vector2(text_size.x + 6, text_size.y + 8))
			draw_rect(bg_rect, Color(0, 0.5, 0, 0.3))
			draw_string(font, Vector2(label_x, label_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Draw exactly ONE resistance level
	if resistance_levels.size() > 0:
		var resistance_level = resistance_levels[0]

		# Only draw if within visible range
		if resistance_level >= min_price and resistance_level <= max_price:
			var price_ratio = (resistance_level - min_price) / price_range
			var y = chart_y_offset + chart_height - (price_ratio * chart_height)

			# Draw resistance line
			draw_line(Vector2(0, y), Vector2(size.x, y), Color.RED, 1.0, false)

			# Draw resistance label
			var font = ThemeDB.fallback_font
			var font_size = 10
			var label_text = "R: %s" % format_price_label(resistance_level)
			var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var label_x = 10
			var label_y = y + text_size.y + 8

			# Draw label background
			var bg_rect = Rect2(Vector2(label_x - 3, label_y - text_size.y - 2), Vector2(text_size.x + 6, text_size.y + 8))
			draw_rect(bg_rect, Color(0.5, 0, 0, 0.3))
			draw_string(font, Vector2(label_x, label_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	print("Drew %d support lines, %d resistance lines" % [1 if support_levels.size() > 0 else 0, 1 if resistance_levels.size() > 0 else 0])


func draw_y_axis_labels():
	"""Draw price labels for currently visible price range in time window"""
	var price_info = get_visible_price_range()

	if price_info.count == 0:
		print("No visible prices in current time window for Y-axis labels")
		return

	var min_price = price_info.min_price
	var max_price = price_info.max_price
	var price_range = price_info.range

	print("Y-axis labels: visible price range %.2f - %.2f (from %d points)" % [min_price, max_price, price_info.count])

	var font_size = 10
	var grid_divisions = 3  # Match grid line count
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# Draw price labels for the visible range
	for i in range(grid_divisions + 1):
		var ratio = float(i) / grid_divisions
		# Map from top to bottom (highest price at top)
		var price_value = max_price - (ratio * price_range)
		var y_pos = chart_y_offset + (ratio * chart_height)

		# Format price based on magnitude
		var price_text = format_price_label(price_value)

		# Draw price label aligned with grid line
		var text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(chart_font, Vector2(4, y_pos + text_size.y / 2 - 2), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func draw_x_axis_labels():
	"""Draw time labels for current time window with proper scaling"""
	var font_size = 9
	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()

	# Get actual data range for consistent scaling with chart
	var data_start_time = current_time - time_window
	var data_end_time = current_time
	var data_time_span = time_window

	# Check if we have actual data to determine real time range
	if price_data.size() > 0:
		var visible_points = []
		for point in price_data:
			if point.timestamp >= data_start_time and point.timestamp <= data_end_time:
				visible_points.append(point)

		if visible_points.size() > 0:
			visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
			var actual_start = visible_points[0].timestamp
			var actual_end = visible_points[-1].timestamp
			var actual_span = actual_end - actual_start

			# Use actual data range if it spans more than 1 minute
			if actual_span > 60.0:
				data_start_time = actual_start
				data_end_time = actual_end
				data_time_span = actual_span

	var grid_divisions = 6  # Match grid line count
	var chart_bottom = size.y * 0.7

	for i in range(grid_divisions + 1):
		var time_progress = float(i) / grid_divisions
		var target_time = data_start_time + (time_progress * data_time_span)
		var x_pos = time_progress * size.x

		var hours_back = (current_time - target_time) / 3600.0
		var time_text = format_time_for_window(hours_back, time_window)

		var text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_x = x_pos - text_size.x / 2

		draw_string(chart_font, Vector2(label_x, chart_bottom + text_size.y + 4), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func draw_crosshair():
	"""Draw crosshair and price/time info at mouse position, adjusted for time range zoom"""
	if not show_crosshair or hovered_point_index != -1:  # Don't show crosshair tooltip if hovering over a point
		return

	# Draw crosshair lines
	draw_line(Vector2(0, mouse_position.y), Vector2(size.x, mouse_position.y), Color.DIM_GRAY, 1.0, false)
	draw_line(Vector2(mouse_position.x, 0), Vector2(mouse_position.x, size.y), Color.DIM_GRAY, 1.0, false)

	# Calculate price and time at mouse position using current time window
	if price_data.size() > 0:
		var current_time = Time.get_unix_time_from_system()
		var time_window = get_current_time_window()

		# Use same data range calculation as chart drawing
		var data_start_time = current_time - time_window
		var data_end_time = current_time
		var data_time_span = time_window

		# Check for actual data range
		var visible_points = []
		for point in price_data:
			if point.timestamp >= data_start_time and point.timestamp <= data_end_time:
				visible_points.append(point)

		if visible_points.size() > 0:
			visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
			var actual_start = visible_points[0].timestamp
			var actual_end = visible_points[-1].timestamp
			var actual_span = actual_end - actual_start

			# Use actual data range if it spans more than 1 minute
			if actual_span > 60.0:
				data_start_time = actual_start
				data_end_time = actual_end
				data_time_span = actual_span

		# Get visible price range for accurate price calculation
		var visible_prices = []
		for point in price_data:
			if point.timestamp >= data_start_time and point.timestamp <= data_end_time:
				visible_prices.append(point.price)

		if visible_prices.size() > 0:
			var min_price = visible_prices[0]
			var max_price = visible_prices[0]
			for price in visible_prices:
				if price < min_price:
					min_price = price
				if price > max_price:
					max_price = price

			var price_range = max_price - min_price
			if price_range > 0:
				# Calculate price at mouse Y position using visible price range
				var chart_height = size.y * 0.6
				var chart_y_offset = size.y * 0.05
				var price_y_ratio = (chart_y_offset + chart_height - mouse_position.y) / chart_height
				var price_at_mouse = min_price + (price_y_ratio * price_range)

				# Calculate time at mouse X position using data time span
				var time_ratio = mouse_position.x / size.x
				var time_at_mouse = data_start_time + (time_ratio * data_time_span)
				var time_diff = current_time - time_at_mouse

				# Format time based on current time window
				var time_text = format_crosshair_time(time_diff, time_window)

				# Draw crosshair tooltip
				var font = ThemeDB.fallback_font
				var font_size = 11
				var tooltip_text = "%.2f ISK | %s" % [price_at_mouse, time_text]
				var text_size = font.get_string_size(tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

				var padding = Vector2(6, 4)
				var tooltip_size = text_size + padding * 2

				var label_pos = Vector2(mouse_position.x + 10, mouse_position.y - 10)
				if label_pos.x + tooltip_size.x > size.x:
					label_pos.x = mouse_position.x - tooltip_size.x - 10
				if label_pos.y - tooltip_size.y < 0:
					label_pos.y = mouse_position.y + 20

				# Draw text
				draw_string(font, label_pos, tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.LIGHT_GRAY)


func draw_zoom_indicator():
	"""Draw time window indicator"""
	var font = ThemeDB.fallback_font
	var font_size = 10
	var time_window = get_current_time_window()
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

	var text_size = font.get_string_size(zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding = Vector2(8, 4)

	var bg_rect = Rect2(size.x - text_size.x - padding.x * 2 - 5, 5, text_size.x + padding.x * 2, text_size.y + padding.y * 2)
	var bg_color = Color(0.1, 0.1, 0.15, 0.8)
	var text_color = Color.YELLOW if zoom_level != 1.0 else Color.WHITE

	draw_rect(bg_rect, bg_color)
	draw_rect(bg_rect, Color(0.3, 0.3, 0.4, 0.8), false, 1.0)
	draw_string(font, Vector2(bg_rect.position.x + padding.x, bg_rect.position.y + padding.y + text_size.y), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func zoom_in(_zoom_point: Vector2):
	var old_zoom = zoom_level
	zoom_level = min(zoom_level * zoom_sensitivity, max_zoom)  # MULTIPLY to zoom IN

	if zoom_level != old_zoom:
		var days = (base_time_window / zoom_level) / 86400.0
		update_price_levels()
		on_zoom_changed()
		print("Zoomed in to %.1fx (%.1f days)" % [zoom_level, days])


func zoom_out(_zoom_point: Vector2):
	var old_zoom = zoom_level
	zoom_level = max(zoom_level / zoom_sensitivity, min_zoom)  # DIVIDE to zoom OUT

	if zoom_level != old_zoom:
		var days = (base_time_window / zoom_level) / 86400.0
		update_price_levels()
		on_zoom_changed()
		print("Zoomed out to %.1fx (%.1f days)" % [zoom_level, days])


func reset_zoom():
	zoom_level = 1.0
	queue_redraw()
	print("Reset zoom to 1.0x (24 hours)")


func find_closest_time_index(target_time: float) -> int:
	"""Find the data point closest to the target time"""
	if price_data.is_empty():
		return -1

	var closest_index = 0
	var smallest_diff = abs(price_data[0].timestamp - target_time)

	for i in range(1, price_data.size()):
		var diff = abs(price_data[i].timestamp - target_time)
		if diff < smallest_diff:
			smallest_diff = diff
			closest_index = i

	return closest_index


func format_time_label(hours_back: float) -> String:
	"""Format time labels for 1-day view"""
	if hours_back < 1.0:
		return "Now"
	if hours_back < 24.0:
		return "-%dh" % int(hours_back)

	var days = int(hours_back / 24.0)
	var remaining_hours = int(hours_back) % 24
	if remaining_hours == 0:
		return "-%dd" % days

	return "-%dd%dh" % [days, remaining_hours]


func format_day_time_label(hours_from_start: float) -> String:
	"""Format time labels showing time of day"""
	var hour = int(hours_from_start) % 24

	# Convert to 12-hour format for readability
	if hour == 0:
		return "12AM"
	if hour < 12:
		return "%dAM" % hour
	if hour == 12:
		return "12PM"

	return "%dPM" % (hour - 12)


func format_rolling_time_label(hours_back: float) -> String:
	"""Format time labels for rolling 24-hour view"""
	if hours_back < 0.5:
		return "Now"
	if hours_back < 1.0:
		return "-%dm" % int(hours_back * 60)
	if hours_back < 24.0:
		return "-%dh" % int(hours_back)

	return "-1d"


func format_number(value: float) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return "%.0f" % value


func format_time_for_window(hours_back: float, time_window: float) -> String:
	var window_days = time_window / 86400.0

	if window_days <= 1:  # 1 day or less - show hours
		if hours_back < 0.5:
			return "Now"
		return "-%dh" % int(hours_back)
	if window_days <= 7:  # 1 week or less - show days
		if hours_back < 12:
			return "-%dh" % int(hours_back)
		var days = hours_back / 24.0
		return "-%.1fd" % days
	if window_days <= 30:  # 1 month or less - show weeks
		var weeks = hours_back / 168.0
		if weeks < 1:
			var days = hours_back / 24.0
			return "-%.0fd" % days
		return "-%.1fw" % weeks
	if window_days <= 365:  # 1 year or less - show months
		var months = hours_back / 720.0
		if months < 1:
			var weeks = hours_back / 168.0
			return "-%.0fw" % weeks
		return "-%.1fm" % months

	var years = hours_back / 8760.0
	return "-%.1fy" % years


func format_crosshair_time(time_diff: float, time_window: float) -> String:
	"""Format time difference for crosshair based on current time window"""
	var window_hours = time_window / 3600.0

	if time_diff < 0:
		return "Future"

	if window_hours <= 6:  # Short window - show precise minutes/seconds
		if time_diff < 60:
			return "%.0fs ago" % time_diff
		if time_diff < 3600:
			return "%.0fm ago" % (time_diff / 60.0)

		return "%.1fh ago" % (time_diff / 3600.0)
	if window_hours <= 24:  # Medium window - show minutes/hours
		if time_diff < 300:  # Less than 5 minutes
			return "%.0fm ago" % (time_diff / 60.0)
		if time_diff < 3600:
			return "%.0fm ago" % (time_diff / 60.0)

		return "%.1fh ago" % (time_diff / 3600.0)
	if window_hours <= 168:  # Up to a week - show hours/days
		if time_diff < 3600:
			return "%.0fh ago" % (time_diff / 3600.0)
		if time_diff < 86400:
			return "%.1fh ago" % (time_diff / 3600.0)

		return "%.1fd ago" % (time_diff / 86400.0)

	if time_diff < 86400:
		return "%.1fd ago" % (time_diff / 86400.0)

	var days = time_diff / 86400.0
	if days < 7:
		return "%.1fd ago" % days

	return "%.1fw ago" % (days / 7.0)


func get_timeframe_info() -> String:
	"""Return human-readable timeframe info"""
	return "24 Hours"


func set_timeframe_hours(hours: float):
	"""Allow changing the timeframe"""
	timeframe_hours = hours
	data_retention_seconds = hours * 3600.0  # Convert to seconds

	# Clean up existing data that's outside new timeframe
	if not price_data.is_empty():
		cleanup_old_data()  # Remove the parameter

	queue_redraw()
	print("Chart timeframe set to %.1f hours" % hours)


func set_day_start_time():
	"""Set the start time to 1 year ago for full year view"""
	var current_time = Time.get_unix_time_from_system()
	day_start_timestamp = current_time - 31536000.0  # Start exactly 1 year ago
	has_loaded_historical = false

	print("Chart window set to show last 1 year")
	print("Start time: ", Time.get_datetime_string_from_unix_time(day_start_timestamp))
	print("End time: ", Time.get_datetime_string_from_unix_time(current_time))
	print("Window duration: %.1f days" % ((current_time - day_start_timestamp) / 86400.0))


func add_candlestick_data_point(open: float, high: float, low: float, close: float, volume: int, timestamp: float):
	"""Add a candlestick data point with OHLC values"""
	var current_time = Time.get_unix_time_from_system()
	var max_age = max_data_retention
	var oldest_allowed = current_time - max_age

	if timestamp < oldest_allowed or timestamp > current_time:
		print("Candlestick data point rejected: outside time window")
		return

	var candle_data = {"open": open, "high": high, "low": low, "close": close, "volume": volume, "timestamp": timestamp, "is_historical": true}  # Assuming daily candles are historical

	candlestick_data.append(candle_data)
	print("Added candlestick: O:%.2f H:%.2f L:%.2f C:%.2f V:%d" % [open, high, low, close, volume])

	# Keep data sorted by timestamp
	candlestick_data.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Clean up old candlestick data
	while candlestick_data.size() > 0 and candlestick_data[0].timestamp < oldest_allowed:
		candlestick_data.pop_front()


func add_data_point(price: float, volume: int, time_label: String = ""):
	print("=== ADDING REAL-TIME DATA POINT ===")
	print("Price: %.2f, Volume: %d" % [price, volume])
	print("Current data points: price=%d, volume=%d" % [price_data.size(), volume_data.size()])

	# Load historical data on first data point if not already loaded
	if price_data.size() == 0 and not has_loaded_historical and not is_loading_historical:
		print("First data point - requesting historical data...")
		request_historical_data()

	# Store the raw price for moving average calculation
	price_history.append(price)

	# Calculate moving average
	var avg_price = calculate_moving_average()

	var current_time = Time.get_unix_time_from_system()
	var window_start = current_time - 432000.0
	var seconds_from_start = current_time - window_start

	# Check if we already have a recent real-time point (within last 5 minutes)
	var recent_realtime_found = false
	var recent_cutoff = current_time - 300.0  # 5 minutes ago

	for i in range(price_data.size() - 1, -1, -1):  # Go backwards through data
		var point = price_data[i]
		if not point.get("is_historical", false) and point.timestamp > recent_cutoff:
			# Replace this recent real-time point instead of adding a new one
			print("Replacing recent real-time point from %s" % Time.get_datetime_string_from_unix_time(point.timestamp))

			# Update the existing point
			point.price = avg_price
			point.raw_price = price
			point.volume = volume
			point.timestamp = current_time
			point.time_label = time_label
			point.seconds_from_day_start = seconds_from_start

			# Update corresponding arrays
			volume_data[i] = volume
			time_labels[i] = time_label

			recent_realtime_found = true
			break

	# Only add new point if we didn't replace an existing one
	if not recent_realtime_found:
		var data_point = {
			"price": avg_price, "raw_price": price, "volume": volume, "timestamp": current_time, "time_label": time_label, "seconds_from_day_start": seconds_from_start, "is_historical": false
		}

		price_data.append(data_point)
		volume_data.append(volume)
		time_labels.append(time_label)
		print("Added new real-time point")
	else:
		print("Replaced existing real-time point")

	print("Total data points after update: price=%d, volume=%d" % [price_data.size(), volume_data.size()])

	# Keep rolling window
	cleanup_old_data()

	# Update support/resistance levels with new data
	update_price_levels()

	if price_data.size() % 10 == 0:  # Update every 10 data points
		update_price_levels()

	queue_redraw()


func request_historical_data():
	"""Request historical market data for the past 24 hours"""
	if is_loading_historical:
		print("Already loading historical data, skipping...")
		return

	is_loading_historical = true
	print("Requesting historical data for new item...")

	# Emit signal to request historical data
	if has_signal("historical_data_requested"):
		emit_signal("historical_data_requested")
	else:
		print("ERROR: historical_data_requested signal not connected!")


func add_historical_data_point(price: float, volume: int, timestamp: float):
	"""Add a historical data point with specific timestamp"""
	var current_time = Time.get_unix_time_from_system()
	var max_age = max_data_retention  # Allow data up to 5 days old
	var oldest_allowed = current_time - max_age

	var hours_ago = (current_time - timestamp) / 3600.0

	print("Adding historical point: %.1fh ago, price=%.2f, volume=%d" % [hours_ago, price, volume])
	print("  Timestamp: %s" % Time.get_datetime_string_from_unix_time(timestamp))
	print("  Oldest allowed: %s" % Time.get_datetime_string_from_unix_time(oldest_allowed))

	# Check if within maximum retention window (5 days)
	if timestamp < oldest_allowed:
		print("  REJECTED: Too old (%.1f hours ago, max %.1f hours)" % [hours_ago, max_age / 3600.0])
		return

	if timestamp > current_time:
		print("  REJECTED: In the future")
		return

	var seconds_from_start = timestamp - oldest_allowed

	var data_point = {
		"price": price,
		"raw_price": price,
		"volume": volume,
		"timestamp": timestamp,
		"time_label": Time.get_datetime_string_from_unix_time(timestamp).substr(11, 8),
		"seconds_from_day_start": seconds_from_start,
		"is_historical": true
	}

	price_data.append(data_point)
	volume_data.append(volume)
	time_labels.append(data_point.time_label)

	print("  ACCEPTED: Added historical point. Total: %d" % price_data.size())


func finish_historical_data_load():
	"""Called when historical data loading is complete"""
	print("=== FINISHING HISTORICAL DATA LOAD ===")
	print("Data before sorting: price=%d, volume=%d, time=%d" % [price_data.size(), volume_data.size(), time_labels.size()])

	if price_data.size() == 0:
		print("ERROR: No data points to sort!")
		has_loaded_historical = true
		is_loading_historical = false
		queue_redraw()
		return

	# Debug data before sorting
	var historical_count = 0
	var realtime_count = 0
	for point in price_data:
		if point.get("is_historical", false):
			historical_count += 1
		else:
			realtime_count += 1
	print("Before sorting: %d historical, %d realtime" % [historical_count, realtime_count])

	# Ensure all arrays are the same size
	var min_size = min(price_data.size(), min(volume_data.size(), time_labels.size()))
	if price_data.size() != volume_data.size() or price_data.size() != time_labels.size():
		print("WARNING: Array size mismatch - trimming to %d" % min_size)
		price_data = price_data.slice(0, min_size)
		volume_data = volume_data.slice(0, min_size)
		time_labels = time_labels.slice(0, min_size)

	# Sort all data by timestamp
	var combined_data = []
	for i in range(price_data.size()):
		combined_data.append({"price_data": price_data[i], "volume": volume_data[i], "time_label": time_labels[i]})

	# Sort by timestamp
	combined_data.sort_custom(func(a, b): return a.price_data.timestamp < b.price_data.timestamp)

	# Rebuild arrays in sorted order
	price_data.clear()
	volume_data.clear()
	time_labels.clear()

	for item in combined_data:
		price_data.append(item.price_data)
		volume_data.append(item.volume)
		time_labels.append(item.time_label)

	has_loaded_historical = true
	is_loading_historical = false

	print("=== HISTORICAL DATA FINALIZED ===")
	print("Final data count: price=%d, volume=%d" % [price_data.size(), volume_data.size()])

	# Debug final data
	historical_count = 0
	realtime_count = 0
	var current_time = Time.get_unix_time_from_system()
	for i in range(price_data.size()):
		var point = price_data[i]
		var hours_ago = (current_time - point.timestamp) / 3600.0
		if point.get("is_historical", false):
			historical_count += 1
		else:
			realtime_count += 1

		# Debug first and last few points
		if i < 3 or i >= price_data.size() - 3:
			print("  Point %d: %.1fh ago, price=%.2f, vol=%d, historical=%s" % [i, hours_ago, point.price, volume_data[i], point.get("is_historical", false)])

	print("Final: %d historical, %d realtime" % [historical_count, realtime_count])
	queue_redraw()


func start_new_day():
	"""Start tracking a new day"""
	print("Starting new trading day")
	set_day_start_time()
	clear_data()


func calculate_moving_average() -> float:
	if price_history.is_empty():
		return 0.0

	var period = min(moving_average_period, price_history.size())
	var sum = 0.0

	# Calculate average of last 'period' prices
	for i in range(price_history.size() - period, price_history.size()):
		sum += price_history[i]

	return sum / period


func update_price_levels():
	"""Calculate exactly one support and one resistance level from visible data"""
	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window

	# ALWAYS clear previous levels first
	support_levels.clear()
	resistance_levels.clear()

	# Get visible prices only
	var visible_prices = []
	for point in price_data:
		if point.timestamp >= window_start:
			visible_prices.append(point.price)

	if visible_prices.size() < 5:
		print("Not enough visible data points (%d) for support/resistance calculation" % visible_prices.size())
		return

	# Sort prices
	visible_prices.sort()

	# Simple method: Use quartiles for support and resistance
	var q1_index = visible_prices.size() / 4  # 25th percentile = support
	var q3_index = (visible_prices.size() * 3) / 4  # 75th percentile = resistance

	# Add exactly ONE support level
	if q1_index < visible_prices.size():
		support_levels.append(visible_prices[q1_index])

	# Add exactly ONE resistance level
	if q3_index < visible_prices.size():
		resistance_levels.append(visible_prices[q3_index])

	print("Set support: %.2f, resistance: %.2f" % [support_levels[0] if support_levels.size() > 0 else 0.0, resistance_levels[0] if resistance_levels.size() > 0 else 0.0])


func clear_data():
	print("=== CLEARING CHART DATA ===")
	print("Clearing %d price points, %d volume points, %d candlesticks" % [price_data.size(), volume_data.size(), candlestick_data.size()])

	price_data.clear()
	volume_data.clear()
	time_labels.clear()
	price_history.clear()
	support_levels.clear()
	resistance_levels.clear()
	candlestick_data.clear()  # Add this line

	# Reset historical data flags
	has_loaded_historical = false
	is_loading_historical = false

	queue_redraw()
	print("Chart data cleared - ready for new item")


func format_price_label(price: float) -> String:
	"""Format price for axis labels"""
	if price >= 1000000000:
		return "%.2fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.2fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.2fK" % (price / 1000.0)
	if price >= 1:
		return "%.3f" % price

	return "%.4f" % price


# Add this new helper function for consistent time formatting
func format_time_ago(hours_ago: float) -> String:
	"""Format time difference in a human-readable way"""
	print("DEBUG: format_time_ago called with hours_ago = %.2f" % hours_ago)

	if hours_ago < 0.1:
		return "Now"
	if hours_ago < 1.0:
		var minutes = int(hours_ago * 60)
		return "%d minute%s ago" % [minutes, "s" if minutes != 1 else ""]
	if hours_ago < 24.0:
		var hours = int(hours_ago)
		return "%d hour%s ago" % [hours, "s" if hours != 1 else ""]
	if hours_ago < 168.0:  # Less than a week (7 * 24 = 168 hours)
		var days = int(hours_ago / 24.0)
		var remaining_hours = int(hours_ago) % 24
		if remaining_hours == 0:
			return "%d day%s ago" % [days, "s" if days != 1 else ""]
		return "%dd %dh ago" % [days, remaining_hours]
	if hours_ago < 730.0:  # Less than a month (30.4 * 24 = 730 hours)
		var weeks = int(hours_ago / 168.0)
		return "%d week%s ago" % [weeks, "s" if weeks != 1 else ""]
	if hours_ago < 8760.0:  # Less than a year (365 * 24 = 8760 hours)
		var months = int(hours_ago / 730.0)  # Fixed: 730 hours per month, not 720
		return "%d month%s ago" % [months, "s" if months != 1 else ""]

	var years = int(hours_ago / 8760.0)
	return "%d year%s ago" % [years, "s" if years != 1 else ""]


func get_min_price() -> float:
	if price_data.is_empty():
		return 0.0
	var min_val = price_data[0].price
	for point in price_data:
		if point.price < min_val:
			min_val = point.price
	return min_val


func get_max_price() -> float:
	if price_data.is_empty():
		return 0.0
	var max_val = price_data[0].price
	for point in price_data:
		if point.price > max_val:
			max_val = point.price
	return max_val


func get_max_volume() -> int:
	if volume_data.is_empty():
		return 0

	# Use only historical volumes for consistent scaling
	var historical_max = 0

	for i in range(min(volume_data.size(), price_data.size())):
		var vol = volume_data[i]
		if price_data[i].get("is_historical", false):
			if vol > historical_max:
				historical_max = vol

	# Fall back to all data if no historical data
	if historical_max == 0:
		for vol in volume_data:
			if vol > historical_max:
				historical_max = vol

	return historical_max


func set_chart_style(style: String):
	"""Set chart visual style"""
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
	queue_redraw()


func set_moving_average_period(period: int):
	"""Allow customization of moving average period"""
	moving_average_period = max(1, period)
	print("Moving average period set to: ", moving_average_period)


func get_latest_price() -> float:
	if price_data.is_empty():
		return 0.0
	return price_data[-1].price


func get_price_change() -> float:
	if price_data.size() < 2:
		return 0.0
	return price_data[-1].price - price_data[-2].price


func get_price_change_percent() -> float:
	if price_data.size() < 2:
		return 0.0
	var old_price = price_data[-2].price
	if old_price == 0:
		return 0.0
	return ((price_data[-1].price - old_price) / old_price) * 100.0


func get_current_time_window() -> float:
	return base_time_window / zoom_level


func get_day_progress() -> float:
	"""Get progress through current day (0.0 to 1.0)"""
	var current_time = Time.get_unix_time_from_system()
	var seconds_from_start = current_time - day_start_timestamp
	return clamp(seconds_from_start / 86400.0, 0.0, 1.0)


func get_current_day_info() -> String:
	"""Return current day information"""
	var day_date = Time.get_date_string_from_unix_time(day_start_timestamp)
	var progress = get_day_progress() * 100.0
	return "%s (%.1f%% complete)" % [day_date, progress]


func get_visible_price_range() -> Dictionary:
	"""Get min/max prices from data within current time window, including candlestick data"""
	if price_data.is_empty() and candlestick_data.is_empty():
		return {"min_price": 0.0, "max_price": 0.0, "range": 0.0, "count": 0}

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	var all_prices = []

	# Add prices from moving average data
	for point in price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			all_prices.append(point.price)

	# Add prices from candlestick data (include high and low for full range)
	for candle in candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			all_prices.append(candle.get("high", 0.0))
			all_prices.append(candle.get("low", 0.0))

	if all_prices.size() == 0:
		return {"min_price": 0.0, "max_price": 0.0, "range": 0.0, "count": 0}

	var min_price = all_prices[0]
	var max_price = all_prices[0]
	for price in all_prices:
		if price < min_price:
			min_price = price
		if price > max_price:
			max_price = price

	var price_range = max_price - min_price
	if price_range <= 0:
		price_range = max_price * 0.1 if max_price > 0 else 100.0
		min_price = max_price - price_range / 2
		max_price = max_price + price_range / 2

	return {"min_price": min_price, "max_price": max_price, "range": price_range, "count": all_prices.size()}


func check_historical_data_coverage():
	"""Check if we need more historical data for current zoom level"""
	if price_data.size() == 0:
		return

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window

	# Find oldest data point
	var oldest_timestamp = current_time
	for point in price_data:
		if point.timestamp < oldest_timestamp:
			oldest_timestamp = point.timestamp

	# If our oldest data doesn't cover the full time window, we might need more
	var coverage_gap = window_start - oldest_timestamp
	if coverage_gap > 3600:  # More than 1 hour gap
		print("Historical data gap detected: %.1f hours" % (coverage_gap / 3600.0))
		print("Might need to request more historical data")
		# Could emit signal here to request more historical data
		# emit_signal("need_more_historical_data", window_start, oldest_timestamp)


func on_zoom_changed():
	check_historical_data_coverage()
	queue_redraw()


func get_zoom_scale_factor() -> Dictionary:
	"""Calculate scale factors based on current zoom level with better point scaling"""
	var zoom_ratio = zoom_level / max_zoom  # 0.0 (zoomed out) to 1.0 (zoomed in)

	# Point scale: more aggressive scaling for better hover detection
	# When zoomed out (low zoom_ratio), points are much smaller
	# When zoomed in (high zoom_ratio), points are normal/larger size
	var point_scale = lerp(0.5, 2.0, zoom_ratio)  # 50% to 200% size

	# Volume bar scale: similar to point scale
	var volume_scale = lerp(0.1, 1.2, zoom_ratio)  # 10% to 120% width

	return {"point_scale": point_scale, "volume_scale": volume_scale, "zoom_ratio": zoom_ratio}


func cleanup_old_data():
	"""Remove data points older than 1 year"""
	var current_time = Time.get_unix_time_from_system()
	var cutoff_time = current_time - max_data_retention  # 1 year

	var removed_count = 0

	# Remove data older than 1 year
	while price_data.size() > 0 and price_data[0].timestamp < cutoff_time:
		price_data.pop_front()
		if volume_data.size() > 0:
			volume_data.pop_front()
		if time_labels.size() > 0:
			time_labels.pop_front()
		if price_history.size() > 0:
			price_history.pop_front()
		removed_count += 1

	if removed_count > 0:
		print("Cleaned up %d data points older than 1 year" % removed_count)


func debug_chart_data():
	print("=== DETAILED CHART DEBUG ===")
	var current_time = Time.get_unix_time_from_system()
	print("Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))
	print("Price data points: %d" % price_data.size())
	print("Volume data points: %d" % volume_data.size())

	if price_data.size() > 0:
		print("All data points:")
		for i in range(price_data.size()):
			var point = price_data[i]
			var hours_ago = (current_time - point.timestamp) / 3600.0
			print(
				(
					"  Point %d: %.1fh ago, price=%.2f, vol=%d, historical=%s, time=%s"
					% [i, hours_ago, point.price, volume_data[i], point.get("is_historical", false), Time.get_datetime_string_from_unix_time(point.timestamp)]
				)
			)

	print("Has loaded historical: %s" % has_loaded_historical)
	print("Is loading historical: %s" % is_loading_historical)
	print("==========================")


func _make_custom_tooltip(_for_text: String) -> Control:
	# Return null to disable built-in tooltip system completely
	return null


func _get_tooltip(_at_position: Vector2) -> String:
	# Return empty string to disable built-in tooltips
	return ""
