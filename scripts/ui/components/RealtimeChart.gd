# scripts/ui/components/RealtimeChart.gd
class_name RealtimeChart
extends Control

signal price_level_clicked(price: float)
signal historical_data_requested

var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var time_labels: Array[String] = []
var max_data_points: int = 200
var timeframe_hours: float = 24.0  # 1 day timeframe
var data_retention_seconds: float = 86400.0  # 24 hours in seconds
var base_time_window: float = 86400.0  # 24 hours in seconds (base window)
var max_data_retention: float = 432000.0  # 5 days in seconds (24 * 5 * 3600)
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

# Price level indicators
var support_levels: Array[float] = []
var resistance_levels: Array[float] = []
var moving_average_period: int = 10  # Number of data points for moving average
var price_history: Array[float] = []  # Store raw prices for moving average calculation

# Mouse interaction
var mouse_position: Vector2 = Vector2.ZERO
var show_crosshair: bool = false
var zoom_level: float = 1.0
var min_zoom: float = 0.041667  # 6 hours (24 * 0.25)
var max_zoom: float = 5.0  # 4 days (24 * 5 = 96 hours)
var zoom_sensitivity: float = 0.5  # How much each scroll step changes zoom

var hovered_point_index: int = -1
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
	hovered_point_index = -1  # Clear hovered point when mouse leaves
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
	"""Check if mouse is hovering over any data point"""
	var old_hovered_index = hovered_point_index
	hovered_point_index = -1
	tooltip_text = ""

	if price_data.size() < 1:
		if old_hovered_index != hovered_point_index:
			queue_redraw()
		return

	var min_price = get_min_price()
	var max_price = get_max_price()
	var price_range = max_price - min_price

	if price_range == 0:
		price_range = max_price * 0.1
		min_price = max_price - price_range / 2
		max_price = max_price + price_range / 2

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var current_time = Time.get_unix_time_from_system()
	var window_start = current_time - 86400.0

	# Check each data point for hover
	for i in range(price_data.size()):
		# Calculate point position
		var time_in_window = price_data[i].timestamp - window_start
		var time_ratio = clamp(time_in_window / 86400.0, 0.0, 1.0)
		var x = time_ratio * size.x

		var normalized_price = (price_data[i].price - min_price) / price_range
		var y = chart_y_offset + chart_height - (normalized_price * chart_height)

		var point_pos = Vector2(x, y)

		# Check if mouse is within hover radius
		if mouse_pos.distance_to(point_pos) <= point_hover_radius:
			hovered_point_index = i
			tooltip_position = mouse_pos

			# Create detailed tooltip text for data points
			var hours_ago = (current_time - price_data[i].timestamp) / 3600.0
			var time_text = ""
			if hours_ago < 0.1:
				time_text = "Now"
			elif hours_ago < 1.0:
				time_text = "%.0f minutes ago" % (hours_ago * 60)
			else:
				time_text = "%.0f hours ago" % hours_ago

			var is_historical = price_data[i].get("is_historical", false)
			var data_type = "Historical" if is_historical else "Real-time"

			tooltip_text = (
				"%s Data\nPrice: %s ISK\nVolume: %s\nTime: %s" % [data_type, format_price_label(price_data[i].price), format_number(volume_data[i] if i < volume_data.size() else 0), time_text]
			)
			break

	# Redraw if hover state changed
	if old_hovered_index != hovered_point_index:
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
	"""Draw tooltip for hovered data point"""
	if hovered_point_index == -1 or tooltip_text.is_empty():
		return

	var font = ThemeDB.fallback_font
	var font_size = 11
	var padding = Vector2(8, 12)
	var line_height = 14

	# Split tooltip text into lines
	var lines = tooltip_text.split("\n")
	var max_width = 0.0

	# Calculate tooltip dimensions
	for line in lines:
		var text_size = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if text_size.x > max_width:
			max_width = text_size.x

	var tooltip_size = Vector2(max_width + padding.x * 2, lines.size() * line_height + padding.y - 8)

	# Position tooltip near cursor, but keep it on screen
	var tooltip_pos = tooltip_position + Vector2(15, -tooltip_size.y / 2)

	# Keep tooltip within screen bounds
	if tooltip_pos.x + tooltip_size.x > size.x:
		tooltip_pos.x = tooltip_position.x - tooltip_size.x - 15
	if tooltip_pos.y < 0:
		tooltip_pos.y = 0
	if tooltip_pos.y + tooltip_size.y > size.y:
		tooltip_pos.y = size.y - tooltip_size.y

	# Draw tooltip background
	var tooltip_rect = Rect2(tooltip_pos, tooltip_size)
	var bg_color = Color(0.1, 0.1, 0.15, 0.95)
	var border_color = Color(0.4, 0.4, 0.5, 1.0)

	draw_rect(tooltip_rect, bg_color)
	draw_rect(tooltip_rect, border_color, false, 1.0)

	# Draw tooltip text
	var text_pos = tooltip_pos + padding
	for i in range(lines.size()):
		var line_pos = text_pos + Vector2(0, i * line_height)
		var text_color = Color.WHITE

		# Color code different parts of the tooltip
		if lines[i].begins_with("Price:"):
			text_color = Color.YELLOW
		elif lines[i].begins_with("Volume:"):
			text_color = Color.LIGHT_BLUE
		elif lines[i].begins_with("Time:"):
			text_color = Color.LIGHT_GREEN

		draw_string(font, line_pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func draw_grid():
	# Adjust grid density based on zoom level
	var grid_divisions_x = max(2, int(12 / zoom_level))  # Fewer divisions when zoomed in
	grid_divisions_x = min(grid_divisions_x, 24)  # Cap at 24 divisions
	var grid_divisions_y = 3  # Keep price grid lines consistent

	# Vertical grid lines (time) - aligned with X-axis labels
	for i in range(grid_divisions_x + 1):
		var x = (float(i) / grid_divisions_x) * size.x
		draw_line(Vector2(x, 0), Vector2(x, size.y * 0.8), grid_color, 1.0)

	# Horizontal grid lines (price) - aligned with Y-axis labels
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	for i in range(grid_divisions_y + 1):
		var y = chart_y_offset + (float(i) / grid_divisions_y) * chart_height
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)


