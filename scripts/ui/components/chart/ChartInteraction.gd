# scripts/ui/components/chart/ChartInteraction.gd
class_name ChartInteraction
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData
var chart_math: ChartMath

# Mouse interaction state (EXACT original)
var mouse_position: Vector2 = Vector2.ZERO
var show_crosshair: bool = false
var hovered_point_index: int = -1
var hovered_volume_index: int = -1
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO

# Hover detection (EXACT original)
var point_hover_radius: float = 8.0
var point_visual_radius: float = 4.0

# Tooltip state
var tooltip_content: String = ""
var tooltip_position: Vector2 = Vector2.ZERO

# Volume bar positions for hover detection
var current_volume_bar_positions: Array = []

# Spread zone for hover detection
var spread_zone_rect: Rect2 = Rect2()
var spread_value: float = 0.0
var spread_margin: float = 0.0


func setup(chart: MarketChart, data: ChartData, math: ChartMath):
	parent_chart = chart
	chart_data = data
	chart_math = math


func handle_input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position

		if is_dragging:
			_handle_simple_drag(event)
		else:
			_check_point_hover(mouse_position)
			if parent_chart.show_spread_analysis:
				_check_spread_zone_hover(mouse_position)

		parent_chart.get_viewport().set_input_as_handled()
		if show_crosshair:
			parent_chart.queue_redraw()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_simple_drag(event.position)
			else:
				_stop_simple_drag()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_reset_to_current()
			parent_chart.get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in_at_mouse(event.position)
			parent_chart.get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out_at_mouse(event.position)
			parent_chart.get_viewport().set_input_as_handled()
		else:
			parent_chart.get_viewport().set_input_as_handled()


func _handle_simple_drag(event: InputEventMouseMotion):
	"""Handle simple chart panning (EXACT original with debug)"""
	var drag_delta = event.position - drag_start_position

	# Calculate how much to move based on current zoom level (EXACT original)
	var time_window = chart_math.get_current_time_window()
	var time_per_pixel = time_window / parent_chart.size.x
	var price_per_pixel = parent_chart.chart_price_range / (parent_chart.size.y * 0.6)

	# Move chart center (opposite direction of drag for natural feel) (EXACT original)
	var time_delta = drag_delta.x * time_per_pixel
	var price_delta = drag_delta.y * price_per_pixel

	# DEBUG: Show what's happening
	print("Drag delta: x=%.1f, y=%.1f" % [drag_delta.x, drag_delta.y])
	print("Time delta: %.2f, Price delta: %.2f" % [time_delta, price_delta])
	print("Before: center_time=%.0f, center_price=%.2f" % [parent_chart.chart_center_time, parent_chart.chart_center_price])

	parent_chart.chart_center_time -= time_delta
	parent_chart.chart_center_price += price_delta  # This affects Y-axis labels

	print("After: center_time=%.0f, center_price=%.2f" % [parent_chart.chart_center_time, parent_chart.chart_center_price])
	print("Price range: %.2f" % parent_chart.chart_price_range)

	# Clamp to reasonable limits (EXACT original)
	var current_time = Time.get_unix_time_from_system()
	var max_history = _get_max_historical_time()

	parent_chart.chart_center_time = clamp(parent_chart.chart_center_time, max_history + time_window / 2, current_time)

	# Reset drag start for smooth continuous dragging (EXACT original)
	drag_start_position = event.position

	# Update support/resistance levels immediately when panning (if enabled) (EXACT original)
	if parent_chart.show_support_resistance:
		parent_chart.analysis_tools.update_price_levels()

	parent_chart.queue_redraw()  # This will redraw everything including spread analysis with new bounds


func _zoom_in_at_mouse(mouse_pos: Vector2):
	"""Zoom in toward the mouse position (EXACT original)"""
	var old_zoom = parent_chart.zoom_level
	parent_chart.zoom_level = min(parent_chart.zoom_level * chart_math.zoom_sensitivity, chart_math.max_zoom)

	if parent_chart.zoom_level != old_zoom:
		# Adjust chart center to zoom toward mouse position (EXACT original)
		_adjust_center_for_zoom(mouse_pos, old_zoom, parent_chart.zoom_level)

		# Update support/resistance levels immediately when zooming (if enabled) (EXACT original)
		if parent_chart.show_support_resistance:
			parent_chart.analysis_tools.update_price_levels()

		parent_chart.queue_redraw()  # This will redraw everything including spread analysis with new bounds
		print("Zoomed in to %.1fx at mouse position" % parent_chart.zoom_level)


