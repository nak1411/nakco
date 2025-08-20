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
	# EXACT original draw order
	_draw_background()
	_draw_axis_label_tracks()
	_draw_y_axis_labels()
	_draw_x_axis_labels()
	_draw_grid()
	_draw_price_line()
	_draw_volume_bars()

	# Only draw S/R lines if enabled
	if parent_chart.show_support_resistance:
		analysis_tools.draw_support_resistance_lines()

	# Draw spread analysis if enabled
	if parent_chart.show_spread_analysis:
		analysis_tools.draw_spread_analysis()

	_draw_zoom_indicator()
	_draw_drag_indicator()

	# Only draw one type of tooltip at a time - prioritize data point tooltips
	if parent_chart.chart_interaction.hovered_point_index != -1 or parent_chart.chart_interaction.hovered_volume_index != -1:
		_draw_tooltip()  # Data point tooltip
	elif parent_chart.chart_interaction.show_crosshair:
		_draw_crosshair()


func _draw_background():
	"""Draw chart background (EXACT original)"""
	parent_chart.draw_rect(Rect2(Vector2.ZERO, parent_chart.size), background_color)


func _draw_grid():
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_top = chart_bounds.top
	var chart_bottom = chart_bounds.bottom
	var chart_height = chart_bounds.height

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var time_window = window_end - window_start
	var window_days = time_window / 86400.0

	print("Drawing grid: window_days=%.2f" % window_days)

	# Vertical grid lines (time) - EXACT same logic as X-axis labels
	var grid_interval_seconds: float
	if window_days <= 1:
		grid_interval_seconds = 21600.0  # 6 hours (matches labels)
	elif window_days <= 7:
		grid_interval_seconds = 86400.0  # 1 day (matches labels)
	elif window_days <= 30:
		grid_interval_seconds = 259200.0  # 3 days (matches labels)
	elif window_days <= 90:
		grid_interval_seconds = 604800.0  # 1 week (matches labels)
	else:
		grid_interval_seconds = 2592000.0  # 1 month (matches labels)

	print("Grid interval: %.0f seconds" % grid_interval_seconds)

	# Use Eve downtime anchor for grid alignment (EXACT same as labels)
	var current_time = Time.get_unix_time_from_system()
	var eve_downtime_anchor = _find_most_recent_eve_downtime(current_time)

	# Draw grid lines going backwards from anchor
	var grid_time = eve_downtime_anchor
	var grid_lines_drawn = 0
	while grid_time >= window_start and grid_lines_drawn < 20:
		if grid_time <= window_end:
			var time_progress = (grid_time - window_start) / (window_end - window_start)
			var x = chart_bounds.left + (time_progress * chart_bounds.width)

			if x >= chart_bounds.left and x <= chart_bounds.right:
				parent_chart.draw_line(Vector2(x, chart_top), Vector2(x, chart_bottom), grid_color, 1.0, false)
				grid_lines_drawn += 1
		grid_time -= grid_interval_seconds

	# Draw grid lines going forwards from anchor
	grid_time = eve_downtime_anchor + grid_interval_seconds
	while grid_time <= window_end and grid_lines_drawn < 20:
		if grid_time >= window_start:
			var time_progress = (grid_time - window_start) / (window_end - window_start)
			var x = chart_bounds.left + (time_progress * chart_bounds.width)

			if x >= chart_bounds.left and x <= chart_bounds.right:
				parent_chart.draw_line(Vector2(x, chart_top), Vector2(x, chart_bottom), grid_color, 1.0, false)
				grid_lines_drawn += 1
		grid_time += grid_interval_seconds

	print("Drew %d vertical grid lines" % grid_lines_drawn)

	# Horizontal grid lines (price) - use the EXACT same calculation as Y-axis labels
	var min_price = parent_chart.chart_center_price - (parent_chart.chart_price_range / 2.0)
	var max_price = parent_chart.chart_center_price + (parent_chart.chart_price_range / 2.0)
	var price_range = max_price - min_price

	if price_range > 0:
		# Use the same price interval calculation as Y-axis labels
		var price_interval = _calculate_price_grid_interval(price_range)
		var first_price = floor(min_price / price_interval) * price_interval

		var current_price = first_price
		var price_lines_drawn = 0
		while current_price <= max_price and price_lines_drawn < 20:
			if current_price >= min_price:
				var price_progress = (current_price - min_price) / price_range
				var y = chart_top + chart_height - (price_progress * chart_height)

				if y >= chart_top and y <= chart_bottom:
					parent_chart.draw_line(Vector2(chart_bounds.left, y), Vector2(chart_bounds.right, y), grid_color, 1.0, false)
					price_lines_drawn += 1

			current_price += price_interval

		print("Drew %d horizontal grid lines" % price_lines_drawn)


