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


func _ready():
	custom_minimum_size = Vector2(400, 200)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	chart_font = ThemeDB.fallback_font

	# Initialize day start time
	set_day_start_time()


func _on_mouse_entered():
	show_crosshair = true


func _on_mouse_exited():
	show_crosshair = false
	queue_redraw()


func _gui_input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position
		if show_crosshair:
			queue_redraw()


func _draw():
	draw_background()
	draw_y_axis_labels()
	draw_x_axis_labels()
	draw_grid()
	draw_price_line()
	draw_volume_bars()
	draw_price_levels()
	if show_crosshair:
		draw_crosshair()


func draw_background():
	draw_rect(Rect2(Vector2.ZERO, size), background_color)


func draw_grid():
	var grid_divisions_x = 4  # 3-hour intervals for 24 hours
	var grid_divisions_y = 3  # Price grid lines

	# Vertical grid lines (time) - aligned with X-axis labels
	for i in range(grid_divisions_x + 1):
		var x = (float(i) / grid_divisions_x) * size.x
		draw_line(Vector2(x, 0), Vector2(x, size.y * 0.8), grid_color, 1.0)

	# Horizontal grid lines (price) - aligned with Y-axis labels
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.06

	for i in range(grid_divisions_y + 1):
		var y = chart_y_offset + (float(i) / grid_divisions_y) * chart_height
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)


func draw_price_line():
	print("=== DRAWING PRICE LINE ===")
	print("Data points: %d" % price_data.size())

	if price_data.size() < 1:
		print("No price data to draw")
		return

	var min_price = get_min_price()
	var max_price = get_max_price()
	var price_range = max_price - min_price

	print("Price range: %.2f - %.2f (range: %.2f)" % [min_price, max_price, price_range])

	if price_range == 0:
		price_range = max_price * 0.1
		min_price = max_price - price_range / 2
		max_price = max_price + price_range / 2
		print("Adjusted price range: %.2f - %.2f" % [min_price, max_price])

	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05
	var current_time = Time.get_unix_time_from_system()
	var window_start = current_time - 86400.0  # 24 hours ago

	var points: PackedVector2Array = []

	for i in range(price_data.size()):
		# X position based on time within 24-hour window
		var time_in_window = price_data[i].timestamp - window_start
		var time_ratio = clamp(time_in_window / 86400.0, 0.0, 1.0)
		var x = time_ratio * size.x

		# Y position based on price
		var normalized_price = (price_data[i].price - min_price) / price_range
		var y = chart_y_offset + chart_height - (normalized_price * chart_height)

		points.append(Vector2(x, y))
		if i < 5:  # Debug first few points
			print("Point %d: time_ratio=%.3f, x=%.1f, price=%.2f, y=%.1f" % [i, time_ratio, x, price_data[i].price, y])

	print("Generated %d drawing points" % points.size())

	# Draw the price line with thicker, more visible lines
	for i in range(points.size() - 1):
		var is_historical = price_data[i].get("is_historical", false)
		var line_color = Color(0.6, 0.8, 1.0, 0.8) if is_historical else Color.YELLOW
		var line_width = 0.5 if is_historical else 0.5
		draw_line(points[i], points[i + 1], line_color, line_width, true)

	# Draw price points - make them very visible
	for i in range(points.size()):
		var is_historical = price_data[i].get("is_historical", false)
		var point_color = Color(0.8, 0.9, 1.0) if is_historical else Color.YELLOW
		var point_size = 0.5 if is_historical else 0.5

		# Draw all points, but thin out historical ones
		if not is_historical or i % 2 == 0:
			draw_circle(points[i], point_size, point_color, true)
			# Add outline for visibility
			draw_arc(points[i], point_size + 1, 0, TAU, 16, Color.WHITE, 1.0, true)

	print("=== PRICE LINE DRAWN ===")


