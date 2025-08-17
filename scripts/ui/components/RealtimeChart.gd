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

var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO
var chart_center_time: float = 0.0  # The time at the center of the current view
var chart_center_price: float = 0.0  # The price at the center of the current view
var chart_price_range: float = 0.0  # The current price range being displayed


func _ready():
	custom_minimum_size = Vector2(400, 200)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# DISABLE built-in tooltip system
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = ""

	chart_font = ThemeDB.fallback_font

	# Initialize chart center to current time
	chart_center_time = Time.get_unix_time_from_system()

	# Set default price range (will be updated when data loads)
	chart_center_price = 1000.0  # Default center price
	chart_price_range = 500.0  # Default range

	set_day_start_time()


func _on_mouse_entered():
	show_crosshair = true


func _on_mouse_exited():
	show_crosshair = false
	hovered_point_index = -1
	hovered_volume_index = -1  # Clear hovered volume bar when mouse leaves
	queue_redraw()


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_HOME or event.keycode == KEY_H:
			get_viewport().set_input_as_handled()


func _gui_input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position

		if is_dragging:
			handle_simple_drag(event)
		else:
			check_point_hover(mouse_position)

		get_viewport().set_input_as_handled()
		if show_crosshair:
			queue_redraw()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_simple_drag(event.position)
			else:
				stop_simple_drag()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			reset_to_current()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in_at_mouse(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out_at_mouse(event.position)
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()


func start_simple_drag(position: Vector2):
	"""Start simple dragging"""
	is_dragging = true
	drag_start_position = position
	print("Started dragging")


func stop_simple_drag():
	"""Stop dragging"""
	is_dragging = false
	print("Stopped dragging")


func initialize_price_center():
	"""Initialize the price center based on current data"""
	print("Initializing price center...")

	# First try to get current visible price range
	var price_info = get_visible_price_range()
	print("Price info from get_visible_price_range: ", price_info)

	if price_info.count > 0 and price_info.range > 0:
		chart_center_price = (price_info.min_price + price_info.max_price) / 2.0
		chart_price_range = price_info.range * 1.2  # Add 20% padding
		print("Set price center to %.2f, range %.2f (from data)" % [chart_center_price, chart_price_range])
	else:
		# Fallback: scan all available data
		var all_prices = []

		for point in price_data:
			if point.price > 0:
				all_prices.append(point.price)

		for candle in candlestick_data:
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
			chart_price_range = (max_price - min_price) * 1.2  # Add 20% padding
			print("Set price center to %.2f, range %.2f (from all data)" % [chart_center_price, chart_price_range])
		else:
			# Ultimate fallback
			chart_center_price = 1000.0
			chart_price_range = 500.0
			print("Using fallback price center/range")


func handle_simple_drag(event: InputEventMouseMotion):
	"""Handle simple chart panning"""
	var drag_delta = event.position - drag_start_position

	# Calculate how much to move based on current zoom level
	var time_window = get_current_time_window()
	var time_per_pixel = time_window / size.x
	var price_per_pixel = chart_price_range / (size.y * 0.6)

	# Move chart center (opposite direction of drag for natural feel)
	var time_delta = drag_delta.x * time_per_pixel
	var price_delta = drag_delta.y * price_per_pixel

	chart_center_time -= time_delta
	chart_center_price += price_delta  # This affects Y-axis labels

	# Clamp to reasonable limits
	var current_time = Time.get_unix_time_from_system()
	var max_history = get_max_historical_time()

	chart_center_time = clamp(chart_center_time, max_history + time_window / 2, current_time)

	# Reset drag start for smooth continuous dragging
	drag_start_position = event.position

	queue_redraw()  # This will redraw Y-axis labels with new price center


func zoom_in_at_mouse(mouse_pos: Vector2):
	"""Zoom in toward the mouse position"""
	var old_zoom = zoom_level
	zoom_level = min(zoom_level * zoom_sensitivity, max_zoom)

	if zoom_level != old_zoom:
		# Adjust chart center to zoom toward mouse position
		adjust_center_for_zoom(mouse_pos, old_zoom, zoom_level)
		queue_redraw()  # This will redraw grid with new zoom level
		print("Zoomed in to %.1fx at mouse position" % zoom_level)


func zoom_out_at_mouse(mouse_pos: Vector2):
	"""Zoom out from the mouse position"""
	var old_zoom = zoom_level
	zoom_level = max(zoom_level / zoom_sensitivity, min_zoom)

	if zoom_level != old_zoom:
		# Adjust chart center to zoom from mouse position
		adjust_center_for_zoom(mouse_pos, old_zoom, zoom_level)
		queue_redraw()  # This will redraw grid with new zoom level
		print("Zoomed out to %.1fx from mouse position" % zoom_level)


func adjust_center_for_zoom(mouse_pos: Vector2, old_zoom: float, new_zoom: float):
	"""Adjust chart center so zoom appears to happen at mouse position"""
	# Calculate what time/price the mouse was pointing at before zoom
	var mouse_time = get_time_at_pixel(mouse_pos.x)
	var mouse_price = get_price_at_pixel(mouse_pos.y)

	# Calculate zoom factor
	var zoom_factor = new_zoom / old_zoom

	# Adjust time center
	var time_offset = mouse_time - chart_center_time
	chart_center_time = mouse_time - (time_offset / zoom_factor)

	# Adjust price center (this affects Y-axis labels)
	var price_offset = mouse_price - chart_center_price
	chart_center_price = mouse_price - (price_offset / zoom_factor)

	# Also adjust price range for zoom
	chart_price_range = chart_price_range / zoom_factor


func check_point_hover(mouse_pos: Vector2):
	"""Check if mouse is hovering over any data point, volume bar, or candlestick (simple drag system)"""
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
	var scaled_hover_radius = max(point_hover_radius * scale_factors.point_scale, 6.0)

	# Use new window bounds system
	var bounds = get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

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

	# Sort data
	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# Moving average point hover detection
	var closest_distance = scaled_hover_radius + 1
	var closest_index = -1

	for i in range(visible_points.size()):
		var point = visible_points[i]
		var timestamp = point.timestamp

		var time_progress = (timestamp - window_start) / (window_end - window_start)
		var x = time_progress * size.x

		var normalized_price = (point.price - min_price) / price_range
		var y = chart_y_offset + chart_height * (1.0 - normalized_price)

		var point_pos = Vector2(x, y)
		var distance = mouse_pos.distance_to(point_pos)

		if distance <= scaled_hover_radius and distance < closest_distance:
			closest_distance = distance
			closest_index = i

	if closest_index != -1:
		hovered_point_index = closest_index
		tooltip_position = mouse_pos

		# Use the visible point directly (not price_data array)
		var point = visible_points[closest_index]
		var current_time = Time.get_unix_time_from_system()
		var hours_ago = (current_time - point.timestamp) / 3600.0
		var time_text = format_time_ago(hours_ago)

		# Find volume for this point by matching timestamp
		var volume = 0
		for i in range(min(volume_data.size(), price_data.size())):
			if abs(price_data[i].timestamp - point.timestamp) < 1.0:
				volume = volume_data[i]
				break

		var raw_price = point.get("raw_price", point.price)

		# Find corresponding candlestick data for high/low values
		var high_low_text = ""
		for candle in candlestick_data:
			if abs(candle.timestamp - point.timestamp) < 86400:
				var high_price = candle.get("high", 0.0)
				var low_price = candle.get("low", 0.0)
				if high_price > 0 and low_price > 0:
					high_low_text = "High: %s ISK\nLow: %s ISK\n" % [format_price_label(high_price), format_price_label(low_price)]
				break

		# Calculate trend using visible points
		var trend_text = "Unknown"
		var trend_emoji = "⚪"

		if closest_index >= 4 and visible_points.size() >= 5:
			var recent_prices = []
			for j in range(max(0, closest_index - 4), closest_index + 1):
				recent_prices.append(visible_points[j].price)

			var price_changes = []
			for j in range(1, recent_prices.size()):
				price_changes.append(recent_prices[j] - recent_prices[j - 1])

			var avg_change = 0.0
			for change in price_changes:
				avg_change += change
			avg_change = avg_change / price_changes.size()

			var positive_changes = 0
			var negative_changes = 0
			for change in price_changes:
				if change > 0:
					positive_changes += 1
				elif change < 0:
					negative_changes += 1

			var trend_consistency = float(max(positive_changes, negative_changes)) / price_changes.size()

			var trend_strength = ""
			if trend_consistency >= 0.8:
				trend_strength = "Strong "
			elif trend_consistency >= 0.6:
				trend_strength = "Moderate "
			else:
				trend_strength = "Weak "

			if avg_change > 0.01 and trend_consistency >= 0.6:
				trend_text = "%sRising" % trend_strength
				trend_emoji = "📈"
			elif avg_change < -0.01 and trend_consistency >= 0.6:
				trend_text = "%sFalling" % trend_strength
				trend_emoji = "📉"
			else:
				trend_text = "Sideways"
				trend_emoji = "➡️"

		elif closest_index > 0:
			var prev_price = visible_points[closest_index - 1].price
			if point.price > prev_price:
				trend_text = "Rising"
				trend_emoji = "📈"
			elif point.price < prev_price:
				trend_text = "Falling"
				trend_emoji = "📉"
			else:
				trend_text = "Stable"
				trend_emoji = "➡️"

		tooltip_text = ("Price: %s ISK\n" % format_price_label(point.price) + high_low_text + "Volume: %s\n" % format_number(volume) + "Trend: %s\n" % trend_text + "Time: %s" % time_text)

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
	draw_zoom_indicator()
	draw_drag_indicator()

	# Only draw one type of tooltip at a time
	if hovered_point_index != -1:
		draw_tooltip()
	elif show_crosshair:
		draw_crosshair()


func draw_drag_indicator():
	"""Show current chart position"""
	var font = ThemeDB.fallback_font
	var font_size = 10
	var current_time = Time.get_unix_time_from_system()
	var time_offset = current_time - chart_center_time

	if abs(time_offset) > 300.0:  # More than 5 minutes offset
		var hours_offset = time_offset / 3600.0
		var days_offset = time_offset / 86400.0

		var time_text = ""
		if abs(days_offset) >= 1.0:
			time_text = "%.1f days from now" % days_offset
		else:
			time_text = "%.1f hours from now" % hours_offset

		var text_size = font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var padding = Vector2(8, 4)
		var bg_rect = Rect2(Vector2(5, 5), Vector2(text_size.x + padding.x * 2, text_size.y + padding.y * 2))

		draw_rect(bg_rect, Color(0.2, 0.15, 0.0, 0.9))
		draw_rect(bg_rect, Color(0.5, 0.4, 0.2, 0.8), false, 1.0)
		draw_string(font, Vector2(bg_rect.position.x + padding.x, bg_rect.position.y + padding.y + text_size.y), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.ORANGE)


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
	"""Draw intelligent grid lines that scale with zoom and align with current view"""
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	# Draw horizontal price grid lines (dynamic based on current view)
	draw_price_grid_lines(chart_height, chart_y_offset)

	# Draw intelligent time-based vertical grid lines (dynamic based on current view)
	draw_time_grid_lines()


func draw_price_grid_lines(chart_height: float, chart_y_offset: float):
	"""Draw horizontal grid lines based on current price range"""
	var bounds = get_current_window_bounds()
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	if price_range <= 0:
		return

	# Determine appropriate price grid interval
	var price_interval = calculate_price_grid_interval(price_range)

	# Find the first grid line (round down to nearest interval)
	var first_price = floor(min_price / price_interval) * price_interval

	# Draw grid lines
	var current_price = first_price
	var lines_drawn = 0
	var max_lines = 20  # Prevent too many lines

	while current_price <= max_price and lines_drawn < max_lines:
		if current_price >= min_price:
			var price_progress = (current_price - min_price) / price_range
			var y = chart_y_offset + chart_height - (price_progress * chart_height)

			# Use slightly brighter lines for major price levels
			var is_major = is_major_price_level(current_price, price_interval)
			var line_color = grid_color.lightened(0.2) if is_major else grid_color
			var line_width = 1.5 if is_major else 1.0

			draw_line(Vector2(0, y), Vector2(size.x, y), line_color, line_width)
			lines_drawn += 1

		current_price += price_interval


func calculate_price_grid_interval(price_range: float) -> float:
	"""Calculate appropriate price grid interval based on current range"""
	# Target around 4-8 grid lines for good readability
	var target_lines = 6.0
	var raw_interval = price_range / target_lines

	# Round to nice numbers
	var magnitude = pow(10, floor(log(raw_interval) / log(10)))
	var normalized = raw_interval / magnitude

	var nice_interval = magnitude
	if normalized <= 1.0:
		nice_interval = magnitude
	elif normalized <= 2.0:
		nice_interval = magnitude * 2.0
	elif normalized <= 5.0:
		nice_interval = magnitude * 5.0
	else:
		nice_interval = magnitude * 10.0

	# Ensure minimum interval to prevent too many labels
	var min_interval = price_range / 10.0  # Maximum 10 lines
	nice_interval = max(nice_interval, min_interval)

	return nice_interval


func is_major_price_level(price: float, interval: float) -> bool:
	"""Check if this is a major price level (for emphasized labels)"""
	# Consider every 5th interval as major, or round numbers
	var major_interval = interval * 5.0
	var is_major_multiple = abs(fmod(price, major_interval)) < (interval * 0.01)

	# Also consider "round" numbers as major based on magnitude
	var magnitude = pow(10, floor(log(price) / log(10)))
	var normalized_price = price / magnitude
	var is_round_number = normalized_price == 1.0 or normalized_price == 2.0 or normalized_price == 5.0

	return is_major_multiple or is_round_number


func draw_time_grid_lines():
	"""Draw vertical grid lines aligned with current time view"""
	var bounds = get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var time_window = window_end - window_start
	var window_days = time_window / 86400.0

	# Determine appropriate grid interval based on current zoom level
	var grid_interval_seconds: float

	if window_days <= 2:
		# Very zoomed in (≤2 days): Show 6-hour intervals
		grid_interval_seconds = 21600.0  # 6 hours
	elif window_days <= 7:
		# Zoomed in (≤1 week): Show daily intervals
		grid_interval_seconds = 86400.0  # 24 hours = 1 day
	elif window_days <= 30:
		# Medium zoom (≤1 month): Show every 3 days
		grid_interval_seconds = 259200.0  # 3 days
	elif window_days <= 90:
		# Zoomed out (≤3 months): Show weekly intervals
		grid_interval_seconds = 604800.0  # 7 days = 1 week
	elif window_days <= 365:
		# Far zoom (≤1 year): Show monthly intervals (~30 days)
		grid_interval_seconds = 2592000.0  # 30 days = ~1 month
	else:
		# Maximum zoom (>1 year): Show quarterly intervals
		grid_interval_seconds = 7776000.0  # 90 days = ~1 quarter

	# Find appropriate starting point aligned to Eve downtime
	var eve_anchor = find_aligned_eve_time(window_start, grid_interval_seconds)

	# Draw grid lines
	var current_time = eve_anchor
	var lines_drawn = 0
	var max_lines = 20

	while current_time <= window_end and lines_drawn < max_lines:
		if current_time >= window_start:
			var time_progress = (current_time - window_start) / time_window
			var x = time_progress * size.x

			# Only draw if within chart bounds
			if x >= 0 and x <= size.x:
				# Check if this is a daily boundary (11:00 UTC) for emphasis
				var datetime = Time.get_datetime_dict_from_unix_time(current_time)
				var is_daily_boundary = datetime.hour == 11 and datetime.minute == 0

				var line_color = grid_color.lightened(0.3) if is_daily_boundary else grid_color
				var line_width = 1.5 if is_daily_boundary else 1.0

				draw_line(Vector2(x, 0), Vector2(x, size.y * 0.8), line_color, line_width)
				lines_drawn += 1

		current_time += grid_interval_seconds


func find_aligned_eve_time(start_time: float, interval_seconds: float) -> float:
	"""Find the first grid line aligned to Eve time boundaries"""
	var current_time = Time.get_unix_time_from_system()
	var eve_downtime = find_most_recent_eve_downtime(current_time)

	# Work backwards from Eve downtime to find the first line before start_time
	var aligned_time = eve_downtime
	while aligned_time > start_time:
		aligned_time -= interval_seconds

	# Move forward to first line at or after start_time
	while aligned_time < start_time:
		aligned_time += interval_seconds

	return aligned_time


func find_most_recent_eve_downtime(current_time: float) -> float:
	"""Find the most recent Eve Online downtime (11:00 UTC) before current_time"""
	var current_datetime = Time.get_datetime_dict_from_unix_time(current_time)

	# Start with today at 11:00 UTC
	var today_downtime = Time.get_unix_time_from_datetime_dict({"year": current_datetime.year, "month": current_datetime.month, "day": current_datetime.day, "hour": 11, "minute": 0, "second": 0})

	# If today's downtime hasn't happened yet, use yesterday's
	if today_downtime > current_time:
		today_downtime -= 86400.0  # Go back 24 hours

	return today_downtime


func draw_time_grid_line(timestamp: float, data_start_time: float, data_time_span: float):
	"""Draw a single vertical grid line at the specified timestamp"""
	var time_progress = (timestamp - data_start_time) / data_time_span
	var x = time_progress * size.x

	# Only draw if the line is within the visible chart area
	if x >= 0 and x <= size.x:
		# Use slightly thicker/brighter lines for daily boundaries (11:00 UTC)
		var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
		var is_daily_boundary = datetime.hour == 11 and datetime.minute == 0

		var line_color = grid_color
		var line_width = 1.0

		if is_daily_boundary:
			line_color = grid_color.lightened(0.3)  # Brighter for daily boundaries
			line_width = 1.5

		draw_line(Vector2(x, 0), Vector2(x, size.y * 0.8), line_color, line_width)


# Modify the draw_price_line function (around line 200) to include candlestick drawing
func draw_price_line():
	print("=== DRAWING PRICE LINE (SIMPLE DRAG) ===")
	print("Price data size: %d, Candlestick data size: %d" % [price_data.size(), candlestick_data.size()])
	print("Chart center time: %.0f, price: %.2f, range: %.2f" % [chart_center_time, chart_center_price, chart_price_range])

	if price_data.size() < 1:
		print("No price data to draw")
		return

	var bounds = get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	print("Drawing bounds: time %.0f-%.0f, price %.2f-%.2f" % [window_start, window_end, min_price, max_price])

	# Get visible data
	var visible_points = []
	var visible_candles = []

	for point in price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_points.append(point)

	for candle in candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			visible_candles.append(candle)

	print("Visible points: %d, Visible candles: %d" % [visible_points.size(), visible_candles.size()])

	if visible_points.size() < 1:
		print("No visible points in current window")
		return

	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	print("Chart dimensions: height %.1f, y_offset %.1f" % [chart_height, chart_y_offset])

	# Draw candlesticks first
	if show_candlesticks and visible_candles.size() > 0:
		print("Drawing %d candlesticks" % visible_candles.size())
		draw_candlesticks_simple(visible_candles, window_start, window_end, min_price, price_range, chart_height, chart_y_offset)

	# Draw moving average line
	var points: PackedVector2Array = []
	for i in range(visible_points.size()):
		var point_data = visible_points[i]
		var time_progress = (point_data.timestamp - window_start) / (window_end - window_start)
		var x = time_progress * size.x

		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		points.append(Vector2(x, y))

		if i < 3:  # Debug first few points
			print("Point %d: time %.0f, price %.2f -> x %.1f, y %.1f" % [i, point_data.timestamp, point_data.price, x, y])

	print("Generated %d drawing points" % points.size())

	# Draw lines between points
	for i in range(points.size() - 1):
		var current_point_data = visible_points[i]
		var next_point_data = visible_points[i + 1]
		var time_diff = next_point_data.timestamp - current_point_data.timestamp

		if time_diff <= 86400.0 * 2:  # Within 2 days
			var current_is_historical = current_point_data.get("is_historical", false)
			var next_is_historical = next_point_data.get("is_historical", false)

			var line_color = Color(0.6, 0.8, 1.0, 0.6) if (current_is_historical and next_is_historical) else Color.YELLOW
			var line_width = 1.5 if (current_is_historical and next_is_historical) else 2.0
			draw_line(points[i], points[i + 1], line_color, line_width, true)

			if i < 3:  # Debug first few lines
				print("Drew line %d: from (%.1f,%.1f) to (%.1f,%.1f) color %s" % [i, points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, line_color])

	# Draw data points
	for i in range(points.size()):
		var point_data = visible_points[i]
		var is_historical = point_data.get("is_historical", false)
		var volume = point_data.get("volume", 0)

		var circle_color = Color(0.9, 0.9, 0.4, 0.8) if is_historical else Color.ORANGE
		var circle_radius = 3.0

		if volume > 0:
			draw_circle(points[i], circle_radius + 1.0, Color.WHITE, true)
			draw_circle(points[i], circle_radius, circle_color, true)

		if i < 3:  # Debug first few circles
			print("Drew circle %d at (%.1f,%.1f) color %s" % [i, points[i].x, points[i].y, circle_color])


# Add this new function after draw_price_line
func draw_candlesticks_simple(visible_candles: Array, window_start: float, window_end: float, min_price: float, price_range: float, chart_height: float, chart_y_offset: float):
	"""Draw candlesticks with simple positioning"""
	var scale_factors = get_zoom_scale_factor()
	var scaled_candle_width = candle_width * scale_factors.volume_scale
	var scaled_wick_width = max(2.0, wick_width * scale_factors.volume_scale)

	for i in range(visible_candles.size()):
		var candle = visible_candles[i]

		# Calculate X position
		var time_progress = (candle.timestamp - window_start) / (window_end - window_start)
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

		# Determine colors (same logic as before)
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
			wick_trend_color = Color(0.0, 0.9, 0.0, 1.0)  # Green wicks
		elif day_change < -0.01:
			wick_trend_color = Color(0.9, 0.0, 0.0, 1.0)  # Red wicks
		else:
			wick_trend_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray wicks

		# Draw the candlestick
		var body_top = min(open_y, close_y)
		var body_bottom = max(open_y, close_y)
		var body_height = max(body_bottom - body_top, 3.0)

		# Draw body
		var body_rect = Rect2(x - scaled_candle_width / 2, body_top, scaled_candle_width, body_height)
		draw_rect(body_rect, candle_color, true)

		# Draw wicks
		if high_y < body_top:
			draw_line(Vector2(x, high_y), Vector2(x, body_top), wick_trend_color, scaled_wick_width, false)
		if low_y > body_bottom:
			draw_line(Vector2(x, body_bottom), Vector2(x, low_y), wick_trend_color, scaled_wick_width, false)

		# Draw border
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
	"""Draw price labels aligned with dynamic price grid lines"""
	var bounds = get_current_window_bounds()
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	if price_range <= 0:
		print("Invalid price range for Y-axis labels")
		return

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var font_size = 10

	# Use the same price interval calculation as the grid
	var price_interval = calculate_price_grid_interval(price_range)

	# Find the first label price (round down to nearest interval)
	var first_price = floor(min_price / price_interval) * price_interval

	# Draw labels at the same positions as grid lines
	var current_price = first_price
	var labels_drawn = 0
	var max_labels = 20  # Prevent too many labels

	while current_price <= max_price and labels_drawn < max_labels:
		if current_price >= min_price:
			# Calculate Y position (same logic as grid lines)
			var price_progress = (current_price - min_price) / price_range
			var y_pos = chart_y_offset + chart_height - (price_progress * chart_height)

			# Format price based on magnitude and make it readable
			var price_text = format_price_label_for_axis(current_price)

			# Check if this is a major price level for styling
			var is_major = is_major_price_level(current_price, price_interval)
			var text_color = axis_label_color.lightened(0.2) if is_major else axis_label_color
			var actual_font_size = font_size + (1 if is_major else 0)

			# Draw price label
			var text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_font_size)
			var label_y = y_pos + text_size.y / 2 - 2  # Center vertically on grid line

			draw_string(chart_font, Vector2(4, label_y), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_font_size, text_color)
			labels_drawn += 1

		current_price += price_interval

	print("Drew %d Y-axis labels with interval %.2f" % [labels_drawn, price_interval])