func _draw_axis_label_tracks():
	"""Draw background tracks for axis labels to make them more visible (EXACT original)"""
	var track_color = Color(0.08, 0.1, 0.12, 1.0)  # Semi-transparent dark background
	var border_color = Color(0.2, 0.25, 0.3, 1.0)  # Subtle border

	# Y-axis track (left side for price labels)
	var y_track_width = 50  # Width of the price label track
	var x_track_height = 25  # Height of the time label track
	var chart_bottom = parent_chart.size.y * 0.7

	var y_track_rect = Rect2(Vector2(0, 0), Vector2(y_track_width, chart_bottom))
	parent_chart.draw_rect(y_track_rect, track_color)
	parent_chart.draw_line(Vector2(y_track_width, 0), Vector2(y_track_width, chart_bottom), border_color, 1.0)

	# X-axis track (bottom for time labels)
	var x_track_rect = Rect2(Vector2(0, chart_bottom), Vector2(parent_chart.size.x, x_track_height))
	parent_chart.draw_rect(x_track_rect, track_color)
	parent_chart.draw_line(Vector2(0, chart_bottom), Vector2(parent_chart.size.x, chart_bottom), border_color, 1.0)


func _draw_y_axis_labels():
	"""Draw price labels aligned with dynamic price grid lines using proper boundaries"""
	var bounds = chart_math.get_current_window_bounds()
	var min_price = bounds.price_min
	var max_price = bounds.price_max
	var price_range = max_price - min_price

	if price_range <= 0:
		return

	# FIXED: Use actual chart boundaries instead of hardcoded percentages
	var chart_bounds = chart_math.get_chart_boundaries()
	var font_size = 10

	print("Drawing Y-axis labels: min=%.2f, max=%.2f, range=%.2f" % [min_price, max_price, price_range])

	# Use the same price interval calculation as the grid
	var price_interval = _calculate_price_grid_interval(price_range)

	# Find the first label price (round down to nearest interval)
	var first_price = floor(min_price / price_interval) * price_interval

	# Draw labels at the same positions as grid lines
	var current_price = first_price
	var labels_drawn = 0
	var max_labels = 20

	while current_price <= max_price and labels_drawn < max_labels:
		if current_price >= min_price:
			# FIXED: Calculate Y position using same system as crosshair and grid
			var price_progress = (current_price - min_price) / price_range
			var y_pos = chart_bounds.top + chart_bounds.height - (price_progress * chart_bounds.height)

			# Format price based on magnitude and make it readable
			var price_text = _format_price_label_for_axis(current_price)

			# Check if this is a major price level for styling
			var is_major = _is_major_price_level(current_price, price_interval)
			var text_color = axis_label_color.lightened(0.1) if is_major else axis_label_color

			# FIXED: Draw price label with consistent vertical alignment
			parent_chart.draw_string(chart_font, Vector2(5, y_pos + 4), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

			labels_drawn += 1

		current_price += price_interval


func _draw_x_axis_labels():
	"""Draw time labels aligned with Eve Online daily boundaries (EXACT original)"""
	var font_size = 9
	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var time_window = window_end - window_start
	var window_days = time_window / 86400.0

	print("Drawing X-axis labels: window_days=%.2f, window_start=%.0f, window_end=%.0f" % [window_days, window_start, window_end])

	# Determine label interval based on zoom level (EXACT original)
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

	print("Label interval: %.0f seconds, format: %s" % [label_interval_seconds, label_format_type])

	# Find the most recent Eve downtime as anchor (EXACT original)
	var current_time = Time.get_unix_time_from_system()
	var eve_downtime_anchor = _find_most_recent_eve_downtime(current_time)

	print("Eve downtime anchor: %.0f (%s)" % [eve_downtime_anchor, Time.get_datetime_string_from_unix_time(eve_downtime_anchor)])

	# Generate labels (EXACT original)
	var labels_drawn = 0
	var max_labels = 8
	var chart_bottom = parent_chart.size.y * 0.7

	# Draw labels going backwards from anchor
	var label_timestamp = eve_downtime_anchor
	while label_timestamp >= window_start and labels_drawn < max_labels:
		if label_timestamp <= window_end:
			_draw_x_axis_label_at_timestamp(label_timestamp, window_start, window_end, chart_bottom, label_format_type, font_size)
			labels_drawn += 1
		label_timestamp -= label_interval_seconds

	# Draw labels going forwards from anchor
	label_timestamp = eve_downtime_anchor + label_interval_seconds
	while label_timestamp <= window_end and labels_drawn < max_labels:
		if label_timestamp >= window_start:
			_draw_x_axis_label_at_timestamp(label_timestamp, window_start, window_end, chart_bottom, label_format_type, font_size)
			labels_drawn += 1
		label_timestamp += label_interval_seconds

	print("Drew %d X-axis labels" % labels_drawn)


func _draw_x_axis_label_at_timestamp(timestamp: float, window_start: float, window_end: float, chart_bottom: float, format_type: String, font_size: int):
	"""Draw a single X-axis label at the specified timestamp (EXACT original)"""
	var time_progress = (timestamp - window_start) / (window_end - window_start)
	var chart_bounds = chart_math.get_chart_boundaries()
	var x_pos = chart_bounds.left + (time_progress * chart_bounds.width)

	if x_pos < chart_bounds.left or x_pos > chart_bounds.right:
		return

	var time_text = _format_eve_time_label(timestamp, format_type)
	var text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	# Position text centered on the timestamp
	var text_x = x_pos - text_size.x / 2
	var text_y = chart_bottom + 15

	# Draw the label
	parent_chart.draw_string(chart_font, Vector2(text_x, text_y), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, axis_label_color)


func _draw_price_line():
	print("=== DRAWING PRICE LINE (FIXING CLOSE ZOOM CLIPPING) ===")

	if chart_data.price_data.size() < 1:
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end
	var min_price = parent_chart.chart_center_price - (parent_chart.chart_price_range / 2.0)
	var max_price = parent_chart.chart_center_price + (parent_chart.chart_price_range / 2.0)
	var price_range = max_price - min_price

	# CRITICAL FIX: Use much larger buffer for close zoom levels
	var time_window = window_end - window_start
	var zoom_level = parent_chart.zoom_level

	# Scale buffer based on zoom level - more zoomed in = larger buffer needed
	var buffer_multiplier = max(0.5, zoom_level / 10.0)  # Minimum 50%, scales up with zoom
	var buffer_time = time_window * buffer_multiplier

	print("Zoom level: %.1fx, buffer_time: %.0f sec (%.1f%% of window)" % [zoom_level, buffer_time, buffer_multiplier * 100])

	# Get visible data with enhanced buffer
	var visible_points = []
	var visible_candles = []

	for point in chart_data.price_data:
		if point.timestamp >= (window_start - buffer_time) and point.timestamp <= (window_end + buffer_time):
			visible_points.append(point)

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= (window_start - buffer_time) and candle.timestamp <= (window_end + buffer_time):
			visible_candles.append(candle)

	print("Found %d visible points, %d candles (with %.0fs buffer)" % [visible_points.size(), visible_candles.size(), buffer_time])

	if visible_points.size() < 1:
		return

	visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Use EXACT original chart dimensions for clipping
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_height = chart_bounds.height
	var chart_y_offset = chart_bounds.top
	var chart_top = chart_bounds.top
	var chart_bottom = chart_bounds.bottom

	# Draw candlesticks first (if enabled)
	if parent_chart.show_candlesticks and visible_candles.size() > 0:
		_draw_candlesticks(visible_candles, window_start, window_end, min_price, price_range, chart_height, chart_y_offset)

	# Draw moving average line with IMPROVED clipping for close zoom
	var points: PackedVector2Array = []
	for i in range(visible_points.size()):
		var point_data = visible_points[i]
		var time_progress = (point_data.timestamp - window_start) / (window_end - window_start)
		var chart_width = chart_bounds.right - chart_bounds.left
		var x = chart_bounds.left + (time_progress * chart_width)

		var price_progress = (point_data.price - min_price) / price_range
		var y = chart_top + chart_height - (price_progress * chart_height)

		points.append(Vector2(x, y))

	print("Generated %d points for MA line" % points.size())

	# CRITICAL FIX: Draw lines with improved clipping that handles close zoom better
	for i in range(points.size() - 1):
		var current_point_data = visible_points[i]
		var next_point_data = visible_points[i + 1]
		var time_diff = next_point_data.timestamp - current_point_data.timestamp

		# IMPROVED: Scale max time gap with zoom level
		var max_time_gap = 86400.0 * 2  # Base: 2 days
		if zoom_level > 10:  # When zoomed in close
			max_time_gap = 86400.0 * 30  # Allow much larger gaps (30 days)

		if time_diff <= max_time_gap:
			var p1 = points[i]
			var p2 = points[i + 1]

			# IMPROVED: Use expanded clipping rectangle for better edge handling
			var expanded_clip_rect = Rect2(Vector2(chart_bounds.left, chart_top), Vector2(chart_bounds.width, chart_height))

			# First check if line is completely outside expanded area (skip it)
			if _is_point_in_rect(p1, expanded_clip_rect) or _is_point_in_rect(p2, expanded_clip_rect) or _line_intersects_rect(p1, p2, expanded_clip_rect):
				# Use normal clipping rectangle for actual drawing
				var clip_rect = Rect2(Vector2(chart_bounds.left, chart_top), Vector2(chart_bounds.width, chart_height))

				var clipped_line = chart_math.clip_line_to_rect(p1, p2, clip_rect)

				if clipped_line.has("start") and clipped_line.has("end"):
					var current_is_historical = current_point_data.get("is_historical", false)
					var next_is_historical = next_point_data.get("is_historical", false)

					var line_color = Color(0.6, 0.8, 1.0, 0.6) if (current_is_historical and next_is_historical) else Color.YELLOW
					var line_width = 1.5 if (current_is_historical and next_is_historical) else 2.0

					parent_chart.draw_line(clipped_line.start, clipped_line.end, line_color, line_width, true)
				else:
					# FALLBACK: If clipping fails but line should be visible, draw it anyway
					if _is_point_in_rect(p1, clip_rect) or _is_point_in_rect(p2, clip_rect):
						var current_is_historical = current_point_data.get("is_historical", false)
						var next_is_historical = next_point_data.get("is_historical", false)

						var line_color = Color(0.6, 0.8, 1.0, 0.6) if (current_is_historical and next_is_historical) else Color.YELLOW
						var line_width = 1.5 if (current_is_historical and next_is_historical) else 2.0

						parent_chart.draw_line(p1, p2, line_color, line_width, true)
						print("Drew fallback line %d (clipping failed but points visible)" % i)

	# Draw data points with proper clipping
	for i in range(points.size()):
		var point_data = visible_points[i]
		var point = points[i]

		# Only draw points within the chart bounds
		if point.y >= chart_top and point.y <= chart_bottom and point.x >= chart_bounds.left and point.x <= chart_bounds.right:
			var is_historical = point_data.get("is_historical", false)
			var volume = point_data.get("volume", 0)

			var circle_color = Color(0.9, 0.9, 0.4, 0.8) if is_historical else Color.ORANGE
			var circle_radius = 4.0

			if volume > 0:
				parent_chart.draw_circle(point, circle_radius + 1.0, Color.WHITE, true)
				parent_chart.draw_circle(point, circle_radius, circle_color, true)

	print("MA line drawing complete with improved close-zoom clipping")


# Add helper functions for improved clipping
func _is_point_in_rect(point: Vector2, rect: Rect2) -> bool:
	"""Check if a point is inside a rectangle"""
	return point.x >= rect.position.x and point.x <= rect.position.x + rect.size.x and point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y


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

	# If line bounding box doesn't overlap rect, no intersection
	if line_max_x < rect_min_x or line_min_x > rect_max_x or line_max_y < rect_min_y or line_min_y > rect_max_y:
		return false

	# If either point is inside rect, there's intersection
	if _is_point_in_rect(p1, rect) or _is_point_in_rect(p2, rect):
		return true

	# Line passes through rect
	return true


func _draw_volume_bars():
	if chart_data.volume_data.size() == 0 or chart_data.price_data.size() == 0:
		return

	var bounds = chart_math.get_current_window_bounds()
	var window_start = bounds.time_start
	var window_end = bounds.time_end

	# Get improved zoom-based scaling
	var scale_factors = chart_math.get_zoom_scale_factor()
	var volume_scale = scale_factors.volume_scale
	var space_per_point = scale_factors.get("space_per_point", 30.0)

	# Get chart boundaries
	var chart_bounds = chart_math.get_chart_boundaries()
	var chart_bottom = chart_bounds.bottom

	# Volume area calculation
	var x_track_height = 25
	var volume_area_height = parent_chart.size.y - chart_bottom
	var volume_base_y = chart_bottom

	if volume_area_height < 20:
		volume_area_height = 20
		volume_base_y = parent_chart.size.y - x_track_height - volume_area_height

	# Collect visible volume data
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

			if volume > all_max:
				all_max = volume
			if is_historical and volume > historical_max:
				historical_max = volume

	if visible_volume_data.size() == 0:
		return

	# FIXED: Calculate bar width based on available space and number of bars
	var chart_width = chart_bounds.right - chart_bounds.left
	var visible_historical_count = 0
	for flag in visible_historical_flags:
		if flag:
			visible_historical_count += 1

	# Calculate maximum bar width to prevent overlap
	var max_bar_width = chart_width / visible_historical_count if visible_historical_count > 0 else 30.0
	max_bar_width = max_bar_width * 0.8  # Use 80% of available space for gaps

	# Set reasonable limits
	var base_bar_width = clamp(max_bar_width, 1.0, 25.0)

	# Fine-tune based on zoom level
	if space_per_point > 100.0:
		base_bar_width = min(base_bar_width, 20.0)
	elif space_per_point > 50.0:
		base_bar_width = min(base_bar_width, 15.0)
	elif space_per_point > 25.0:
		base_bar_width = min(base_bar_width, 10.0)
	elif space_per_point > 10.0:
		base_bar_width = min(base_bar_width, 6.0)
	else:
		base_bar_width = min(base_bar_width, 3.0)

	# Calculate precise sampling rate to prevent overlap
	var sampling_rate = 1
	var required_space_per_bar = base_bar_width + 1.0  # Bar width + minimum 1px gap

	if space_per_point < required_space_per_bar:
		sampling_rate = max(1, int(ceil(required_space_per_bar / space_per_point)))

	# Special handling for the problematic 4-week to 1-week zoom range
	var time_window_days = (window_end - window_start) / 86400.0
	if time_window_days > 7.0 and time_window_days < 28.0:
		# Force more aggressive sampling in this range
		var overlap_factor = required_space_per_bar / space_per_point
		if overlap_factor > 0.8:  # If we're close to overlapping
			sampling_rate = max(sampling_rate, int(ceil(overlap_factor * 1.2)))
		print("PROBLEM RANGE - Days: %.1f, overlap_factor: %.2f, sampling_rate: %d" % [time_window_days, overlap_factor, sampling_rate])

	# Use historical max for scaling
	var scaling_max = historical_max if historical_max > 0 else all_max
	var volume_percentile_95 = _calculate_volume_percentile(visible_volume_data, 95.0)
	var volume_cap = volume_percentile_95 * 1.5

	var volume_height_scale = volume_area_height * 0.8
	var volume_bar_positions = []

	print("Volume bar drawing: space=%.1f, bar_width=%.1f, required_space=%.1f, sampling_rate=%d" % [space_per_point, base_bar_width, required_space_per_bar, sampling_rate])

	# Track last drawn bar position to enforce gaps
	var last_bar_x = -999999.0

	# Draw volume bars with strict overlap prevention
	for i in range(visible_volume_data.size()):
		var volume = visible_volume_data[i]
		var timestamp = visible_timestamps[i]
		var is_historical = visible_historical_flags[i]
		var original_index = visible_indices[i]

		if not is_historical:
			continue

		# Apply sampling to prevent overlap
		if i % sampling_rate != 0:
			continue

		# Calculate X position
		var time_progress = (timestamp - window_start) / (window_end - window_start)
		var x = chart_bounds.left + (time_progress * chart_width)

		# Skip if outside visible area
		if x < chart_bounds.left - base_bar_width or x > chart_bounds.right + base_bar_width:
			continue

		# Additional overlap check - ensure minimum distance from last bar
		var bar_left = x - base_bar_width / 2
		var bar_right = x + base_bar_width / 2

		if bar_left <= last_bar_x + 1.0:  # 1px minimum gap
			continue  # Skip this bar to prevent overlap

		# Cap extreme volumes
		var display_volume = min(volume, volume_cap)

		# Scale volume to bar height
		var normalized_volume = float(display_volume) / scaling_max if scaling_max > 0 else 0.0
		var bar_height = normalized_volume * volume_height_scale

		# Ensure minimum visibility when zoomed in
		if space_per_point > 20.0 and bar_height < 3.0:
			bar_height = 3.0
		elif bar_height < 1.0:
			bar_height = 1.0

		# Cap maximum height
		if bar_height > volume_area_height:
			bar_height = volume_area_height

		# Position bar
		var y = volume_base_y + (volume_area_height - bar_height)
		y = clamp(y, volume_base_y, volume_base_y + volume_area_height - bar_height)

		var bar_rect = Rect2(bar_left, y, base_bar_width, bar_height)

		# Update last bar position
		last_bar_x = bar_right

		# Store for hover detection
		volume_bar_positions.append({"rect": bar_rect, "original_index": original_index, "volume": volume, "timestamp": timestamp})

		# Color coding
		var bar_color: Color
		if is_historical:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.2, 0.4, 0.8, 0.8) * volume_intensity
		else:
			var volume_intensity = clamp(normalized_volume + 0.4, 0.5, 1.0)
			bar_color = Color(0.8, 0.9, 0.2, 0.9) * volume_intensity

		# Draw the volume bar
		parent_chart.draw_rect(bar_rect, bar_color)

		# Add highlight when hovered
		if parent_chart.chart_interaction.hovered_volume_index == original_index:
			var highlight_color = Color(1.0, 1.0, 1.0, 0.3)
			parent_chart.draw_rect(bar_rect, highlight_color)

			var border_color = Color.CYAN
			var border_width = max(1.0, 2.0 * volume_scale)
			parent_chart.draw_rect(bar_rect, border_color, false, border_width)

		# Add subtle border for visibility when bars are very thin
		elif base_bar_width < 3.0 and bar_height > 2:
			var border_height = max(1.0, 1.0 * volume_scale)
			parent_chart.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x, border_height)), Color.WHITE * 0.2)

	# Store positions for hover detection
	parent_chart.chart_interaction.current_volume_bar_positions = volume_bar_positions

	print("Drew %d volume bars (from %d visible) with width %.1f, sampling %d" % [volume_bar_positions.size(), visible_volume_data.size(), base_bar_width, sampling_rate])


