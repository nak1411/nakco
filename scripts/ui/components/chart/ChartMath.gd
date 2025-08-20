# scripts/ui/components/chart/ChartMath.gd
class_name ChartMath
extends RefCounted

var parent_chart: MarketChart
var chart_data: ChartData

# Constants
var min_zoom: float = 1.0
var max_zoom: float = 365.0
var zoom_sensitivity: float = 1.2


func setup(chart: MarketChart, data: ChartData):
	parent_chart = chart
	chart_data = data


func get_current_time_window() -> float:
	return chart_data.base_time_window / parent_chart.zoom_level


func get_time_at_pixel(x_pixel: float) -> float:
	var time_window = get_current_time_window()
	var progress = x_pixel / parent_chart.size.x
	return parent_chart.chart_center_time - (time_window / 2.0) + (progress * time_window)


func get_price_at_pixel(y_pixel: float) -> float:
	# EXACT ORIGINAL PROPORTIONS - must match drawing coordinates exactly
	var chart_height = parent_chart.size.y * 0.6
	var chart_y_offset = parent_chart.size.y * 0.05
	var relative_y = y_pixel - chart_y_offset
	var progress = 1.0 - (relative_y / chart_height)  # Invert Y (top = high price)

	var half_range = parent_chart.chart_price_range / 2.0
	return parent_chart.chart_center_price - half_range + (progress * parent_chart.chart_price_range)


func get_chart_boundaries() -> Dictionary:
	# EXACT ORIGINAL BOUNDARIES from RealtimeChart.gd
	var y_track_width = 50  # Must match the original
	var chart_left = y_track_width
	var chart_right = parent_chart.size.x
	var chart_top = 0.0
	var chart_bottom = parent_chart.size.y * 0.70  # This stays the same as X-axis track starts here

	var chart_width = chart_right - chart_left
	var chart_height = chart_bottom - chart_top

	return {"left": chart_left, "right": chart_right, "top": chart_top, "bottom": chart_bottom, "width": chart_width, "height": chart_height}


func get_current_window_bounds() -> Dictionary:
	"""Get the current time and price window bounds (EXACT same as chart rendering)"""
	var time_window = get_current_time_window()
	var half_time = time_window / 2.0
	var half_price = parent_chart.chart_price_range / 2.0

	# Use EXACT same bounds calculation as the original chart system
	var bounds = {
		"time_start": parent_chart.chart_center_time - half_time,
		"time_end": parent_chart.chart_center_time + half_time,
		"price_min": parent_chart.chart_center_price - half_price,
		"price_max": parent_chart.chart_center_price + half_price
	}

	return bounds


func get_zoom_scale_factor() -> Dictionary:
	"""Calculate improved adaptive scale factors that prevent overlap at all zoom levels"""
	var time_window_days = get_current_time_window() / 86400.0

	# Calculate how many data points are visible
	var visible_data_points = 0
	var bounds = get_current_window_bounds()
	for point in chart_data.price_data:
		if point.timestamp >= bounds.time_start and point.timestamp <= bounds.time_end:
			visible_data_points += 1

	# Calculate available space per data point
	var chart_bounds = get_chart_boundaries()
	var available_width = chart_bounds.width
	var space_per_point = available_width / max(visible_data_points, 1) if visible_data_points > 0 else available_width

	# More aggressive volume scaling to prevent overlap
	var volume_scale: float

	# The key insight: we need much more aggressive scaling in the problem zone
	if space_per_point > 100.0:
		# Very zoomed in - large bars
		volume_scale = min(3.0, space_per_point / 40.0)
	elif space_per_point > 50.0:
		# Zoomed in - normal to large bars
		volume_scale = min(2.0, space_per_point / 30.0)
	elif space_per_point > 25.0:
		# Medium zoom - normal bars
		volume_scale = 1.0
	elif space_per_point > 15.0:
		# Getting tight - smaller bars
		volume_scale = space_per_point / 25.0
	elif space_per_point > 8.0:
		# Tight space - much smaller bars (this covers the problematic 2.8 month range)
		volume_scale = space_per_point / 35.0
	elif space_per_point > 4.0:
		# Very tight - very small bars
		volume_scale = space_per_point / 50.0
	elif space_per_point > 2.0:
		# Extremely tight - minimal bars
		volume_scale = space_per_point / 80.0
	else:
		# Ultra zoomed out - tiny bars
		volume_scale = max(0.05, space_per_point / 100.0)

	# Ensure bars never get larger than the available space
	var max_allowed_scale = space_per_point / 10.0  # Never use more than 10% of available space
	volume_scale = min(volume_scale, max_allowed_scale)

	# Absolute limits
	volume_scale = clamp(volume_scale, 0.05, 3.0)

	# Debug output for problematic ranges
	if time_window_days > 14.0 and time_window_days < 90.0:
		print("PROBLEM ZONE - Days: %.1f, Points: %d, Space: %.1f, Scale: %.3f" % [time_window_days, visible_data_points, space_per_point, volume_scale])

	return {"volume_scale": volume_scale, "space_per_point": space_per_point}


func clip_line_to_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> Dictionary:
	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y

	var xmin = rect.position.x
	var ymin = rect.position.y
	var xmax = rect.position.x + rect.size.x
	var ymax = rect.position.y + rect.size.y

	var outcode1 = _compute_outcode(x1, y1, xmin, ymin, xmax, ymax)
	var outcode2 = _compute_outcode(x2, y2, xmin, ymin, xmax, ymax)

	var max_iterations = 10
	var iteration_count = 0

	while iteration_count < max_iterations:
		iteration_count += 1

		if (outcode1 | outcode2) == 0:
			return {"start": Vector2(x1, y1), "end": Vector2(x2, y2)}
		if (outcode1 & outcode2) != 0:
			return {}

		var outcode_out = outcode1 if outcode1 != 0 else outcode2
		var x: float
		var y: float

		if outcode_out & 8:  # Top
			if abs(y2 - y1) > 0.001:
				x = x1 + (x2 - x1) * (ymax - y1) / (y2 - y1)
				y = ymax
			else:
				return {}
		elif outcode_out & 4:  # Bottom
			if abs(y2 - y1) > 0.001:
				x = x1 + (x2 - x1) * (ymin - y1) / (y2 - y1)
				y = ymin
			else:
				return {}
		elif outcode_out & 2:  # Right
			if abs(x2 - x1) > 0.001:
				y = y1 + (y2 - y1) * (xmax - x1) / (x2 - x1)
				x = xmax
			else:
				return {}
		else:  # Left
			if abs(x2 - x1) > 0.001:
				y = y1 + (y2 - y1) * (xmin - x1) / (x2 - x1)
				x = xmin
			else:
				return {}

		if outcode_out == outcode1:
			x1 = x
			y1 = y
			outcode1 = _compute_outcode(x1, y1, xmin, ymin, xmax, ymax)
		else:
			x2 = x
			y2 = y
			outcode2 = _compute_outcode(x2, y2, xmin, ymin, xmax, ymax)

	return {}


func _compute_outcode(x: float, y: float, xmin: float, ymin: float, xmax: float, ymax: float) -> int:
	var code = 0
	if x < xmin:
		code |= 1  # Left
	elif x > xmax:
		code |= 2  # Right
	if y < ymin:
		code |= 4  # Bottom
	elif y > ymax:
		code |= 8  # Top
	return code