func draw_price_line():
	print("=== DRAWING PRICE LINE WITH HISTORICAL TIME RANGE ===")
	print("Data points: %d, Time window: %.1f hours" % [price_data.size(), get_current_time_window() / 3600.0])

	if price_data.size() < 1:
		print("No price data to draw")
		return

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	# Get visible points and price range using the same method as Y-axis
	var visible_points = []
	for i in range(price_data.size()):
		var timestamp = price_data[i].timestamp
		if timestamp >= window_start and timestamp <= window_end:
			visible_points.append(price_data[i])

	if visible_points.size() < 1:
		print("No data points in current time window")
		return

	# Use the same price range calculation as Y-axis labels
	var price_info = get_visible_price_range()
	var min_price = price_info.min_price
	var max_price = price_info.max_price
	var price_range = price_info.range

	print("Visible points: %d, Price range: %.2f - %.2f" % [visible_points.size(), min_price, max_price])

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var points: PackedVector2Array = []

	# Sort visible points by timestamp
	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Create drawing points using consistent price range
	for i in range(visible_points.size()):
		var point_data = visible_points[i]

		# X position: map timestamp to chart width
		var time_progress = (point_data.timestamp - window_start) / time_window
		var x = time_progress * size.x

		# Y position: map price to chart height using same range as Y-axis
		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_y_offset + chart_height - (price_progress * chart_height)

		points.append(Vector2(x, y))

	print("Generated %d drawing points with consistent price range" % points.size())

	# Draw connecting lines between points
	for i in range(points.size() - 1):
		var point_data = visible_points[i]
		var is_historical = point_data.get("is_historical", false)
		var line_color = Color(0.6, 0.8, 1.0, 0.8) if is_historical else Color.YELLOW
		var line_width = 2.0 if is_historical else 2.5
		draw_line(points[i], points[i + 1], line_color, line_width, true)

	# Draw data point circles
	for i in range(points.size()):
		var point_data = visible_points[i]
		var is_historical = point_data.get("is_historical", false)

		# Find original index for hover detection
		var original_index = -1
		for j in range(price_data.size()):
			if price_data[j].timestamp == point_data.timestamp:
				original_index = j
				break

		var is_hovered = original_index == hovered_point_index

		# Circle properties
		var circle_radius = point_visual_radius
		var circle_color = Color(0.8, 0.9, 1.0, 0.9) if is_historical else Color.YELLOW
		var outline_color = Color.WHITE
		var outline_width = 1.0

		# Highlight hovered point
		if is_hovered:
			circle_radius = point_visual_radius * 1.5
			outline_width = 2.0
			outline_color = Color.CYAN

		# Draw circle with outline
		draw_circle(points[i], circle_radius + outline_width, outline_color, true)
		draw_circle(points[i], circle_radius, circle_color, true)

		# Inner highlight
		if not is_historical or is_hovered:
			var highlight_color = Color.WHITE
			highlight_color.a = 0.4 if is_hovered else 0.2
			draw_circle(points[i], circle_radius * 0.6, highlight_color, true)

	print("=== PRICE LINE DRAWN WITH CONSISTENT SCALING ===")


