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
	# EXACT ORIGINAL PROPORTIONS
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
	var chart_bottom = parent_chart.size.y * 0.7  # This stays the same as X-axis track starts here

	var chart_width = chart_right - chart_left
	var chart_height = chart_bottom - chart_top

	return {"left": chart_left, "right": chart_right, "top": chart_top, "bottom": chart_bottom, "width": chart_width, "height": chart_height}


# Update scripts/ui/components/chart/ChartMath.gd
func get_current_window_bounds() -> Dictionary:
	var time_window = get_current_time_window()
	var window_start = parent_chart.chart_center_time - (time_window / 2.0)
	var window_end = parent_chart.chart_center_time + (time_window / 2.0)

	var visible_points = []
	var visible_candles = []

	for point in chart_data.price_data:
		if point.timestamp >= window_start and point.timestamp <= window_end:
			visible_points.append(point)

	for candle in chart_data.candlestick_data:
		if candle.timestamp >= window_start and candle.timestamp <= window_end:
			visible_candles.append(candle)

	var min_price = parent_chart.chart_center_price - (parent_chart.chart_price_range / 2.0)
	var max_price = parent_chart.chart_center_price + (parent_chart.chart_price_range / 2.0)

	if visible_points.size() > 0 or visible_candles.size() > 0:
		var all_prices = []

		for point in visible_points:
			all_prices.append(point.price)

		for candle in visible_candles:
			if candle.get("high", 0) > 0:
				all_prices.append(candle.high)
			if candle.get("low", 0) > 0:
				all_prices.append(candle.low)

		if all_prices.size() > 0:
			min_price = all_prices[0]
			max_price = all_prices[0]
			for price in all_prices:
				if price < min_price:
					min_price = price
				if price > max_price:
					max_price = price

			# FIX: If all prices are the same, create an artificial range
			if max_price - min_price < 0.01:  # Essentially zero range
				var center_price = min_price
				var artificial_range = max(center_price * 0.1, 1000000.0)  # 10% of price or 1M ISK minimum
				min_price = center_price - (artificial_range / 2.0)
				max_price = center_price + (artificial_range / 2.0)
				print("Created artificial price range: %.2f - %.2f (center: %.2f)" % [min_price, max_price, center_price])

	return {"time_start": window_start, "time_end": window_end, "price_min": min_price, "price_max": max_price}


func get_zoom_scale_factor() -> Dictionary:
	var time_window_days = get_current_time_window() / 86400.0

	var volume_scale: float
	if time_window_days <= 1.0:
		volume_scale = 2.0
	elif time_window_days <= 7.0:
		volume_scale = 1.5
	elif time_window_days <= 30.0:
		volume_scale = 1.2
	else:
		volume_scale = 1.0

	return {"volume_scale": volume_scale}


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
