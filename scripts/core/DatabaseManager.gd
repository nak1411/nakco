# scripts/core/DatabaseManager.gd
class_name DatabaseManager
extends Node

# Remove the problematic preload line and use this instead:
var db: SQLite
var db_path: String = "user://eve_trader.db"
var is_initialized: bool = false


func _ready():
	initialize()


func initialize() -> bool:
	# Create SQLite instance using the new API
	db = SQLite.new()

	# Set database path
	db.path = db_path

	# Open database
	if not db.open_db():
		print("Error: Could not open database at ", db_path)
		return false

	# Create tables
	create_tables()
	is_initialized = true
	print("Database initialized successfully")
	return true


func create_tables():
	# Portfolio table
	var portfolio_sql = """
	CREATE TABLE IF NOT EXISTS portfolio (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		item_name TEXT NOT NULL,
		quantity INTEGER NOT NULL,
		buy_price REAL NOT NULL,
		buy_date TEXT NOT NULL,
		region_id INTEGER NOT NULL,
		station_id INTEGER,
		notes TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)
	"""

	# Trades history table
	var trades_sql = """
	CREATE TABLE IF NOT EXISTS trades (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		item_name TEXT NOT NULL,
		trade_type TEXT NOT NULL,
		quantity INTEGER NOT NULL,
		price REAL NOT NULL,
		total_value REAL NOT NULL,
		region_id INTEGER NOT NULL,
		station_id INTEGER,
		profit_loss REAL DEFAULT 0,
		trade_date TEXT NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)
	"""

	# Watchlist table
	var watchlist_sql = """
	CREATE TABLE IF NOT EXISTS watchlist (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL UNIQUE,
		item_name TEXT NOT NULL,
		target_buy_price REAL,
		target_sell_price REAL,
		region_id INTEGER NOT NULL,
		notes TEXT,
		active BOOLEAN DEFAULT 1,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)
	"""

	# Price history cache table
	var price_history_sql = """
	CREATE TABLE IF NOT EXISTS price_history (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL,
		region_id INTEGER NOT NULL,
		date TEXT NOT NULL,
		highest REAL NOT NULL,
		lowest REAL NOT NULL,
		average REAL NOT NULL,
		volume INTEGER NOT NULL,
		order_count INTEGER NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(item_id, region_id, date)
	)
	"""

	# User settings table
	var settings_sql = """
	CREATE TABLE IF NOT EXISTS user_settings (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)
	"""

	# Execute table creation
	var tables = [portfolio_sql, trades_sql, watchlist_sql, price_history_sql, settings_sql]

	for sql in tables:
		db.query(sql)
		if db.error_message:
			print("Error creating table: ", db.error_message)


# Portfolio Management
func add_portfolio_item(item_id: int, item_name: String, quantity: int, buy_price: float, region_id: int, station_id: int = 0, notes: String = "") -> bool:
	var sql = """
	INSERT INTO portfolio (item_id, item_name, quantity, buy_price, buy_date, region_id, station_id, notes)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	"""

	var buy_date = Time.get_datetime_string_from_system()
	var bindings = [item_id, item_name, quantity, buy_price, buy_date, region_id, station_id, notes]

	db.query_with_bindings(sql, bindings)
	if not db.error_message:
		print("Added portfolio item: ", item_name)
		return true

	print("Error adding portfolio item: ", db.error_message)
	return false


func get_portfolio() -> Array[Dictionary]:
	var sql = "SELECT * FROM portfolio ORDER BY created_at DESC"
	db.query(sql)

	var portfolio: Array[Dictionary] = []

	if db.error_message:
		print("Error getting portfolio: ", db.error_message)
		return portfolio

	var query_result = db.query_result
	for row in query_result:
		portfolio.append(row)

	return portfolio


func update_portfolio_item(id: int, quantity: int, notes: String = "") -> bool:
	var sql = "UPDATE portfolio SET quantity = ?, notes = ? WHERE id = ?"
	var bindings = [quantity, notes, id]

	db.query_with_bindings(sql, bindings)
	return not db.error_message


func remove_portfolio_item(id: int) -> bool:
	var sql = "DELETE FROM portfolio WHERE id = ?"
	db.query_with_bindings(sql, [id])
	return not db.error_message


