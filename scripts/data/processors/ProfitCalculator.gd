# scripts/data/processors/ProfitCalculator.gd
class_name ProfitCalculator
extends RefCounted

# EVE Online skill IDs for trading
const SKILL_BROKER_RELATIONS = 3446
const SKILL_ACCOUNTING = 16622
const SKILL_TRADE = 3443
const SKILL_RETAIL = 16598
const SKILL_MARKETING = 3444

# Base tax rates (before skill reductions)
const BASE_BROKER_FEE_RATE = 0.03  # 3% base broker fee
const BASE_SALES_TAX_RATE = 0.02  # 2% base sales tax
const BASE_TRANSACTION_TAX_RATE = 0.0

# Maximum skill reductions
const MAX_BROKER_FEE_REDUCTION = 0.005  # 0.5% total reduction (0.3% per level of Broker Relations)
const MAX_ACCOUNTING_REDUCTION = 0.005  # 0.5% total reduction (0.2% per level of Accounting)


## Calculate skill-adjusted trading fees based on character skills
# Replace the calculate_trading_fees function in ProfitCalculator.gd
static func calculate_trading_fees(character_skills: Dictionary) -> Dictionary:
	var broker_relations_level = character_skills.get("broker_relations", 0)
	var accounting_level = character_skills.get("accounting", 0)

	# Correct EVE skill reductions
	var broker_fee_reduction = min(broker_relations_level * 0.001, MAX_BROKER_FEE_REDUCTION)  # 0.1% per level
	var sales_tax_reduction = min(accounting_level * 0.001, MAX_ACCOUNTING_REDUCTION)  # 0.1% per level

	var adjusted_broker_fee = max(BASE_BROKER_FEE_RATE - broker_fee_reduction, 0.025)  # Min 2.5%
	var adjusted_sales_tax = max(BASE_SALES_TAX_RATE - sales_tax_reduction, 0.015)  # Min 1.5%

	return {
		"broker_fee_rate": adjusted_broker_fee,
		"sales_tax_rate": adjusted_sales_tax,
		"transaction_tax_rate": 0.0,  # No separate transaction tax
		"broker_relations_level": broker_relations_level,
		"accounting_level": accounting_level
	}


# Replace the calculate_station_trading_profit function in ProfitCalculator.gd
static func calculate_station_trading_profit(buy_price: float, sell_price: float, character_skills: Dictionary, volume: int = 1) -> Dictionary:
	var fees = calculate_trading_fees(character_skills)

	# 🔥 FIX: Correct fee application
	# When you BUY: pay broker fee + transaction tax on purchase
	var buy_broker_fee = buy_price * fees.broker_fee_rate
	var buy_transaction_tax = buy_price * fees.transaction_tax_rate
	var total_buy_cost = buy_price + buy_broker_fee + buy_transaction_tax

	# When you SELL: pay broker fee + sales tax, get net income
	var sell_broker_fee = sell_price * fees.broker_fee_rate
	var sell_sales_tax = sell_price * fees.sales_tax_rate
	var total_sell_income = sell_price - sell_broker_fee - sell_sales_tax

	# Profit calculation
	var profit_per_unit = total_sell_income - total_buy_cost
	var profit_margin = (profit_per_unit / total_buy_cost) * 100.0 if total_buy_cost > 0 else 0.0

	print("=== PROFIT DEBUG ===")
	print("Buy: %.2f + fees %.2f = %.2f total cost" % [buy_price, buy_broker_fee + buy_transaction_tax, total_buy_cost])
	print("Sell: %.2f - fees %.2f = %.2f net income" % [sell_price, sell_broker_fee + sell_sales_tax, total_sell_income])
	print("Profit: %.2f ISK (%.2f%% margin)" % [profit_per_unit, profit_margin])

	# Calculate for specified volume
	var total_cost = total_buy_cost * volume
	var total_income = total_sell_income * volume
	var total_profit = profit_per_unit * volume

	return {
		"buy_price": buy_price,
		"sell_price": sell_price,
		"volume": volume,
		"cost_per_unit": total_buy_cost,
		"income_per_unit": total_sell_income,
		"profit_per_unit": profit_per_unit,
		"profit_margin": profit_margin,
		"total_cost": total_cost,
		"total_income": total_income,
		"total_profit": total_profit,
		"fees": fees,
		"skill_savings": _calculate_skill_savings(character_skills)
	}