func _zoom_out_at_mouse(mouse_pos: Vector2):
	"""Zoom out from the mouse position (EXACT original)"""
	var old_zoom = parent_chart.zoom_level
	parent_chart.zoom_level = max(parent_chart.zoom_level / chart_math.zoom_sensitivity, chart_math.min_zoom)

	if parent_chart.zoom_level != old_zoom:
		# Adjust chart center to zoom from mouse position (EXACT original)
		_adjust_center_for_zoom(mouse_pos, old_zoom, parent_chart.zoom_level)

		# Update support/resistance levels immediately when zooming (if enabled) (EXACT original)
		if parent_chart.show_support_resistance:
			parent_chart.analysis_tools.update_price_levels()

		parent_chart.queue_redraw()  # This will redraw everything including spread analysis with new bounds
		print("Zoomed out to %.1fx from mouse position" % parent_chart.zoom_level)


func _adjust_center_for_zoom(mouse_pos: Vector2, old_zoom: float, new_zoom: float):
	"""Adjust chart center so zoom appears to happen at mouse position (EXACT original)"""
	# Calculate what time/price the mouse was pointing at before zoom (EXACT original)
	var mouse_time = chart_math.get_time_at_pixel(mouse_pos.x)
	var mouse_price = chart_math.get_price_at_pixel(mouse_pos.y)

	# Calculate zoom factor (EXACT original)
	var zoom_factor = new_zoom / old_zoom

	# Adjust time center (EXACT original)
	var time_offset = mouse_time - parent_chart.chart_center_time
	parent_chart.chart_center_time = mouse_time - (time_offset / zoom_factor)

	# Adjust price center (this affects Y-axis labels) (EXACT original)
	var price_offset = mouse_price - parent_chart.chart_center_price
	parent_chart.chart_center_price = mouse_price - (price_offset / zoom_factor)

	# Also adjust price range for zoom (EXACT original)
	parent_chart.chart_price_range = parent_chart.chart_price_range / zoom_factor


func _reset_to_current():
	"""Reset chart to current time and auto-fit price (EXACT original)"""
	parent_chart.chart_center_time = Time.get_unix_time_from_system()
	parent_chart.zoom_level = 1.0
	parent_chart.initialize_price_center()
	parent_chart.queue_redraw()
	print("Reset to current time and auto price range")


func _get_max_historical_time() -> float:
	"""Get the maximum historical time (EXACT original)"""
	var current_time = Time.get_unix_time_from_system()
	return current_time - chart_data.max_data_retention