# Trade History Management
func add_trade(item_id: int, item_name: String, trade_type: String, quantity: int, price: float, region_id: int, station_id: int = 0, profit_loss: float = 0.0) -> bool:
	var sql = """
	INSERT INTO trades (item_id, item_name, trade_type, quantity, price, total_value, region_id, station_id, profit_loss, trade_date)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""

	var total_value = quantity * price
	var trade_date = Time.get_datetime_string_from_system()
	var bindings = [item_id, item_name, trade_type, quantity, price, total_value, region_id, station_id, profit_loss, trade_date]

	db.query_with_bindings(sql, bindings)
	if not db.error_message:
		print("Added trade: ", trade_type, " ", quantity, "x ", item_name)
		return true

	print("Error adding trade: ", db.error_message)
	return false


func get_trade_history(limit: int = 100) -> Array[Dictionary]:
	var sql = "SELECT * FROM trades ORDER BY created_at DESC LIMIT ?"
	db.query_with_bindings(sql, [limit])

	var trades: Array[Dictionary] = []

	if db.error_message:
		print("Error getting trade history: ", db.error_message)
		return trades

	var query_result = db.query_result
	for row in query_result:
		trades.append(row)

	return trades


func get_trade_statistics() -> Dictionary:
	var stats = {"total_trades": 0, "total_profit": 0.0, "total_volume": 0.0, "best_trade": 0.0, "worst_trade": 0.0}

	var sql = """
	SELECT 
		COUNT(*) as total_trades,
		SUM(profit_loss) as total_profit,
		SUM(total_value) as total_volume,
		MAX(profit_loss) as best_trade,
		MIN(profit_loss) as worst_trade
	FROM trades
	"""

	db.query(sql)
	if not db.error_message and db.query_result.size() > 0:
		stats = db.query_result[0]

	return stats


# Watchlist Management
func add_watchlist_item(item_id: int, item_name: String, region_id: int, target_buy_price: float = 0.0, target_sell_price: float = 0.0, notes: String = "") -> bool:
	var sql = """
	INSERT OR REPLACE INTO watchlist (item_id, item_name, target_buy_price, target_sell_price, region_id, notes)
	VALUES (?, ?, ?, ?, ?, ?)
	"""

	var bindings = [item_id, item_name, target_buy_price, target_sell_price, region_id, notes]

	db.query_with_bindings(sql, bindings)
	if not db.error_message:
		print("Added to watchlist: ", item_name)
		return true

	print("Error adding to watchlist: ", db.error_message)
	return false


func get_watchlist() -> Array[Dictionary]:
	var sql = "SELECT * FROM watchlist WHERE active = 1 ORDER BY created_at DESC"
	db.query(sql)

	var watchlist: Array[Dictionary] = []

	if db.error_message:
		print("Error getting watchlist: ", db.error_message)
		return watchlist

	var query_result = db.query_result
	for row in query_result:
		watchlist.append(row)

	return watchlist


func remove_watchlist_item(item_id: int) -> bool:
	var sql = "UPDATE watchlist SET active = 0 WHERE item_id = ?"
	db.query_with_bindings(sql, [item_id])
	return not db.error_message


# Price History Management
func cache_price_history(item_id: int, region_id: int, history_data: Array):
	for day_data in history_data:
		var sql = """
		INSERT OR REPLACE INTO price_history 
		(item_id, region_id, date, highest, lowest, average, volume, order_count)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		"""

		var bindings = [
			item_id,
			region_id,
			day_data.get("date", ""),
			day_data.get("highest", 0.0),
			day_data.get("lowest", 0.0),
			day_data.get("average", 0.0),
			day_data.get("volume", 0),
			day_data.get("order_count", 0)
		]

		db.query_with_bindings(sql, bindings)


func get_cached_price_history(item_id: int, region_id: int, days: int = 30) -> Array[Dictionary]:
	var sql = """
	SELECT * FROM price_history 
	WHERE item_id = ? AND region_id = ?
	ORDER BY date DESC LIMIT ?
	"""

	db.query_with_bindings(sql, [item_id, region_id, days])

	var history: Array[Dictionary] = []

	if db.error_message:
		print("Error getting price history: ", db.error_message)
		return history

	var query_result = db.query_result
	for row in query_result:
		history.append(row)

	return history


# Utility Methods
func close():
	if db:
		db.close_db()
		print("Database connection closed")


func backup_database(backup_path: String) -> bool:
	if not is_initialized:
		return false

	# Simple file copy for backup
	var file = FileAccess.open(db_path, FileAccess.READ)
	if not file:
		return false

	var backup_file = FileAccess.open(backup_path, FileAccess.WRITE)
	if not backup_file:
		file.close()
		return false

	backup_file.store_buffer(file.get_buffer(file.get_length()))
	file.close()
	backup_file.close()

	print("Database backed up to: ", backup_path)
	return true


func get_database_size() -> int:
	var file = FileAccess.open(db_path, FileAccess.READ)
	if file:
		var size = file.get_length()
		file.close()
		return size
	return 0