## Calculate optimal trading prices based on market conditions and skills
static func calculate_optimal_trading_prices(current_buy_orders: Array, current_sell_orders: Array, character_skills: Dictionary) -> Dictionary:
	if current_buy_orders.is_empty() or current_sell_orders.is_empty():
		return {}

	# Sort orders to get best prices
	var sorted_buy_orders = current_buy_orders.duplicate()
	var sorted_sell_orders = current_sell_orders.duplicate()

	sorted_buy_orders.sort_custom(func(a, b): return a.get("price", 0.0) > b.get("price", 0.0))
	sorted_sell_orders.sort_custom(func(a, b): return a.get("price", 0.0) < b.get("price", 0.0))

	var current_highest_buy = sorted_buy_orders[0].get("price", 0.0)
	var current_lowest_sell = sorted_sell_orders[0].get("price", 0.0)

	# Check for profitable gap
	var market_gap = current_lowest_sell - current_highest_buy
	if market_gap <= 0:
		return {"has_opportunity": false, "reason": "No market gap - orders overlap"}

	# Calculate competitive prices
	var price_increment = max(market_gap * 0.01, 0.01)  # 1% of gap or minimum 0.01 ISK
	var your_buy_price = current_highest_buy + price_increment
	var your_sell_price = current_lowest_sell - price_increment

	# Calculate profit with character skills
	var profit_calc = calculate_station_trading_profit(your_buy_price, your_sell_price, character_skills)

	var result = profit_calc.duplicate()
	result["current_highest_buy"] = current_highest_buy
	result["current_lowest_sell"] = current_lowest_sell
	result["market_gap"] = market_gap
	result["your_buy_price"] = your_buy_price
	result["your_sell_price"] = your_sell_price

	# 🔥 FIX: Use a much lower threshold for ANY positive profit
	result["has_opportunity"] = profit_calc.profit_per_unit > 0  # ANY positive profit!

	if not result["has_opportunity"]:
		result["reason"] = "Negative profit after fees (%.2f ISK per unit)" % profit_calc.profit_per_unit

	return result


## Calculate how much ISK is saved due to character skills vs default rates
static func _calculate_skill_savings(character_skills: Dictionary) -> Dictionary:
	var base_fees = {"broker_fee_rate": BASE_BROKER_FEE_RATE, "sales_tax_rate": BASE_SALES_TAX_RATE, "transaction_tax_rate": BASE_TRANSACTION_TAX_RATE}
	var skilled_fees = calculate_trading_fees(character_skills)

	var broker_fee_savings = base_fees.broker_fee_rate - skilled_fees.broker_fee_rate
	var sales_tax_savings = base_fees.sales_tax_rate - skilled_fees.sales_tax_rate

	return {"broker_fee_savings_pct": broker_fee_savings * 100.0, "sales_tax_savings_pct": sales_tax_savings * 100.0, "total_fee_savings_pct": (broker_fee_savings + sales_tax_savings) * 100.0}


## Calculate regional arbitrage profit (buy in one region, sell in another)
static func calculate_arbitrage_profit(buy_region_price: float, sell_region_price: float, character_skills: Dictionary, transport_cost: float = 0.0, volume: int = 1) -> Dictionary:
	var fees = calculate_trading_fees(character_skills)

	# Buy costs (including transport)
	var cost_per_unit = (buy_region_price * (1.0 + fees.broker_fee_rate + fees.transaction_tax_rate)) + transport_cost

	# Sell income
	var income_per_unit = sell_region_price * (1.0 - fees.sales_tax_rate - fees.broker_fee_rate)

	# Profit calculations
	var profit_per_unit = income_per_unit - cost_per_unit
	var profit_margin = (profit_per_unit / cost_per_unit) * 100.0 if cost_per_unit > 0 else 0.0

	return {
		"buy_price": buy_region_price,
		"sell_price": sell_region_price,
		"transport_cost": transport_cost,
		"volume": volume,
		"cost_per_unit": cost_per_unit,
		"income_per_unit": income_per_unit,
		"profit_per_unit": profit_per_unit,
		"profit_margin": profit_margin,
		"total_profit": profit_per_unit * volume,
		"fees": fees
	}


## Format ISK values for display
static func format_isk(value: float) -> String:
	if value >= 1000000000000:
		return "%.2fT ISK" % (value / 1000000000000.0)
	if value >= 1000000000:
		return "%.2fB ISK" % (value / 1000000000.0)
	if value >= 1000000:
		return "%.2fM ISK" % (value / 1000000.0)
	if value >= 1000:
		return "%.2fK ISK" % (value / 1000.0)
	return "%.2f ISK" % value
