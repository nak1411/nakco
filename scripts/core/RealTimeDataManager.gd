# scripts/core/RealTimeDataManager.gd
class_name RealTimeDataManager
extends Node

signal price_update(item_id: int, new_price: float, old_price: float)
signal volume_update(item_id: int, new_volume: int)
signal market_opportunity(opportunity: Dictionary)

var update_timer: Timer
var watched_items: Dictionary = {}  # item_id -> last_known_data
var update_interval: float = 5.0  # seconds

@onready var data_manager: DataManager
@onready var notification_manager: NotificationManager


func _ready():
	setup_timer()


func setup_timer():
	update_timer = Timer.new()
	add_child(update_timer)
	update_timer.wait_time = update_interval
	update_timer.timeout.connect(_on_update_timer)
	update_timer.start()


func _on_update_timer():
	update_watched_items()


func add_watched_item(item_id: int, region_id: int):
	watched_items[item_id] = {"region_id": region_id, "last_price": 0.0, "last_volume": 0, "price_history": [], "last_update": 0}


func update_watched_items():
	for item_id in watched_items.keys():
		var item_data = watched_items[item_id]
		if data_manager:
			data_manager.get_market_orders(item_data.region_id, item_id)


func process_market_update(item_id: int, market_data: Dictionary):
	if not watched_items.has(item_id):
		return

	var item_info = watched_items[item_id]
	var current_time = Time.get_ticks_msec()

	# Extract price information
	var buy_orders = []
	var sell_orders = []

	for order in market_data.get("data", []):
		if order.get("is_buy_order", false):
			buy_orders.append(order)
		else:
			sell_orders.append(order)

	# Get best prices
	var best_buy_price = get_best_buy_price(buy_orders)
	var best_sell_price = get_best_sell_price(sell_orders)

	# Check for price changes
	if best_buy_price != item_info.last_price:
		emit_signal("price_update", item_id, best_buy_price, item_info.last_price)
		item_info.last_price = best_buy_price

	# Check for trading opportunities
	check_trading_opportunities(item_id, buy_orders, sell_orders)


func get_best_buy_price(buy_orders: Array) -> float:
	var best_price = 0.0
	for order in buy_orders:
		var price = order.get("price", 0.0)
		if price > best_price:
			best_price = price
	return best_price


func get_best_sell_price(sell_orders: Array) -> float:
	var best_price = INF
	for order in sell_orders:
		var price = order.get("price", 0.0)
		if price < best_price:
			best_price = price
	return best_price if best_price != INF else 0.0


func check_trading_opportunities(item_id: int, buy_orders: Array, sell_orders: Array):
	var best_buy = get_best_buy_price(buy_orders)
	var best_sell = get_best_sell_price(sell_orders)

	if best_buy > 0 and best_sell > 0:
		var spread = best_sell - best_buy
		var margin_percent = (spread / best_buy) * 100.0

		# Alert on good opportunities (>5% margin)
		if margin_percent > 5.0:
			var opportunity = {"item_id": item_id, "buy_price": best_buy, "sell_price": best_sell, "spread": spread, "margin_percent": margin_percent, "timestamp": Time.get_ticks_msec()}
			emit_signal("market_opportunity", opportunity)