func _check_point_hover(mouse_pos: Vector2):
	"""Check if mouse is hovering over any data point, volume bar, or candlestick (EXACT original)"""
	var old_hovered_index = hovered_point_index
	var old_hovered_volume = hovered_volume_index
	hovered_point_index = -1
	hovered_volume_index = -1
	tooltip_content = ""

	if chart_data.price_data.size() < 1:
		if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
			parent_chart.queue_redraw()
		return

	# Check volume bar hover first (using stored positions) (EXACT original)
	if current_volume_bar_positions.size() > 0:
		for bar_data in current_volume_bar_positions:
			var bar_rect = bar_data.rect
			if bar_rect.has_point(mouse_pos):
				hovered_volume_index = bar_data.original_index
				tooltip_position = mouse_pos

				var volume = bar_data.volume
				var timestamp = bar_data.timestamp
				var current_time = Time.get_unix_time_from_system()
				var time_diff = current_time - timestamp
				var time_text = _format_time_ago(time_diff / 3600.0)

				tooltip_content = "Volume: %s\nTime: %s" % [_format_number(volume), time_text]

				print("Volume bar hover: index=%d, volume=%d" % [hovered_volume_index, volume])
				break

	# If not hovering volume, check price points (EXACT original)
	if hovered_volume_index == -1:
		# Get zoom scaling for consistent hover detection (EXACT original)
		var scale_factors = chart_math.get_zoom_scale_factor()
		var scaled_hover_radius = max(point_hover_radius * scale_factors.volume_scale, 6.0)

		# Use new window bounds system (EXACT original)
		var bounds = chart_math.get_current_window_bounds()
		var window_start = bounds.time_start
		var window_end = bounds.time_end
		var min_price = bounds.price_min
		var max_price = bounds.price_max
		var price_range = max_price - min_price

		# Get visible points and candlesticks (EXACT original)
		var visible_points = []
		var visible_candles = []

		for point in chart_data.price_data:
			if point.timestamp >= window_start and point.timestamp <= window_end:
				visible_points.append(point)

		for candle in chart_data.candlestick_data:
			if candle.timestamp >= window_start and candle.timestamp <= window_end:
				visible_candles.append(candle)

		if visible_points.size() == 0 and visible_candles.size() == 0:
			if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
				parent_chart.queue_redraw()
			return

		# Sort data (EXACT original)
		visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)
		visible_candles.sort_custom(func(a, b): return a.timestamp < b.timestamp)

		var chart_bounds = chart_math.get_chart_boundaries()
		var chart_height = parent_chart.size.y * 0.6  # EXACT original
		var chart_y_offset = parent_chart.size.y * 0.05  # EXACT original

		# Moving average point hover detection (EXACT original)
		var closest_distance = scaled_hover_radius + 1
		var closest_index = -1

		for i in range(visible_points.size()):
			var point = visible_points[i]
			var timestamp = point.timestamp

			var time_progress = (timestamp - window_start) / (window_end - window_start)
			var chart_width = chart_bounds.right - chart_bounds.left
			var x = chart_bounds.left + (time_progress * chart_width)

			var normalized_price = (point.price - min_price) / price_range
			var y = chart_y_offset + chart_height * (1.0 - normalized_price)

			var distance = mouse_pos.distance_to(Vector2(x, y))

			if distance <= scaled_hover_radius and distance < closest_distance:
				closest_distance = distance
				closest_index = i

		if closest_index != -1:
			hovered_point_index = closest_index
			tooltip_position = mouse_pos

			var point = visible_points[closest_index]
			var lines = []

			# EXACT original tooltip format
			var is_historical = point.get("is_historical", false)
			var point_type = "Historical" if is_historical else "Real-time"
			var price_label = "MA Price" if is_historical else "Current Price"

			lines.append("%s Data Point" % point_type)
			lines.append("%s: %s ISK" % [price_label, _format_price_label(point.price)])

			# Find and show high/low for this time period
			var extremes = _find_recent_extremes(visible_points, visible_candles, closest_index)
			if extremes.has("high") and extremes.has("low"):
				lines.append("High: %s ISK" % _format_price_label(extremes.high))
				lines.append("Low: %s ISK" % _format_price_label(extremes.low))

			# Add volume analysis at different price levels
			var volume_analysis = _analyze_volume_at_price_levels(point.price)
			if not volume_analysis.is_empty():
				lines.append("")  # Empty line separator
				lines.append("VOLUME ANALYSIS:")
				for level_info in volume_analysis:
					lines.append(level_info)

			var current_time = Time.get_unix_time_from_system()
			var time_diff = current_time - point.timestamp
			lines.append("Time: %s" % _format_time_ago(time_diff / 3600.0))

			if point.has("volume") and is_historical:
				lines.append("Volume: %s" % _format_number(point.volume))

			tooltip_content = "\n".join(lines)

	# Check spread zone hover if enabled (EXACT original)
	if parent_chart.show_spread_analysis and hovered_point_index == -1 and hovered_volume_index == -1:
		_check_spread_zone_hover(mouse_pos)

	# Redraw if hover state changed (EXACT original)
	if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
		parent_chart.queue_redraw()


func _analyze_volume_at_price_levels(current_price: float) -> Array:
	"""Analyze volume at different price levels around the current price"""
	var analysis = []

	# Get current market data
	var market_data = parent_chart.chart_data.current_station_trading_data
	if market_data.is_empty():
		return analysis

	var buy_orders = market_data.get("buy_orders", [])
	var sell_orders = market_data.get("sell_orders", [])

	if buy_orders.is_empty() and sell_orders.is_empty():
		return analysis

	# Analyze volume within price ranges around current price
	var price_ranges = [{"range": "±1%", "multiplier": 0.01}, {"range": "±5%", "multiplier": 0.05}, {"range": "±10%", "multiplier": 0.10}]

	for range_info in price_ranges:
		var range_text = range_info.range
		var price_tolerance = current_price * range_info.multiplier
		var min_price = current_price - price_tolerance
		var max_price = current_price + price_tolerance

		var buy_volume = 0
		var sell_volume = 0

		# Count buy volume in this price range
		for order in buy_orders:
			var price = order.get("price", 0.0)
			if price >= min_price and price <= max_price:
				buy_volume += order.get("volume", 0)

		# Count sell volume in this price range
		for order in sell_orders:
			var price = order.get("price", 0.0)
			if price >= min_price and price <= max_price:
				sell_volume += order.get("volume", 0)

		if buy_volume > 0 or sell_volume > 0:
			var total_volume = buy_volume + sell_volume
			analysis.append("%s: %s units (%s buy, %s sell)" % [range_text, _format_number(total_volume), _format_number(buy_volume), _format_number(sell_volume)])

	return analysis