func draw_x_axis_labels():
	"""Draw time labels aligned with Eve Online daily boundaries (simple drag system)"""
	var font_size = 9
	var bounds = get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var time_window = window_end - window_start
	var window_days = time_window / 86400.0

	# Determine label interval based on zoom level
	var label_interval_seconds: float
	var label_format_type: String

	if window_days <= 1:
		label_interval_seconds = 21600.0  # 6 hours
		label_format_type = "time"
	elif window_days <= 7:
		label_interval_seconds = 86400.0  # 1 day
		label_format_type = "daily"
	elif window_days <= 30:
		label_interval_seconds = 259200.0  # 3 days
		label_format_type = "multi_day"
	elif window_days <= 90:
		label_interval_seconds = 604800.0  # 1 week
		label_format_type = "weekly"
	else:
		label_interval_seconds = 2592000.0  # 1 month
		label_format_type = "monthly"

	# Find the most recent Eve downtime as anchor
	var current_time = Time.get_unix_time_from_system()
	var eve_downtime_anchor = find_most_recent_eve_downtime(current_time)

	# Generate labels
	var labels_drawn = 0
	var max_labels = 8
	var chart_bottom = size.y * 0.7

	var label_timestamp = eve_downtime_anchor
	while label_timestamp >= window_start and labels_drawn < max_labels:
		if label_timestamp <= window_end:
			draw_x_axis_label_at_timestamp(label_timestamp, window_start, window_end, chart_bottom, label_format_type, font_size)
			labels_drawn += 1
		label_timestamp -= label_interval_seconds

	label_timestamp = eve_downtime_anchor + label_interval_seconds
	while label_timestamp <= window_end and labels_drawn < max_labels:
		if label_timestamp >= window_start:
			draw_x_axis_label_at_timestamp(label_timestamp, window_start, window_end, chart_bottom, label_format_type, font_size)
			labels_drawn += 1
		label_timestamp += label_interval_seconds


