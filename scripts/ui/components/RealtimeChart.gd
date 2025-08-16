# scripts/ui/components/RealtimeChart.gd
class_name RealtimeChart
extends Control

var price_data: Array[float] = []
var volume_data: Array[int] = []
var time_labels: Array[String] = []
var max_data_points: int = 100

var chart_color: Color = Color.GREEN
var background_color: Color = Color.BLACK
var grid_color: Color = Color.GRAY


func _ready():
	custom_minimum_size = Vector2(400, 200)


func _draw():
	draw_background()
	draw_grid()
	draw_price_line()
	draw_volume_bars()


func draw_background():
	draw_rect(Rect2(Vector2.ZERO, size), background_color)


func draw_grid():
	var grid_spacing = size.x / 10.0
	for i in range(11):
		var x = i * grid_spacing
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)

	grid_spacing = size.y / 5.0
	for i in range(6):
		var y = i * grid_spacing
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)


func draw_price_line():
	if price_data.size() < 2:
		return

	var max_price = price_data.max()
	var min_price = price_data.min()
	var price_range = max_price - min_price

	if price_range == 0:
		return

	var points: PackedVector2Array = []
	for i in range(price_data.size()):
		var x = (float(i) / float(price_data.size() - 1)) * size.x
		var normalized_price = (price_data[i] - min_price) / price_range
		var y = size.y - (normalized_price * size.y)
		points.append(Vector2(x, y))

	# Draw the price line
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], chart_color, 2.0)


func draw_volume_bars():
	if volume_data.size() == 0:
		return

	var max_volume = volume_data.max() as float
	if max_volume == 0:
		return

	var bar_width = size.x / float(volume_data.size())
	var volume_height_scale = size.y * 0.3  # Use bottom 30% for volume

	for i in range(volume_data.size()):
		var bar_height = (float(volume_data[i]) / max_volume) * volume_height_scale
		var x = i * bar_width
		var y = size.y - bar_height

		var bar_rect = Rect2(x, y, bar_width - 1, bar_height)
		draw_rect(bar_rect, chart_color.lerp(Color.WHITE, 0.3))


func add_data_point(price: float, volume: int, time_label: String = ""):
	price_data.append(price)
	volume_data.append(volume)
	time_labels.append(time_label)

	# Keep only recent data
	if price_data.size() > max_data_points:
		price_data.pop_front()
		volume_data.pop_front()
		time_labels.pop_front()

	queue_redraw()


func clear_data():
	price_data.clear()
	volume_data.clear()
	time_labels.clear()
	queue_redraw()
