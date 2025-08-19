# scripts/ui/components/VolumeChart.gd
class_name VolumeChart
extends Control

signal volume_bar_clicked(timestamp: float, volume: int)

# Current display mode
enum VolumeDisplayMode { TOTAL_VOLUME, BUY_SELL_SPLIT, STACKED_ORDERS }

# Volume data storage
var volume_data: Array[Dictionary] = []
var max_volume: int = 0
var time_range: float = 3600.0  # 1 hour default

# Chart styling
var background_color: Color = Color(0.1, 0.1, 0.15, 1.0)
var grid_color: Color = Color(0.3, 0.3, 0.4, 0.5)
var buy_volume_color: Color = Color(0.2, 0.8, 0.2, 0.8)  # Green for buy volume
var sell_volume_color: Color = Color(0.8, 0.2, 0.2, 0.8)  # Red for sell volume
var total_volume_color: Color = Color(0.4, 0.4, 0.8, 0.8)  # Blue for total volume
var text_color: Color = Color(0.9, 0.9, 0.9, 1.0)

# Chart layout
var margin_left: float = 60.0
var margin_right: float = 20.0
var margin_top: float = 20.0
var margin_bottom: float = 40.0

var display_mode: VolumeDisplayMode = VolumeDisplayMode.TOTAL_VOLUME


func _ready():
	custom_minimum_size = Vector2(300, 150)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw():
	var rect = get_rect()

	# Draw background
	draw_rect(rect, background_color)

	if volume_data.is_empty():
		draw_no_data_message()
		return

	# Calculate chart area
	var chart_area = Rect2(margin_left, margin_top, rect.size.x - margin_left - margin_right, rect.size.y - margin_top - margin_bottom)

	# Draw grid and axes
	draw_grid(chart_area)
	draw_axes(chart_area)

	# Draw volume bars
	match display_mode:
		VolumeDisplayMode.TOTAL_VOLUME:
			draw_total_volume_bars(chart_area)
		VolumeDisplayMode.BUY_SELL_SPLIT:
			draw_buy_sell_split_bars(chart_area)
		VolumeDisplayMode.STACKED_ORDERS:
			draw_stacked_order_bars(chart_area)


