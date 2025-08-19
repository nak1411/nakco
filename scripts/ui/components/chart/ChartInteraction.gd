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
	print("Started dragging")


func _stop_simple_drag():
	is_dragging = false
	print("Stopped dragging")


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
		print("Zoomed in to %.1fx at mouse position" % parent_chart.zoom_level)


func _zoom_out_at_mouse(mouse_pos: Vector2):
	var old_zoom = parent_chart.zoom_level
	parent_chart.zoom_level = max(parent_chart.zoom_level / chart_math.zoom_sensitivity, chart_math.min_zoom)

	if parent_chart.zoom_level != old_zoom:
		_adjust_center_for_zoom(mouse_pos, old_zoom, parent_chart.zoom_level)
		parent_chart.queue_redraw()
		print("Zoomed out to %.1fx from mouse position" % parent_chart.zoom_level)


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
	print("Reset to current time and 1.0x zoom")


func _check_point_hover(_mouse_pos: Vector2):
	var old_hovered_index = hovered_point_index
	hovered_point_index = -1

	# Check for point hovering logic here...
	# (Implementation details omitted for brevity)

	if hovered_point_index != old_hovered_index:
		parent_chart.queue_redraw()
