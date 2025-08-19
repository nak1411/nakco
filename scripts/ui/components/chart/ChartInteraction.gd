# scripts/ui/components/chart/ChartInteraction.gd
class_name ChartInteraction
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData
var chart_math: ChartMath

# Mouse interaction state
var mouse_position: Vector2 = Vector2.ZERO
var show_crosshair: bool = false
var hovered_point_index: int = -1
var hovered_volume_index: int = -1
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO

# Hover detection
var point_hover_radius: float = 8.0
var point_visual_radius: float = 4.0

# Tooltip state
var tooltip_content: String = ""
var tooltip_position: Vector2 = Vector2.ZERO

# Volume bar positions for hover detection
var current_volume_bar_positions: Array = []


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

	# Check volume bar hover first (using stored positions)
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
				break

	# If not hovering volume, check price points
	if hovered_volume_index == -1:
		var scale_factors = chart_math.get_zoom_scale_factor()
		var scaled_hover_radius = max(point_hover_radius * scale_factors.volume_scale, 6.0)

		var bounds = chart_math.get_current_window_bounds()
		var window_start = bounds.time_start
		var window_end = bounds.time_end
		var min_price = bounds.price_min
		var max_price = bounds.price_max
		var price_range = max_price - min_price

		# Get visible points
		var visible_points = []
		for point in chart_data.price_data:
			if point.timestamp >= window_start and point.timestamp <= window_end:
				visible_points.append(point)

		if visible_points.size() == 0:
			if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
				parent_chart.queue_redraw()
			return

		visible_points.sort_custom(func(a, b): return a.timestamp < b.timestamp)

		var chart_bounds = chart_math.get_chart_boundaries()
		var chart_height = parent_chart.size.y * 0.6  # EXACT original
		var chart_y_offset = parent_chart.size.y * 0.05  # EXACT original

		# Point hover detection
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
			lines.append("Price: %s ISK" % _format_price_label(point.price))

			var current_time = Time.get_unix_time_from_system()
			var time_diff = current_time - point.timestamp
			lines.append("Time: %s" % _format_time_ago(time_diff / 3600.0))

			if point.has("volume"):
				lines.append("Volume: %s" % _format_number(point.volume))

			tooltip_content = "\n".join(lines)

	# Redraw if hover state changed
	if old_hovered_index != hovered_point_index or old_hovered_volume != hovered_volume_index:
		parent_chart.queue_redraw()


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
	parent_chart.queue_redraw()


func _start_simple_drag(position: Vector2):
	is_dragging = true
	drag_start_position = position


func _stop_simple_drag():
	is_dragging = false


func _handle_simple_drag(event: InputEventMouseMotion):
	var drag_delta = event.position - drag_start_position

	var time_window = chart_math.get_current_time_window()
	var time_per_pixel = time_window / parent_chart.size.x
	var price_per_pixel = parent_chart.chart_price_range / (parent_chart.size.y * 0.6)

	var time_delta = drag_delta.x * time_per_pixel
	var price_delta = drag_delta.y * price_per_pixel

	parent_chart.chart_center_time -= time_delta
	parent_chart.chart_center_price += price_delta

	var current_time = Time.get_unix_time_from_system()
	var max_history = current_time - chart_data.max_data_retention

	parent_chart.chart_center_time = clamp(parent_chart.chart_center_time, max_history + time_window / 2, current_time)

	drag_start_position = event.position
	parent_chart.queue_redraw()


func _zoom_in_at_mouse(mouse_pos: Vector2):
	var old_zoom = parent_chart.zoom_level
	parent_chart.zoom_level = min(parent_chart.zoom_level * chart_math.zoom_sensitivity, chart_math.max_zoom)

	if parent_chart.zoom_level != old_zoom:
		_adjust_center_for_zoom(mouse_pos, old_zoom, parent_chart.zoom_level)
		parent_chart.queue_redraw()


func _zoom_out_at_mouse(mouse_pos: Vector2):
	var old_zoom = parent_chart.zoom_level
	parent_chart.zoom_level = max(parent_chart.zoom_level / chart_math.zoom_sensitivity, chart_math.min_zoom)

	if parent_chart.zoom_level != old_zoom:
		_adjust_center_for_zoom(mouse_pos, old_zoom, parent_chart.zoom_level)
		parent_chart.queue_redraw()


func _adjust_center_for_zoom(mouse_pos: Vector2, old_zoom: float, new_zoom: float):
	var mouse_time = chart_math.get_time_at_pixel(mouse_pos.x)
	var mouse_price = chart_math.get_price_at_pixel(mouse_pos.y)

	var zoom_factor = new_zoom / old_zoom

	var time_offset = mouse_time - parent_chart.chart_center_time
	parent_chart.chart_center_time = mouse_time - (time_offset / zoom_factor)

	var price_offset = mouse_price - parent_chart.chart_center_price
	parent_chart.chart_center_price = mouse_price - (price_offset / zoom_factor)

	parent_chart.chart_price_range = parent_chart.chart_price_range / zoom_factor


func _reset_to_current():
	parent_chart.chart_center_time = Time.get_unix_time_from_system()
	parent_chart.zoom_level = 1.0
	parent_chart.queue_redraw()


# Helper functions
func _format_time_ago(hours: float) -> String:
	if hours < 1.0:
		return "%.0fm ago" % (hours * 60.0)
	elif hours < 24.0:
		return "%.1fh ago" % hours
	else:
		return "%.1fd ago" % (hours / 24.0)


func _format_number(value: int) -> String:
	if value >= 1000000000:
		return "%.1fB" % (value / 1000000000.0)
	elif value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK" % (value / 1000.0)
	else:
		return str(value)


func _format_price_label(price: float) -> String:
	if price >= 1000000000:
		return "%.1fB" % (price / 1000000000.0)
	elif price >= 1000000:
		return "%.1fM" % (price / 1000000.0)
	elif price >= 1000:
		return "%.1fK" % (price / 1000.0)
	else:
		return "%.2f" % price