func draw_volume_bars():
	print("=== DRAWING VOLUME BARS DEBUG ===")
	print("Volume data size: %d, Price data size: %d" % [volume_data.size(), price_data.size()])

	if volume_data.size() == 0 or price_data.size() == 0:
		print("No volume or price data to draw")
		return

	# Calculate max volume but cap real-time volumes to prevent huge bars
	var historical_max = 0
	var realtime_volumes = []

	for i in range(min(volume_data.size(), price_data.size())):
		var vol = volume_data[i]
		if price_data[i].get("is_historical", false):
			if vol > historical_max:
				historical_max = vol
		else:
			realtime_volumes.append(vol)

	# Cap real-time volumes to 3x historical max to prevent huge bars
	var volume_cap = historical_max * 3 if historical_max > 0 else 1000000
	var max_volume = historical_max

	print("Historical max: %d, Volume cap: %d" % [historical_max, volume_cap])

	var volume_height_scale = size.y * 0.3  # Reduced from 0.2 to 0.15
	var current_time = Time.get_unix_time_from_system()
	var window_start = current_time - 86400.0

	var bars_drawn = 0
	var historical_count = 0
	var realtime_count = 0

	# Draw all volume bars with capped scaling
	for i in range(min(volume_data.size(), price_data.size())):
		var volume = volume_data[i]
		var timestamp = price_data[i].timestamp
		var is_historical = price_data[i].get("is_historical", false)

		# Calculate position
		var time_in_window = timestamp - window_start
		var time_ratio = clamp(time_in_window / 86400.0, 0.0, 1.0)
		var x = time_ratio * size.x

		# Skip if outside visible area
		if x < 0 or x > size.x:
			continue

		# Cap real-time volumes for display
		var display_volume = volume
		if not is_historical and volume > volume_cap:
			display_volume = volume_cap
			print("Capped real-time volume from %d to %d" % [volume, display_volume])

		# Use historical max + some buffer for scaling
		var scaling_max = max(historical_max, volume_cap)
		var normalized_volume = float(display_volume) / scaling_max
		var bar_height = normalized_volume * volume_height_scale

		# Ensure minimum visibility
		if bar_height < 1.0:
			bar_height = 1.0

		# Ensure maximum height doesn't exceed chart area
		var max_bar_height = size.y * 0.15
		if bar_height > max_bar_height:
			bar_height = max_bar_height

		var y = size.y - bar_height

		# Consistent bar width
		var bar_width = max(2.0, (size.x / volume_data.size()) * 0.8)
		var bar_rect = Rect2(x - bar_width / 2, y, bar_width, bar_height)

		# Color coding
		var bar_color: Color
		if is_historical:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.2, 0.4, 0.8, 0.8) * volume_intensity
			historical_count += 1
		else:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.8, 0.9, 0.2, 0.9) * volume_intensity
			realtime_count += 1

		# Draw the bar
		draw_rect(bar_rect, bar_color)

		# Add border
		if bar_height > 1:
			draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x, 1)), Color.WHITE * 0.2)

		bars_drawn += 1

		# Debug key bars
		if bars_drawn <= 3 or bars_drawn > volume_data.size() - 3 or not is_historical:
			var hours_ago = (current_time - timestamp) / 3600.0
			print("Volume bar %d: x=%.1f, vol=%d->%d, height=%.1f, historical=%s, %.1fh ago" % [bars_drawn, x, volume, display_volume, bar_height, is_historical, hours_ago])

	print("Drew %d volume bars (%d historical, %d realtime)" % [bars_drawn, historical_count, realtime_count])
	print("=== VOLUME BARS COMPLETE ===")


func draw_price_levels():
	"""Draw support and resistance levels"""
	if price_data.is_empty():
		return

	var min_price = get_min_price()
	var max_price = get_max_price()
	var price_range = max_price - min_price

	if price_range <= 0:
		return

	# Draw support levels
	for level in support_levels:
		var y = size.y * 0.7 - ((level - min_price) / price_range) * size.y * 0.6
		draw_line(Vector2(0, y), Vector2(size.x, y), Color.GREEN, 0.5, true)

		# Add label
		var font = ThemeDB.fallback_font
		var font_size = 10
		draw_string(font, Vector2(5, y - 5), "Support: %.2f" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)

	# Draw resistance levels
	for level in resistance_levels:
		var y = size.y * 0.7 - ((level - min_price) / price_range) * size.y * 0.6
		draw_line(Vector2(0, y), Vector2(size.x, y), Color.RED, 0.5, true)

		# Add label
		var font = ThemeDB.fallback_font
		var font_size = 10
		draw_string(font, Vector2(5, y + 15), "Resistance: %.2f" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.RED)