func _calculate_price_percentile(price: float, visible_points: Array) -> float:
	"""Calculate what percentile this price is in the visible data (EXACT original)"""
	if visible_points.size() < 2:
		return 50.0  # Default to 50th percentile if not enough data

	var prices = []
	for point in visible_points:
		if point.get("is_historical", false):  # Only use historical data for percentile
			prices.append(point.price)

	if prices.size() < 2:
		return 50.0

	prices.sort()

	# Find where this price ranks
	var rank = 0
	for p in prices:
		if price >= p:
			rank += 1

	return (float(rank) / float(prices.size())) * 100.0


func _format_time_ago(hours: float) -> String:
	"""Format time ago text (EXACT original)"""
	var time_window = chart_math.get_current_time_window()
	var window_hours = time_window / 3600.0

	if window_hours <= 24:  # Up to a day - show minutes/hours
		if hours < 1.0:
			return "%.0fm ago" % (hours * 60.0)
		return "%.1fh ago" % hours
	if window_hours <= 168:  # Up to a week - show hours/days
		if hours < 24:
			return "%.1fh ago" % hours
		return "%.1fd ago" % (hours / 24.0)

	if hours < 24:
		return "%.1fd ago" % (hours / 24.0)

	var days = hours / 24.0
	if days < 7:
		return "%.1fd ago" % days

	return "%.1fw ago" % (days / 7.0)


func _format_number(value: int) -> String:
	"""Format numbers for display (EXACT original)"""
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)

	return str(value)


func _format_price_label(price: float) -> String:
	"""Format price labels (EXACT original)"""
	if price >= 1000000000:
		return "%.2fB" % (price / 1000000000.0)
	if price >= 1000000:
		return "%.2fM" % (price / 1000000.0)
	if price >= 1000:
		return "%.2fK" % (price / 1000.0)

	return "%.2f" % price


func _check_spread_zone_hover(mouse_position: Vector2):
	# Delegate to analysis tools
	if parent_chart.analysis_tools:
		parent_chart.analysis_tools.check_spread_zone_hover(mouse_position)


func _on_mouse_entered():
	show_crosshair = true
	parent_chart.mouse_default_cursor_shape = Control.CURSOR_CROSS


func _on_mouse_exited():
	show_crosshair = false
	hovered_point_index = -1
	hovered_volume_index = -1
	parent_chart.mouse_default_cursor_shape = Control.CURSOR_ARROW
	parent_chart.queue_redraw()


func _on_chart_resized():
	print("Chart resized to: %.1f x %.1f" % [parent_chart.size.x, parent_chart.size.y])

	# Update cached chart boundaries (EXACT original)
	var boundaries = chart_math.get_chart_boundaries()
	print("New chart boundaries: top=%.1f, bottom=%.1f, height=%.1f" % [boundaries.top, boundaries.bottom, boundaries.height])

	# Update support/resistance levels if enabled (EXACT original)
	if parent_chart.show_support_resistance:
		parent_chart.analysis_tools.update_price_levels()

	# Force complete redraw with new dimensions (EXACT original)
	parent_chart.queue_redraw()


func _find_recent_extremes(points: Array, candles: Array, point_index: int) -> Dictionary:
	"""Find high/low for the specific day being hovered over"""
	var result = {}

	if point_index >= 0 and point_index < points.size():
		var hovered_point = points[point_index]
		var hover_timestamp = hovered_point.timestamp

		# Find the candlestick that matches this day (within 24 hours)
		var matching_candle = null
		var closest_time_diff = 999999999.0

		for candle in candles:
			var time_diff = abs(candle.timestamp - hover_timestamp)
			# If within same day (12 hours tolerance)
			if time_diff < 43200.0 and time_diff < closest_time_diff:  # 12 hours
				closest_time_diff = time_diff
				matching_candle = candle

		if matching_candle:
			var high = matching_candle.get("high", 0.0)
			var low = matching_candle.get("low", 0.0)
			if high > 0 and low > 0:
				result["high"] = high
				result["low"] = low

	return result


func _start_simple_drag(position: Vector2):
	"""Start simple dragging (EXACT original)"""
	is_dragging = true
	drag_start_position = position
	print("Started dragging")


func _stop_simple_drag():
	"""Stop dragging (EXACT original)"""
	is_dragging = false
	print("Stopped dragging")