func draw_x_axis_label_at_timestamp(timestamp: float, window_start: float, window_end: float, chart_bottom: float, format_type: String, font_size: int):
	"""Draw a single X-axis label at the specified timestamp"""
	var time_progress = (timestamp - window_start) / (window_end - window_start)
	var x_pos = time_progress * size.x

	if x_pos < 0 or x_pos > size.x:
		return

	var label_text = format_eve_time_label(timestamp, format_type)
	var text_size = chart_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_x = x_pos - text_size.x / 2

	label_x = max(0, min(label_x, size.x - text_size.x))

	draw_string(chart_font, Vector2(label_x, chart_bottom + text_size.y + 4), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func format_price_label_for_axis(price: float) -> String:
	"""Format price labels specifically for Y-axis (more compact than tooltips)"""
	if price >= 1000000000:
		return "%.1fB" % (price / 1000000000.0)
	elif price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	elif price >= 1000:
		return "%.1fK" % (price / 1000.0)
	elif price >= 100:
		return "%.0f" % price
	elif price >= 10:
		return "%.1f" % price
	elif price >= 1:
		return "%.2f" % price
	else:
		return "%.3f" % price


func format_eve_time_label(timestamp: float, format_type: String) -> String:
	"""Format time labels based on type and Eve Online conventions"""
	var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
	var current_time = Time.get_unix_time_from_system()

	match format_type:
		"time":
			# Show time of day (for very zoomed in views)
			if datetime.hour == 11:
				return "DT"  # Eve downtime marker
			if datetime.hour == 0:
				return "00:00"
			if datetime.hour == 6:
				return "06:00"
			if datetime.hour == 12:
				return "12:00"
			if datetime.hour == 18:
				return "18:00"

			return "%02d:00" % datetime.hour

		"daily":
			# Show day format
			var days_ago = (current_time - timestamp) / 86400.0
			if days_ago < 1:
				return "Today"
			if days_ago < 2:
				return "Yesterday"
			else:
				# Show month/day for recent dates
				return "%d/%d" % [datetime.month, datetime.day]

		"multi_day":
			# Show date for multi-day intervals
			return "%d/%d" % [datetime.month, datetime.day]

		"weekly":
			# Show week indicators
			var days_ago = (current_time - timestamp) / 86400.0
			var weeks_ago = int(days_ago / 7.0)
			if weeks_ago == 0:
				return "This Week"
			if weeks_ago == 1:
				return "Last Week"
			else:
				return "-%dw" % weeks_ago

		"monthly":
			# Show month/year
			var month_names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
			return "%s %d" % [month_names[datetime.month], datetime.year]

		_:
			# Fallback
			return "%d/%d" % [datetime.month, datetime.day]


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

	if price_data.size() == 1:  # First data point
		initialize_price_center()

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

	if price_data.size() % 10 == 0:  # Every 10 points, update center
		initialize_price_center()

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
	initialize_price_center()
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


func get_time_at_pixel(x_pixel: float) -> float:
	"""Get the timestamp at a specific pixel position"""
	var time_window = get_current_time_window()
	var progress = x_pixel / size.x
	return chart_center_time - (time_window / 2.0) + (progress * time_window)


func get_price_at_pixel(y_pixel: float) -> float:
	"""Get the price at a specific pixel position"""
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var relative_y = y_pixel - chart_y_offset
	var progress = 1.0 - (relative_y / chart_height)  # Invert Y (top = high price)

	var half_range = chart_price_range / 2.0
	return chart_center_price - half_range + (progress * chart_price_range)


func get_max_historical_time() -> float:
	"""Get the earliest timestamp from available data"""
	var earliest = Time.get_unix_time_from_system()

	for point in price_data:
		if point.timestamp < earliest:
			earliest = point.timestamp

	for candle in candlestick_data:
		if candle.timestamp < earliest:
			earliest = candle.timestamp

	return earliest


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


func reset_to_current():
	"""Reset chart to current time and auto-fit price"""
	chart_center_time = Time.get_unix_time_from_system()
	zoom_level = 1.0
	initialize_price_center()
	queue_redraw()
	print("Reset to current time and auto price range")


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


func get_current_window_bounds() -> Dictionary:
	"""Get the current time and price window bounds"""
	var time_window = get_current_time_window()
	var half_time = time_window / 2.0
	var half_price = chart_price_range / 2.0

	var bounds = {"time_start": chart_center_time - half_time, "time_end": chart_center_time + half_time, "price_min": chart_center_price - half_price, "price_max": chart_center_price + half_price}

	print("Window bounds: time %.0f-%.0f, price %.2f-%.2f" % [bounds.time_start, bounds.time_end, bounds.price_min, bounds.price_max])
	return bounds


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
