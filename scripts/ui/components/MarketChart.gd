# scripts/ui/components/MarketChart.gd (updated)
class_name MarketChart
extends Control

signal price_level_clicked(price: float)
signal historical_data_requested

# Component references
var chart_data: ChartData
var chart_renderer: ChartRenderer
var chart_interaction: ChartInteraction
var chart_math: ChartMath
var analysis_tools: AnalysisTools

# Core data (delegated to ChartData)
var price_data: Array[Dictionary] = []
var volume_data: Array[int] = []
var candlestick_data: Array[Dictionary] = []
var time_labels: Array[String] = []

# Display settings
var show_candlesticks: bool = true
var show_support_resistance: bool = false
var show_spread_analysis: bool = true

# Chart view state (delegated to ChartInteraction)
var zoom_level: float = 1.0
var chart_center_time: float = 0.0
var chart_center_price: float = 0.0
var chart_price_range: float = 0.0


func _ready():
	custom_minimum_size = Vector2(400, 150)

	# Initialize components
	_initialize_components()
	_connect_signals()

	# Set up initial state
	chart_center_time = Time.get_unix_time_from_system()
	chart_center_price = 1000.0
	chart_price_range = 500.0

	chart_data.set_day_start_time()


func _initialize_components():
	chart_data = ChartData.new()
	chart_renderer = ChartRenderer.new()
	chart_interaction = ChartInteraction.new()
	chart_math = ChartMath.new()
	analysis_tools = AnalysisTools.new()

	# Pass references between components
	chart_renderer.setup(self, chart_data, chart_math, analysis_tools)
	chart_interaction.setup(self, chart_data, chart_math)
	analysis_tools.setup(self, chart_data, chart_math)
	chart_math.setup(self, chart_data)

	# Set up data references for easy access
	price_data = chart_data.price_data
	volume_data = chart_data.volume_data
	candlestick_data = chart_data.candlestick_data
	time_labels = chart_data.time_labels


func _connect_signals():
	mouse_entered.connect(chart_interaction._on_mouse_entered)
	mouse_exited.connect(chart_interaction._on_mouse_exited)
	resized.connect(chart_interaction._on_chart_resized)


func _draw():
	chart_renderer.draw_chart()


func _gui_input(event):
	chart_interaction.handle_input(event)


# Public API methods (delegate to appropriate components)
func add_data_point(price: float, volume: int, time_label: String = ""):
	chart_data.add_data_point(price, volume, time_label)


func add_candlestick_data_point(open: float, high: float, low: float, close: float, volume: int, timestamp: float):
	chart_data.add_candlestick_data_point(open, high, low, close, volume, timestamp)


func set_station_trading_data(data: Dictionary):
	chart_data.set_station_trading_data(data)
	if show_spread_analysis:
		analysis_tools.update_spread_analysis(data)


func get_latest_price() -> float:
	return chart_data.get_latest_price()


func get_price_change() -> float:
	return chart_data.get_price_change()


func get_price_change_percent() -> float:
	return chart_data.get_price_change_percent()


func set_chart_style(style: String):
	chart_renderer.set_chart_style(style)


func toggle_support_resistance():
	analysis_tools.toggle_support_resistance()


func toggle_spread_analysis():
	analysis_tools.toggle_spread_analysis()


func set_moving_average_period(period: int):
	analysis_tools.set_moving_average_period(period)


# Additional utility methods that were in the original
func get_timeframe_info() -> String:
	return "Market Data View"


func debug_chart_data():
	print("=== MARKET CHART DEBUG ===")
	var current_time = Time.get_unix_time_from_system()
	print("Current time: %s" % Time.get_datetime_string_from_unix_time(current_time))
	print("Price data points: %d" % chart_data.price_data.size())
	print("Volume data points: %d" % chart_data.volume_data.size())
	print("Candlestick data points: %d" % chart_data.candlestick_data.size())
	print("Zoom level: %.2f" % zoom_level)
	print("Chart center time: %.0f" % chart_center_time)
	print("Chart center price: %.2f" % chart_center_price)
	print("Chart price range: %.2f" % chart_price_range)
	print("========================")