func _draw_crosshair():
	"""Draw crosshair with price and time labels using proper chart boundaries"""
	if not parent_chart.chart_interaction.show_crosshair:
		return

	var chart_bounds = chart_math.get_chart_boundaries()
	var mouse_pos = parent_chart.chart_interaction.mouse_position

	if mouse_pos.x < chart_bounds.left or mouse_pos.x > chart_bounds.right or mouse_pos.y < chart_bounds.top or mouse_pos.y > chart_bounds.bottom:
		return

	# Draw crosshair lines using proper chart boundaries
	parent_chart.draw_line(Vector2(chart_bounds.left, mouse_pos.y), Vector2(chart_bounds.right, mouse_pos.y), Color.DIM_GRAY, 1.0, false)
	parent_chart.draw_line(Vector2(mouse_pos.x, chart_bounds.top), Vector2(mouse_pos.x, chart_bounds.bottom), Color.DIM_GRAY, 1.0, false)

	# Use the SAME coordinate system as axis labels
	if chart_data.price_data.size() > 0:
		var bounds = chart_math.get_current_window_bounds()
		var price_range = bounds.price_max - bounds.price_min
		var time_span = bounds.time_end - bounds.time_start

		if price_range > 0 and time_span > 0:
			var time_at_mouse = chart_math.get_time_at_pixel(mouse_pos.x)
			var price_at_mouse = chart_math.get_price_at_pixel(mouse_pos.y)

			# Determine time format type based on current zoom level
			var time_window = chart_math.get_current_time_window()
			var window_days = time_window / 86400.0
			var time_format_type: String
			if window_days <= 1:
				time_format_type = "time"
			elif window_days <= 7:
				time_format_type = "daily"
			else:
				time_format_type = "monthly"

			var price_text = _format_price_label_for_axis(price_at_mouse)
			var time_text = _format_eve_time_label(time_at_mouse, time_format_type)

			# FIXED: Draw price text with same +4 offset as Y-axis labels
			var font_size = 11
			var price_text_size = chart_font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var padding = Vector2(4, 2)

			# Position with same +4 vertical offset as Y-axis labels
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

			# Draw time text using proper chart boundaries
			var time_text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var time_x = mouse_pos.x - time_text_size.x / 2
			time_x = max(0, min(time_x, parent_chart.size.x - time_text_size.x))

			var time_bg_rect = Rect2(Vector2(time_x - padding.x, chart_bounds.bottom + 2), Vector2(time_text_size.x + padding.x * 2, time_text_size.y + padding.y * 2))

			parent_chart.draw_rect(time_bg_rect, Color(0.1, 0.1, 0.15, 0.9))
			parent_chart.draw_rect(time_bg_rect, axis_label_color, false, 1.0)
			parent_chart.draw_string(
				chart_font, Vector2(time_bg_rect.position.x + padding.x, time_bg_rect.position.y + padding.y + time_text_size.y - 4), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE
			)


