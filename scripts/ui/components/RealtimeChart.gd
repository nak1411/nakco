# scripts/ui/components/RealtimeChart.gd
class_name RealtimeChart
extends Control

signal price_level_clicked(price: float)

var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var time_labels: Array[String] = []
var max_data_points: int = 200

var chart_color: Color = Color.GREEN
var background_color: Color = Color(0.1, 0.12, 0.15, 1)
var grid_color: Color = Color(0.3, 0.3, 0.4, 0.3)
var buy_color: Color = Color(0.2, 0.8, 0.2, 1)
var sell_color: Color = Color(0.8, 0.2, 0.2, 1)
var volume_color: Color = Color(0.4, 0.6, 1.0, 0.7)

# Price level indicators
var support_levels: Array[float] = []
var resistance_levels: Array[float] = []

# Mouse interaction
var mouse_position: Vector2 = Vector2.ZERO
var show_crosshair: bool = false


func _ready():
	custom_minimum_size = Vector2(400, 200)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


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
	draw_grid()
	draw_price_line()
	draw_volume_bars()
	draw_price_levels()
	if show_crosshair:
		draw_crosshair()


func draw_background():
	draw_rect(Rect2(Vector2.ZERO, size), background_color)


func draw_grid():
	# Vertical grid lines (time)
	var time_divisions = 10
	for i in range(time_divisions + 1):
		var x = (float(i) / time_divisions) * size.x
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)

	# Horizontal grid lines (price)
	var price_divisions = 8
	for i in range(price_divisions + 1):
		var y = (float(i) / price_divisions) * size.y
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)


func draw_price_line():
	if price_data.size() < 2:
		return

	var min_price = get_min_price()
	var max_price = get_max_price()
	var price_range = max_price - min_price

	if price_range == 0:
		return

	var points: PackedVector2Array = []
	for i in range(price_data.size()):
		var x = (float(i) / float(price_data.size() - 1)) * size.x
		var normalized_price = (price_data[i].price - min_price) / price_range
		var y = size.y * 0.7 - (normalized_price * size.y * 0.6)  # Leave space for volume
		points.append(Vector2(x, y))

	# Draw the price line with gradient effect
	for i in range(points.size() - 1):
		var color_intensity = 1.0 - (float(i) / points.size())
		var line_color = chart_color * color_intensity
		draw_line(points[i], points[i + 1], line_color, 2.0)

	# Draw price points
	for i in range(points.size()):
		var point_color = chart_color
		if i == points.size() - 1:  # Latest point
			point_color = Color.YELLOW
		draw_circle(points[i], 3.0, point_color)


func draw_volume_bars():
	if volume_data.size() == 0:
		return

	var max_volume = get_max_volume()
	if max_volume == 0:
		return

	var bar_width = size.x / float(volume_data.size())
	var volume_height_scale = size.y * 0.25  # Use bottom 25% for volume

	for i in range(volume_data.size()):
		var bar_height = (float(volume_data[i]) / max_volume) * volume_height_scale
		var x = i * bar_width
		var y = size.y - bar_height

		var bar_rect = Rect2(x, y, bar_width - 1, bar_height)

		# Color based on volume intensity
		var volume_intensity = float(volume_data[i]) / max_volume
		var bar_color = volume_color * (0.3 + volume_intensity * 0.7)

		draw_rect(bar_rect, bar_color)


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
		draw_line(Vector2(0, y), Vector2(size.x, y), Color.GREEN, 2.0, true)

		# Add label
		var font = ThemeDB.fallback_font
		var font_size = 10
		draw_string(font, Vector2(5, y - 5), "Support: %.2f" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)

	# Draw resistance levels
	for level in resistance_levels:
		var y = size.y * 0.7 - ((level - min_price) / price_range) * size.y * 0.6
		draw_line(Vector2(0, y), Vector2(size.x, y), Color.RED, 2.0, true)

		# Add label
		var font = ThemeDB.fallback_font
		var font_size = 10
		draw_string(font, Vector2(5, y + 15), "Resistance: %.2f" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.RED)


func draw_crosshair():
	"""Draw crosshair and price/time info at mouse position"""
	if not show_crosshair:
		return

	# Draw crosshair lines
	draw_line(Vector2(0, mouse_position.y), Vector2(size.x, mouse_position.y), Color.WHITE, 1.0, true)
	draw_line(Vector2(mouse_position.x, 0), Vector2(mouse_position.x, size.y), Color.WHITE, 1.0, true)

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

			draw_rect(Rect2(label_pos - Vector2(2, text_size.y + 2), text_size + Vector2(4, 4)), Color.BLACK)
			draw_string(font, label_pos, price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func add_data_point(price: float, volume: int, time_label: String = ""):
	var data_point = {"price": price, "volume": volume, "timestamp": Time.get_ticks_msec() / 1000.0, "time_label": time_label}

	price_data.append(data_point)
	volume_data.append(volume)
	time_labels.append(time_label)

	# Keep only recent data
	if price_data.size() > max_data_points:
		price_data.pop_front()
		volume_data.pop_front()
		time_labels.pop_front()

	# Update support/resistance levels
	update_price_levels()

	queue_redraw()
	print("Chart updated: price=", price, " volume=", volume, " at ", time_label)


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
	price_data.clear()
	volume_data.clear()
	time_labels.clear()
	support_levels.clear()
	resistance_levels.clear()
	queue_redraw()


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
	var max_val = volume_data[0]
	for vol in volume_data:
		if vol > max_val:
			max_val = vol
	return max_val


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
