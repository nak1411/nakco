# scripts/ui/components/chart/ChartData.gd
class_name ChartData
extends RefCounted

var parent_chart: MarketChart

# Data storage
var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var candlestick_data: Array[Dictionary] = []
var time_labels: Array[String] = []
var current_station_trading_data: Dictionary = {}
var price_history: Array[float] = []

# Data limits and settings
var max_data_points: int = 365
var timeframe_hours: float = 8760.0  # 1 year timeframe (365 * 24)
var data_retention_seconds: float = 31536000.0  # 1 year in seconds
var base_time_window: float = 31536000.0  # 1 year in seconds
var max_data_retention: float = 31536000.0  # 1 year in seconds
var day_start_timestamp: float = 0.0
var current_day_data: Array = []
var has_loaded_historical: bool = false
var is_loading_historical: bool = false


func setup(chart: MarketChart):
	parent_chart = chart


func add_data_point(price: float, volume: int, time_label: String = ""):
	print("=== ADDING REAL-TIME DATA POINT ===")
	print("Price: %.2f, Volume: %d" % [price, volume])

	var current_time = Time.get_unix_time_from_system()
	var max_age = max_data_retention
	var oldest_allowed = current_time - max_age

	if current_time < oldest_allowed or current_time > Time.get_unix_time_from_system() + 3600:
		print("Data point rejected: outside time window")
		return

	var data_point = {"price": price, "timestamp": current_time, "volume": volume, "is_historical": false}

	price_data.append(data_point)
	volume_data.append(volume)
	price_history.append(price)

	if time_label != "":
		time_labels.append(time_label)
	else:
		time_labels.append(Time.get_datetime_string_from_unix_time(current_time))

	# Keep data sorted by timestamp
	price_data.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	cleanup_old_data()

	if parent_chart:
		parent_chart.queue_redraw()


func add_candlestick_data_point(open: float, high: float, low: float, close: float, volume: int, timestamp: float):
	var current_time = Time.get_unix_time_from_system()
	var max_age = max_data_retention
	var oldest_allowed = current_time - max_age

	if timestamp < oldest_allowed or timestamp > current_time:
		print("Candlestick data point rejected: outside time window")
		return

	var candle_data = {"open": open, "high": high, "low": low, "close": close, "volume": volume, "timestamp": timestamp, "is_historical": true}

	candlestick_data.append(candle_data)
	candlestick_data.sort_custom(func(a, b): return a.timestamp < b.timestamp)

	# Clean up old candlestick data
	while candlestick_data.size() > 0 and candlestick_data[0].timestamp < oldest_allowed:
		candlestick_data.pop_front()


func set_station_trading_data(data: Dictionary):
	current_station_trading_data = data


func cleanup_old_data():
	var current_time = Time.get_unix_time_from_system()
	var cutoff_time = current_time - max_data_retention

	var removed_count = 0

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
		print("Cleaned up %d data points older than 1 year" % removed_count)


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

	var historical_max = 0

	for i in range(min(volume_data.size(), price_data.size())):
		var vol = volume_data[i]
		if price_data[i].get("is_historical", false):
			if vol > historical_max:
				historical_max = vol

	if historical_max == 0:
		for vol in volume_data:
			if vol > historical_max:
				historical_max = vol

	return historical_max


func set_day_start_time():
	var current_time = Time.get_unix_time_from_system()
	day_start_timestamp = current_time - 31536000.0  # Start exactly 1 year ago
	has_loaded_historical = false

	print("Chart window set to show last 1 year")
	print("Start time: ", Time.get_datetime_string_from_unix_time(day_start_timestamp))
	print("End time: ", Time.get_datetime_string_from_unix_time(current_time))


func clear_all_data():
	"""Clear all data arrays"""
	price_data.clear()
	volume_data.clear()
	candlestick_data.clear()
	time_labels.clear()
	current_station_trading_data.clear()
	price_history.clear()

	# Reset flags
	has_loaded_historical = false
	is_loading_historical = false

	print("ChartData: All data cleared")