func draw_no_data_message():
	var rect = get_rect()
	var font = ThemeDB.fallback_font
	var font_size = 16
	var text = "No volume data available"

	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var center_pos = Vector2(rect.size.x / 2.0, rect.size.y / 2.0)

	draw_string(font, center_pos - text_size / 2.0, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


func draw_grid(chart_area: Rect2):
	# Draw horizontal grid lines (volume levels)
	var grid_lines = 5
	for i in range(grid_lines + 1):
		var y = chart_area.position.y + (chart_area.size.y * i / grid_lines)
		draw_line(Vector2(chart_area.position.x, y), Vector2(chart_area.position.x + chart_area.size.x, y), grid_color, 1.0)

	# Draw vertical grid lines (time intervals)
	var time_divisions = 6
	for i in range(time_divisions + 1):
		var x = chart_area.position.x + (chart_area.size.x * i / time_divisions)
		draw_line(Vector2(x, chart_area.position.y), Vector2(x, chart_area.position.y + chart_area.size.y), grid_color, 1.0)


func draw_axes(chart_area: Rect2):
	var font = ThemeDB.fallback_font
	var font_size = 12

	# Y-axis labels (volume)
	var volume_steps = 5
	for i in range(volume_steps + 1):
		var volume_value = max_volume * i / volume_steps
		var y = chart_area.position.y + chart_area.size.y - (chart_area.size.y * i / volume_steps)
		var label = format_volume(volume_value)

		var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size)
		draw_string(font, Vector2(margin_left - text_size.x - 5, y + text_size.y / 2), label, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, text_color)

	# X-axis labels (time)
	var time_steps = 6
	var current_time = Time.get_unix_time_from_system()
	for i in range(time_steps + 1):
		var time_offset = time_range * i / time_steps
		var timestamp = current_time - time_range + time_offset
		var x = chart_area.position.x + (chart_area.size.x * i / time_steps)

		var time_label = Time.get_datetime_string_from_unix_time(timestamp).substr(11, 5)  # HH:MM
		var text_size = font.get_string_size(time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(x - text_size.x / 2, chart_area.position.y + chart_area.size.y + text_size.y + 5), time_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


func draw_total_volume_bars(chart_area: Rect2):
	if volume_data.is_empty() or max_volume == 0:
		return

	var bar_width = chart_area.size.x / max(volume_data.size(), 1)
	var current_time = Time.get_unix_time_from_system()

	for i in range(volume_data.size()):
		var data_point = volume_data[i]
		var volume = data_point.get("total_volume", 0)
		var timestamp = data_point.get("timestamp", current_time)

		# Calculate bar position and height
		var x = chart_area.position.x + (i * bar_width)
		var bar_height = (float(volume) / float(max_volume)) * chart_area.size.y
		var y = chart_area.position.y + chart_area.size.y - bar_height

		# Draw volume bar
		var bar_rect = Rect2(x + 1, y, bar_width - 2, bar_height)
		draw_rect(bar_rect, total_volume_color)

		# Add border
		draw_rect(bar_rect, text_color, false, 1.0)


func draw_buy_sell_split_bars(chart_area: Rect2):
	if volume_data.is_empty() or max_volume == 0:
		return

	var bar_width = chart_area.size.x / max(volume_data.size(), 1)

	for i in range(volume_data.size()):
		var data_point = volume_data[i]
		var buy_volume = data_point.get("buy_volume", 0)
		var sell_volume = data_point.get("sell_volume", 0)
		var total_volume = buy_volume + sell_volume

		if total_volume == 0:
			continue

		var x = chart_area.position.x + (i * bar_width)

		# Calculate proportional heights
		var total_bar_height = (float(total_volume) / float(max_volume)) * chart_area.size.y
		var buy_height = (float(buy_volume) / float(total_volume)) * total_bar_height
		var sell_height = total_bar_height - buy_height

		# Draw sell volume (bottom, red)
		var sell_y = chart_area.position.y + chart_area.size.y - sell_height
		var sell_rect = Rect2(x + 1, sell_y, bar_width - 2, sell_height)
		draw_rect(sell_rect, sell_volume_color)

		# Draw buy volume (top, green)
		var buy_y = sell_y - buy_height
		var buy_rect = Rect2(x + 1, buy_y, bar_width - 2, buy_height)
		draw_rect(buy_rect, buy_volume_color)

		# Add border around entire bar
		var total_rect = Rect2(x + 1, buy_y, bar_width - 2, total_bar_height)
		draw_rect(total_rect, text_color, false, 1.0)


func draw_stacked_order_bars(chart_area: Rect2):
	# Similar to buy_sell_split but with more granular order size categories
	draw_buy_sell_split_bars(chart_area)  # Fallback for now


func add_volume_data_point(timestamp: float, buy_volume: int, sell_volume: int, total_volume: int = 0):
	"""Add a new volume data point"""
	if total_volume == 0:
		total_volume = buy_volume + sell_volume

	var data_point = {"timestamp": timestamp, "buy_volume": buy_volume, "sell_volume": sell_volume, "total_volume": total_volume}

	volume_data.append(data_point)

	# Update max volume for scaling
	max_volume = max(max_volume, total_volume)

	# Keep only recent data points
	cleanup_old_data()

	queue_redraw()


func add_simple_volume_point(volume: int, timestamp: float = 0.0):
	"""Add a simple volume data point (total volume only)"""
	if timestamp == 0.0:
		timestamp = Time.get_unix_time_from_system()

	add_volume_data_point(timestamp, 0, 0, volume)


func update_volume_data(market_data: Dictionary):
	"""Update volume chart with market data"""
	var buy_volume = market_data.get("total_buy_volume", 0)
	var sell_volume = market_data.get("total_sell_volume", 0)
	var total_volume = market_data.get("volume", buy_volume + sell_volume)
	var timestamp = Time.get_unix_time_from_system()

	add_volume_data_point(timestamp, buy_volume, sell_volume, total_volume)

	print("Volume chart updated: Buy=%d, Sell=%d, Total=%d" % [buy_volume, sell_volume, total_volume])


func cleanup_old_data():
	"""Remove data points older than time_range"""
	var current_time = Time.get_unix_time_from_system()
	var cutoff_time = current_time - time_range

	volume_data = volume_data.filter(func(point): return point.get("timestamp", 0) >= cutoff_time)

	# Recalculate max_volume
	max_volume = 0
	for point in volume_data:
		max_volume = max(max_volume, point.get("total_volume", 0))


func clear_data():
	"""Clear all volume data"""
	volume_data.clear()
	max_volume = 0
	queue_redraw()


func set_display_mode(mode: VolumeDisplayMode):
	"""Change how volume is displayed"""
	display_mode = mode
	queue_redraw()


func set_time_range(seconds: float):
	"""Set the time range to display"""
	time_range = seconds
	cleanup_old_data()
	queue_redraw()


func format_volume(volume: int) -> String:
	"""Format volume numbers for display"""
	if volume >= 1000000000:
		return "%.1fB" % (volume / 1000000000.0)
	elif volume >= 1000000:
		return "%.1fM" % (volume / 1000000.0)
	elif volume >= 1000:
		return "%.1fK" % (volume / 1000.0)
	else:
		return str(volume)


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Handle clicking on volume bars
		var chart_area = Rect2(margin_left, margin_top, size.x - margin_left - margin_right, size.y - margin_top - margin_bottom)

		if chart_area.has_point(event.position):
			var bar_width = chart_area.size.x / max(volume_data.size(), 1)
			var clicked_bar = int((event.position.x - chart_area.position.x) / bar_width)

			if clicked_bar >= 0 and clicked_bar < volume_data.size():
				var data_point = volume_data[clicked_bar]
				emit_signal("volume_bar_clicked", data_point.get("timestamp", 0), data_point.get("total_volume", 0))