func draw_y_axis_labels():
	"""Draw price labels aligned with grid lines"""
	if price_data.is_empty():
		return

	var min_price = get_min_price()
	var max_price = get_max_price()
	var price_range = max_price - min_price

	if price_range <= 0:
		return

	var font_size = 10
	var grid_divisions = 3  # Match grid line count
	var chart_height = size.y * 0.6
	var chart_y_offset = size.y * 0.05

	for i in range(grid_divisions + 1):
		var ratio = float(i) / grid_divisions
		var price_value = min_price + (price_range * (1.0 - ratio))  # Flip for top-to-bottom
		var y_pos = chart_y_offset + (ratio * chart_height)

		# Format price based on magnitude
		var price_text = format_price_label(price_value)

		# Draw price label aligned with grid line
		var text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(chart_font, Vector2(4, y_pos + text_size.y / 2 - 2), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func draw_x_axis_labels():
	"""Draw time labels for 24-hour rolling window"""
	var font_size = 9
	var grid_divisions = 8  # 3-hour intervals
	var chart_bottom = size.y * 0.7
	var current_time = Time.get_unix_time_from_system()

	for i in range(grid_divisions + 1):
		var hours_back = 24.0 - (float(i) / grid_divisions) * 24.0  # 24 hours ago to now
		var target_time = current_time - (hours_back * 3600.0)
		var x_pos = (float(i) / grid_divisions) * size.x

		var time_text = format_rolling_time_label(hours_back)
		var text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		# Center the label horizontally
		var label_x = x_pos - text_size.x / 2

		# Draw time label
		draw_string(chart_font, Vector2(label_x, chart_bottom + text_size.y + 4), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func draw_crosshair():
	"""Draw crosshair and price/time info at mouse position"""
	if not show_crosshair:
		return

	# Draw crosshair lines
	draw_line(Vector2(0, mouse_position.y), Vector2(size.x, mouse_position.y), Color.DIM_GRAY, 1.0, false)
	draw_line(Vector2(mouse_position.x, 0), Vector2(mouse_position.x, size.y), Color.DIM_GRAY, 1.0, false)

	# Calculate price at mouse position
	if price_data.size() > 0:
		var min_price = get_min_price()
		var max_price = get_max_price()
		var price_range = max_price - min_price

		if price_range > 0:
			var price_y_ratio = (size.y * 0.7 - mouse_position.y) / (size.y * 0.6)
			var price_at_mouse = min_price + (price_y_ratio * price_range)

			# Draw price label
			var font = ThemeDB.fallback_font
			var font_size = 12
			var price_text = "%.2f ISK" % price_at_mouse
			var text_size = font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var label_pos = Vector2(mouse_position.x + 10, mouse_position.y - 10)
			if label_pos.x + text_size.x > size.x:
				label_pos.x = mouse_position.x - text_size.x - 10

			draw_string(font, label_pos, price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.LIGHT_GRAY)


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

	# Keep rolling 24-hour window
	cleanup_old_data()

	# Update support/resistance levels
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
	var window_start = current_time - 86400.0
	var hours_ago = (current_time - timestamp) / 3600.0

	print("Adding historical point: %.1fh ago, price=%.2f, volume=%d" % [hours_ago, price, volume])
	print("  Timestamp: %s" % Time.get_datetime_string_from_unix_time(timestamp))
	print("  Window start: %s" % Time.get_datetime_string_from_unix_time(window_start))
	print("  Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))

	# Check if within 24-hour window
	if timestamp < window_start:
		print("  REJECTED: Too old (%.1f hours ago)" % hours_ago)
		return

	if timestamp > current_time:
		print("  REJECTED: In the future")
		return

	var seconds_from_start = timestamp - window_start

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
	"""Calculate support and resistance levels"""
	if price_data.size() < 10:
		return

	var recent_prices = []
	var recent_count = min(20, price_data.size())

	for i in range(price_data.size() - recent_count, price_data.size()):
		if i >= 0:
			recent_prices.append(price_data[i].price)

	recent_prices.sort()

	# Simple support/resistance calculation
	support_levels.clear()
	resistance_levels.clear()

	if recent_prices.size() >= 4:
		support_levels.append(recent_prices[recent_prices.size() / 4])
		resistance_levels.append(recent_prices[recent_prices.size() * 3 / 4])


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
		return "%.1fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.1fK" % (price / 1000.0)
	if price >= 1:
		return "%.2f" % price

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


func cleanup_old_data():
	"""Remove data points older than 24 hours"""
	var current_time = Time.get_unix_time_from_system()
	var cutoff_time = current_time - 86400.0  # Exactly 24 hours ago

	var removed_count = 0

	# Remove old data points from the beginning - keep price/volume/time in sync
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
		print("Cleaned up %d old data points" % removed_count)

	# Ensure arrays stay in sync
	var min_size = min(price_data.size(), volume_data.size())
	if price_data.size() != volume_data.size():
		print("WARNING: Data arrays out of sync - price:%d, volume:%d" % [price_data.size(), volume_data.size()])
		# Trim to match
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