# Modify draw_volume_bars to maintain consistent bar width
func draw_volume_bars():
	print("=== DRAWING VOLUME BARS WITH HISTORICAL TIME RANGE ===")
	print("Volume data size: %d, Time window: %.1f hours" % [volume_data.size(), get_current_time_window() / 3600.0])

	if volume_data.size() == 0 or price_data.size() == 0:
		print("No volume or price data to draw")
		return

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	# Collect all volume data within the time window
	var visible_volume_data = []
	var visible_timestamps = []
	var visible_historical_flags = []
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

			# Track maximums for scaling
			if volume > all_max:
				all_max = volume
			if is_historical and volume > historical_max:
				historical_max = volume

	if visible_volume_data.size() == 0:
		print("No visible volume data in time window")
		return

	print("Visible volume bars: %d, Historical max: %d, All max: %d" % [visible_volume_data.size(), historical_max, all_max])

	# Use historical max for scaling, fall back to all max if no historical data
	var scaling_max = historical_max if historical_max > 0 else all_max
	var volume_cap = scaling_max * 3  # Cap for real-time spikes

	var volume_height_scale = size.y * 0.3
	var base_bar_width = 8.0
	var bars_drawn = 0

	# Draw all visible volume bars
	for i in range(visible_volume_data.size()):
		var volume = visible_volume_data[i]
		var timestamp = visible_timestamps[i]
		var is_historical = visible_historical_flags[i]

		# Calculate X position based on time within window
		var time_progress = (timestamp - window_start) / time_window
		var x = time_progress * size.x

		# Skip if somehow outside visible area
		if x < -base_bar_width or x > size.x + base_bar_width:
			continue

		# Cap extreme volumes for display consistency
		var display_volume = volume
		if not is_historical and volume > volume_cap:
			display_volume = volume_cap
			print("Capped real-time volume from %d to %d" % [volume, display_volume])

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

		# Add subtle border
		if bar_height > 1:
			draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x, 1)), Color.WHITE * 0.2)

		bars_drawn += 1

	print("Drew %d volume bars across time window" % bars_drawn)
	print("=== VOLUME BARS COMPLETE ===")


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
			draw_line(Vector2(0, y), Vector2(size.x, y), Color.GREEN, 2.0, true)

			# Draw support label
			var font = ThemeDB.fallback_font
			var font_size = 10
			var label_text = "S: %s" % format_price_label(support_level)
			var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var label_x = 10
			var label_y = y - 6

			# Draw label background
			var bg_rect = Rect2(Vector2(label_x - 3, label_y - text_size.y - 2), Vector2(text_size.x + 6, text_size.y + 4))
			draw_rect(bg_rect, Color(0, 0.5, 0, 0.9))
			draw_string(font, Vector2(label_x, label_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Draw exactly ONE resistance level
	if resistance_levels.size() > 0:
		var resistance_level = resistance_levels[0]

		# Only draw if within visible range
		if resistance_level >= min_price and resistance_level <= max_price:
			var price_ratio = (resistance_level - min_price) / price_range
			var y = chart_y_offset + chart_height - (price_ratio * chart_height)

			# Draw resistance line
			draw_line(Vector2(0, y), Vector2(size.x, y), Color.RED, 2.0, true)

			# Draw resistance label
			var font = ThemeDB.fallback_font
			var font_size = 10
			var label_text = "R: %s" % format_price_label(resistance_level)
			var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var label_x = 10
			var label_y = y + text_size.y + 8

			# Draw label background
			var bg_rect = Rect2(Vector2(label_x - 3, label_y - text_size.y - 2), Vector2(text_size.x + 6, text_size.y + 4))
			draw_rect(bg_rect, Color(0.5, 0, 0, 0.9))
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
	"""Draw time labels for current time window"""
	var font_size = 9
	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window

	# Adjust label density based on time window
	var grid_divisions = 6  # Always show 6 time labels
	var chart_bottom = size.y * 0.7

	for i in range(grid_divisions + 1):
		var time_progress = float(i) / grid_divisions
		var target_time = window_start + (time_progress * time_window)
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
		var window_start = current_time - time_window

		# Get visible price range for accurate price calculation
		var visible_prices = []
		for point in price_data:
			if point.timestamp >= window_start:
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

				# Calculate time at mouse X position using current time window
				var time_ratio = mouse_position.x / size.x
				var time_at_mouse = window_start + (time_ratio * time_window)
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

				# Draw tooltip background
				var bg_rect = Rect2(label_pos - padding, tooltip_size)
				draw_rect(bg_rect, Color(0.1, 0.1, 0.15, 0.9))
				draw_rect(bg_rect, Color(0.4, 0.4, 0.5, 0.8), false, 1.0)

				# Draw text
				draw_string(font, label_pos, tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.LIGHT_GRAY)


func draw_zoom_indicator():
	"""Draw time window indicator"""
	var font = ThemeDB.fallback_font
	var font_size = 10
	var time_window = get_current_time_window()
	var window_hours = time_window / 3600.0

	var zoom_text = ""
	if window_hours < 1.0:
		zoom_text = "%.0f minutes" % (window_hours * 60)
	elif window_hours < 24.0:
		zoom_text = "%.1f hours" % window_hours
	elif window_hours < 168.0:  # Less than a week
		zoom_text = "%.1f days" % (window_hours / 24.0)
	else:
		zoom_text = "%.1f weeks" % (window_hours / 168.0)

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
	zoom_level = max(zoom_level - zoom_sensitivity, min_zoom)

	if zoom_level != old_zoom:
		var hours = (base_time_window * zoom_level) / 3600.0
		update_price_levels()  # Recalculate levels for new time window
		on_zoom_changed()
		print("Zoomed in to %.1fx (%.1f hours)" % [zoom_level, hours])


func zoom_out(_zoom_point: Vector2):
	var old_zoom = zoom_level
	zoom_level = min(zoom_level + zoom_sensitivity, max_zoom)

	if zoom_level != old_zoom:
		var hours = (base_time_window * zoom_level) / 3600.0
		update_price_levels()  # Recalculate levels for new time window
		on_zoom_changed()
		print("Zoomed out to %.1fx (%.1f hours)" % [zoom_level, hours])


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
	var window_hours = time_window / 3600.0

	if window_hours <= 6:  # 6 hours or less - show minutes
		if hours_back < 0.1:
			return "Now"
		if hours_back < 1.0:
			return "-%dm" % int(hours_back * 60)

		return "-%dh" % int(hours_back)
	if window_hours <= 48:  # 2 days or less - show hours
		if hours_back < 0.5:
			return "Now"

		return "-%dh" % int(hours_back)

	if hours_back < 12:
		return "-%dh" % int(hours_back)

	var days = hours_back / 24.0
	return "-%.1fd" % days


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
	"""Set the start time to 24 hours ago for full day view"""
	var current_time = Time.get_unix_time_from_system()
	day_start_timestamp = current_time - 86400.0  # Start exactly 24 hours ago
	has_loaded_historical = false

	print("Chart window set to show last 24 hours")
	print("Start time: ", Time.get_datetime_string_from_unix_time(day_start_timestamp))
	print("End time: ", Time.get_datetime_string_from_unix_time(current_time))
	print("Window duration: %.1f hours" % ((current_time - day_start_timestamp) / 3600.0))


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
	var window_start = current_time - 86400.0
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
	var max_age = max_data_retention  # Allow data up to 4 days old
	var oldest_allowed = current_time - max_age

	var hours_ago = (current_time - timestamp) / 3600.0

	print("Adding historical point: %.1fh ago, price=%.2f, volume=%d" % [hours_ago, price, volume])
	print("  Timestamp: %s" % Time.get_datetime_string_from_unix_time(timestamp))
	print("  Oldest allowed: %s" % Time.get_datetime_string_from_unix_time(oldest_allowed))

	# Check if within maximum retention window (4 days)
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
	print("Clearing %d price points, %d volume points" % [price_data.size(), volume_data.size()])

	price_data.clear()
	volume_data.clear()
	time_labels.clear()
	price_history.clear()
	support_levels.clear()
	resistance_levels.clear()

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
	return base_time_window * zoom_level


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
	"""Get min/max prices from data within current time window"""
	if price_data.is_empty():
		return {"min_price": 0.0, "max_price": 0.0, "range": 0.0, "count": 0}

	var current_time = Time.get_unix_time_from_system()
	var time_window = get_current_time_window()
	var window_start = current_time - time_window
	var window_end = current_time

	var visible_prices = []
	for point in price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_prices.append(point.price)

	if visible_prices.size() == 0:
		return {"min_price": 0.0, "max_price": 0.0, "range": 0.0, "count": 0}

	var min_price = visible_prices[0]
	var max_price = visible_prices[0]
	for price in visible_prices:
		if price < min_price:
			min_price = price
		if price > max_price:
			max_price = price

	var price_range = max_price - min_price
	if price_range <= 0:
		price_range = max_price * 0.1 if max_price > 0 else 100.0
		min_price = max_price - price_range / 2
		max_price = max_price + price_range / 2

	return {"min_price": min_price, "max_price": max_price, "range": price_range, "count": visible_prices.size()}


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


func cleanup_old_data():
	"""Remove data points older than 4 days"""
	var current_time = Time.get_unix_time_from_system()
	var cutoff_time = current_time - max_data_retention  # 4 days

	var removed_count = 0

	# Remove data older than 4 days
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
		print("Cleaned up %d data points older than 4 days" % removed_count)

	# Ensure arrays stay in sync
	var min_size = min(price_data.size(), volume_data.size())
	if price_data.size() != volume_data.size():
		print("WARNING: Data arrays out of sync - trimming to %d" % min_size)
		price_data = price_data.slice(0, min_size)
		volume_data = volume_data.slice(0, min_size)
		time_labels = time_labels.slice(0, min_size)


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