func _draw_tooltip():
	"""Draw enhanced tooltip with color coding and better formatting (EXACT original)"""
	var tooltip_text = parent_chart.chart_interaction.tooltip_content
	var tooltip_position = parent_chart.chart_interaction.tooltip_position

	if (parent_chart.chart_interaction.hovered_point_index == -1 and parent_chart.chart_interaction.hovered_volume_index == -1) or tooltip_text.is_empty():
		return

	var font_size = 11
	var line_height = 14
	var padding = Vector2(10, 12)

	# Split tooltip text into lines
	var lines = tooltip_text.split("\n")
	var max_width = 0.0

	# Calculate tooltip dimensions
	for line in lines:
		var text_size = chart_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if text_size.x > max_width:
			max_width = text_size.x

	var tooltip_size = Vector2(max_width + padding.x * 2, lines.size() * line_height + padding.y * 2)

	# Position tooltip near cursor, but keep it on screen (EXACT original)
	var tooltip_pos = tooltip_position + Vector2(15, -tooltip_size.y / 2)

	# Keep tooltip within screen bounds (EXACT original)
	if tooltip_pos.x + tooltip_size.x > parent_chart.size.x:
		tooltip_pos.x = tooltip_position.x - tooltip_size.x - 15
	if tooltip_pos.y < 0:
		tooltip_pos.y = 0
	if tooltip_pos.y + tooltip_size.y > parent_chart.size.y:
		tooltip_pos.y = parent_chart.size.y - tooltip_size.y

	# Draw tooltip background with subtle gradient (EXACT original)
	var tooltip_rect = Rect2(tooltip_pos, tooltip_size)
	var bg_color = Color(0.08, 0.1, 0.12, 0.95)
	var border_color = Color(0.4, 0.45, 0.5, 1.0)
	var header_color = Color(0.12, 0.15, 0.18, 1.0)

	# Main background
	parent_chart.draw_rect(tooltip_rect, bg_color)

	# Header background for first line (EXACT original)
	if lines.size() > 0:
		var header_rect = Rect2(tooltip_pos, Vector2(tooltip_size.x, line_height + 4))
		parent_chart.draw_rect(header_rect, header_color)

	# Border
	parent_chart.draw_rect(tooltip_rect, border_color, false, 1.5)

	# Draw tooltip text with color coding (EXACT original)
	var text_pos = tooltip_pos + padding
	for i in range(lines.size()):
		var line = lines[i]
		var line_pos = text_pos + Vector2(0, i * line_height + 10)
		var text_color = Color.WHITE

		# Color code different types of information (EXACT original)
		if i == 0:  # Header line
			text_color = Color.CYAN
		elif line.contains("Open:") or line.contains("MA Price:"):
			text_color = Color.LIGHT_GREEN
		elif line.contains("High:") or line.contains("Raw Price:"):
			text_color = Color.GREEN
		elif line.contains("Low:"):
			text_color = Color.RED
		elif line.contains("Close:") or line.contains("Current Price:"):
			text_color = Color.YELLOW
		elif line.contains("Volume:"):
			text_color = Color.LIGHT_BLUE
		elif line.contains("Time:"):
			text_color = Color.GRAY
		elif line.contains("Station Trading:"):
			text_color = Color.ORANGE
		elif line.contains("Your Buy:"):
			text_color = Color.GREEN
		elif line.contains("Your Sell:"):
			text_color = Color.RED
		elif line.contains("Potential Profit:"):
			var profit_text = line
			if profit_text.contains("-"):
				text_color = Color.RED  # Negative profit
			else:
				text_color = Color.GREEN  # Positive profit
		elif line.contains("📈") or line.contains("Historical Low"):
			text_color = Color.LIGHT_GREEN
		elif line.contains("📉") or line.contains("Historical High"):
			text_color = Color.ORANGE

		parent_chart.draw_string(chart_font, line_pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _draw_spread_hover_tooltip():
	"""Draw spread analysis hover tooltip"""
	if not parent_chart.analysis_tools.is_hovering_spread_zone:
		return

	if chart_data.current_station_trading_data.is_empty():
		return

	var font_size = 11
	var font = chart_font
	var lines = []

	# Get station trading data for detailed tooltip
	var data = chart_data.current_station_trading_data
	if data.has("profit_margin"):
		lines = [
			"STATION TRADING OPPORTUNITY",
			"",
			"Your Buy Order: %s ISK" % _format_price_label(data.get("your_buy_price", 0)),
			"Your Sell Order: %s ISK" % _format_price_label(data.get("your_sell_price", 0)),
			"",
			"Cost (with fees): %s ISK" % _format_price_label(data.get("cost_with_fees", 0)),
			"Income (after taxes): %s ISK" % _format_price_label(data.get("income_after_taxes", 0)),
			"",
			"Profit: %s ISK per unit" % _format_price_label(data.get("profit_per_unit", 0)),
			"Margin: %.2f%%" % data.get("profit_margin", 0),
			"",
			_get_station_trading_quality_text(data.get("profit_margin", 0))
		]
	else:
		# Fallback to basic spread info
		var spread = parent_chart.analysis_tools.current_sell_price - parent_chart.analysis_tools.current_buy_price
		var margin_pct = (spread / parent_chart.analysis_tools.current_sell_price) * 100.0 if parent_chart.analysis_tools.current_sell_price > 0 else 0.0
		lines = ["SPREAD ANALYSIS", "Spread: %s ISK" % _format_price_label(spread), "Margin: %.2f%%" % margin_pct, _get_spread_quality_text(margin_pct)]

	var max_width = 0.0
	var line_height = 14

	# Calculate tooltip dimensions
	for line in lines:
		if line.length() > 0:
			var text_size = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			max_width = max(max_width, text_size.x)

	var padding = Vector2(12, 8)
	var tooltip_width = max_width + padding.x * 2
	var tooltip_height = lines.size() * line_height + padding.y * 2

	# Position tooltip
	var tooltip_pos = parent_chart.analysis_tools.spread_tooltip_position + Vector2(15, -tooltip_height / 2)

	# Keep tooltip within screen bounds
	if tooltip_pos.x + tooltip_width > parent_chart.size.x:
		tooltip_pos.x = parent_chart.analysis_tools.spread_tooltip_position.x - tooltip_width - 15
	if tooltip_pos.y < 0:
		tooltip_pos.y = 5
	if tooltip_pos.y + tooltip_height > parent_chart.size.y:
		tooltip_pos.y = parent_chart.size.y - tooltip_height - 5

	# Draw tooltip background
	var bg_color = Color(0.05, 0.08, 0.12, 0.95)
	var border_color = Color.CYAN

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
			text_color = Color.YELLOW
		elif line.contains("Your Buy Order:"):
			text_color = Color.GREEN
		elif line.contains("Your Sell Order:"):
			text_color = Color.RED

		parent_chart.draw_string(font, text_pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _draw_zoom_indicator():
	"""Draw time window indicator (EXACT original)"""
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


func _draw_drag_indicator():
	"""Show current chart position (EXACT original)"""
	var font_size = 10
	var current_time = Time.get_unix_time_from_system()
	var time_offset = current_time - parent_chart.chart_center_time

	if abs(time_offset) > 300.0:  # More than 5 minutes offset
		var hours_offset = time_offset / 3600.0
		var days_offset = time_offset / 86400.0

		var time_text = ""
		if abs(days_offset) >= 1.0:
			time_text = "%.1f days from now" % days_offset
		else:
			time_text = "%.1f hours from now" % hours_offset

		var text_size = chart_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var padding = Vector2(8, 4)
		var bg_rect = Rect2(Vector2(5, 5), Vector2(text_size.x + padding.x * 2, text_size.y + padding.y * 2))

		parent_chart.draw_rect(bg_rect, Color(0.2, 0.15, 0.0, 0.9))
		parent_chart.draw_rect(bg_rect, Color(0.5, 0.4, 0.2, 0.8), false, 1.0)
		parent_chart.draw_string(
			chart_font, Vector2(bg_rect.position.x + padding.x, bg_rect.position.y + padding.y + text_size.y - 4), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.ORANGE
		)


func _draw_no_data_message():
	var font_size = 16
	var text = "No market data available"
	var text_size = chart_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center_pos = parent_chart.size / 2
	var text_pos = center_pos - text_size / 2

	parent_chart.draw_string(chart_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GRAY)


func _draw_candlesticks(visible_candles: Array, window_start: float, window_end: float, min_price: float, price_range: float, chart_height: float, chart_y_offset: float):
	var scale_factors = chart_math.get_zoom_scale_factor()
	var scaled_candle_width = candle_width * scale_factors.volume_scale
	var scaled_wick_width = max(1.0, wick_width)

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


# Helper functions
func _calculate_volume_percentile(volume_data: Array, percentile: float) -> float:
	"""Calculate the Nth percentile of volume data for outlier detection"""
	if volume_data.is_empty():
		return 0.0

	var sorted_volumes = volume_data.duplicate()
	sorted_volumes.sort()

	var index = int((percentile / 100.0) * (sorted_volumes.size() - 1))
	index = clamp(index, 0, sorted_volumes.size() - 1)

	return sorted_volumes[index]


func _calculate_price_grid_interval(price_range: float) -> float:
	"""Calculate appropriate price interval for grid lines"""
	if price_range <= 0:
		return 1.0

	# Target around 8-12 grid lines
	var raw_interval = price_range / 10.0

	# Round to nice numbers
	var magnitude = pow(10, floor(log(raw_interval) / log(10)))
	var normalized = raw_interval / magnitude

	var nice_interval: float
	if normalized <= 1.5:
		nice_interval = 1.0 * magnitude
	elif normalized <= 3.0:
		nice_interval = 2.0 * magnitude
	elif normalized <= 7.0:
		nice_interval = 5.0 * magnitude
	else:
		nice_interval = 10.0 * magnitude

	return nice_interval


func _is_major_price_level(price: float, interval: float) -> bool:
	"""Check if this is a major price level (every 5th line)"""
	var larger_interval = interval * 5.0
	return abs(fmod(price, larger_interval)) < (interval * 0.1)


func _format_price_label_for_axis(price: float) -> String:
	"""Format price for axis labels"""
	if price >= 1000000000:
		return "%.2fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.2fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.2fK" % (price / 1000.0)
	if price >= 10:
		return "%.0f" % price

	return "%.2f" % price


func _format_price_label(price: float) -> String:
	"""Format price labels for display"""
	if price >= 1000000000:
		return "%.2fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.2fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.2fK" % (price / 1000.0)

	return "%.2f" % price


func _format_eve_time_label(timestamp: float, format_type: String) -> String:
	"""Format EVE time labels (EXACT original)"""
	var datetime = Time.get_datetime_dict_from_unix_time(timestamp)

	match format_type:
		"time":
			return "%02d:%02d" % [datetime.hour, datetime.minute]
		"daily":
			return "%d/%d" % [datetime.month, datetime.day]
		"multi_day":
			return "%d/%d" % [datetime.month, datetime.day]
		"weekly":
			return "%d/%d" % [datetime.month, datetime.day]
		"monthly":
			return "%d/%d" % [datetime.month, datetime.year % 100]
		_:
			return "%d/%d" % [datetime.month, datetime.day]


func _find_most_recent_eve_downtime(current_time: float) -> float:
	"""Find the most recent EVE downtime (11:00 UTC) (EXACT original)"""
	var current_datetime = Time.get_datetime_dict_from_unix_time(current_time)

	# Today's downtime
	var today_downtime = Time.get_unix_time_from_datetime_dict({"year": current_datetime.year, "month": current_datetime.month, "day": current_datetime.day, "hour": 11, "minute": 0, "second": 0})

	if today_downtime <= current_time:
		return today_downtime

	# Yesterday's downtime
	return today_downtime - 86400.0


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


func _get_station_trading_quality_text(margin_pct: float) -> String:
	"""Get text description of trading opportunity quality"""
	if margin_pct >= 10.0:
		return "EXCELLENT OPPORTUNITY"
	if margin_pct >= 5.0:
		return "GOOD OPPORTUNITY"
	if margin_pct >= 2.0:
		return "MARGINAL OPPORTUNITY"

	return "POOR OPPORTUNITY"


func _get_spread_quality_text(margin_pct: float) -> String:
	"""Get text description of spread quality"""
	if margin_pct >= 10.0:
		return "Wide Spread"
	if margin_pct >= 5.0:
		return "Good Spread"
	if margin_pct >= 2.0:
		return "Narrow Spread"

	return "Very Narrow Spread"
