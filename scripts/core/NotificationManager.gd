# scripts/core/NotificationManager.gd
class_name NotificationManager
extends Node

signal notification_triggered(notification: Dictionary)

enum NotificationType { PRICE_ALERT, VOLUME_ALERT, SYSTEM_ALERT, ERROR_ALERT, SUCCESS_ALERT, OPPORTUNITY_ALERT }

var active_alerts: Array[Dictionary] = []
var sound_player: AudioStreamPlayer
var alert_history: Array[Dictionary] = []
var max_history_size: int = 100


func _ready():
	setup_audio()


func setup_audio():
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)

	# Load default notification sound
	var sound_path = "res://assets/audio/notifications/alert.ogg"
	if FileAccess.file_exists(sound_path):
		var audio_stream = load(sound_path)
		if audio_stream:
			sound_player.stream = audio_stream


func create_price_alert(item_id: int, item_name: String, target_price: float, condition: String) -> Dictionary:
	var alert = {
		"id": generate_alert_id(),
		"type": NotificationType.PRICE_ALERT,
		"item_id": item_id,
		"item_name": item_name,
		"target_price": target_price,
		"condition": condition,  # "above", "below", "equals"
		"created_time": Time.get_ticks_msec(),
		"active": true,
		"triggered": false
	}

	active_alerts.append(alert)
	print("Price alert created for %s at %s ISK" % [item_name, target_price])
	return alert


func create_volume_alert(item_id: int, item_name: String, target_volume: int, condition: String) -> Dictionary:
	var alert = {
		"id": generate_alert_id(),
		"type": NotificationType.VOLUME_ALERT,
		"item_id": item_id,
		"item_name": item_name,
		"target_volume": target_volume,
		"condition": condition,
		"created_time": Time.get_ticks_msec(),
		"active": true,
		"triggered": false
	}

	active_alerts.append(alert)
	return alert


func create_system_alert(message: String, severity: String = "info") -> Dictionary:
	var alert = {"id": generate_alert_id(), "type": NotificationType.SYSTEM_ALERT, "message": message, "severity": severity, "created_time": Time.get_ticks_msec(), "active": true}  # "info", "warning", "error", "success"

	trigger_notification(alert)
	return alert


func check_price_alerts(market_data: Dictionary):
	for alert in active_alerts:
		if alert.type != NotificationType.PRICE_ALERT or not alert.active:
			continue

		var item_id = alert.item_id
		var target_price = alert.target_price
		var condition = alert.condition

		# Check if market data contains this item
		if not market_data.has("data"):
			continue

		for order in market_data.data:
			if order.get("type_id") != item_id:
				continue

			var current_price = order.get("price", 0.0)
			var should_trigger = false

			match condition:
				"above":
					should_trigger = current_price > target_price
				"below":
					should_trigger = current_price < target_price
				"equals":
					should_trigger = abs(current_price - target_price) < (target_price * 0.01)  # 1% tolerance

			if should_trigger and not alert.triggered:
				alert.triggered = true
				alert.current_price = current_price
				trigger_notification(alert)
				break


func check_volume_alerts(market_data: Dictionary):
	for alert in active_alerts:
		if alert.type != NotificationType.VOLUME_ALERT or not alert.active:
			continue

		var item_id = alert.item_id
		var target_volume = alert.target_volume
		var condition = alert.condition

		if not market_data.has("data"):
			continue

		var total_volume = 0
		for order in market_data.data:
			if order.get("type_id") == item_id:
				total_volume += order.get("volume_remain", 0)

		var should_trigger = false
		match condition:
			"above":
				should_trigger = total_volume > target_volume
			"below":
				should_trigger = total_volume < target_volume

		if should_trigger and not alert.triggered:
			alert.triggered = true
			alert.current_volume = total_volume
			trigger_notification(alert)


func trigger_notification(notification: Dictionary):
	# Add to history
	alert_history.append(notification.duplicate())
	if alert_history.size() > max_history_size:
		alert_history.pop_front()

	# Play sound if enabled
	if ConfigManager and ConfigManager.get_setting("sound_enabled", true):
		play_notification_sound(notification.get("type", NotificationType.SYSTEM_ALERT))

	# Emit signal
	emit_signal("notification_triggered", notification)

	print("Notification triggered: ", notification.get("message", "Alert"))


func play_notification_sound(type: NotificationType):
	if not sound_player or not sound_player.stream:
		return

	# You could have different sounds for different types
	sound_player.pitch_scale = 1.0

	match type:
		NotificationType.ERROR_ALERT:
			sound_player.pitch_scale = 0.8
		NotificationType.SUCCESS_ALERT:
			sound_player.pitch_scale = 1.2
		NotificationType.PRICE_ALERT:
			sound_player.pitch_scale = 1.1

	sound_player.play()


func remove_alert(alert_id: String):
	for i in range(active_alerts.size()):
		if active_alerts[i].id == alert_id:
			active_alerts.remove_at(i)
			print("Alert removed: ", alert_id)
			break


func disable_alert(alert_id: String):
	for alert in active_alerts:
		if alert.id == alert_id:
			alert.active = false
			print("Alert disabled: ", alert_id)
			break


func enable_alert(alert_id: String):
	for alert in active_alerts:
		if alert.id == alert_id:
			alert.active = true
			alert.triggered = false  # Reset trigger state
			print("Alert enabled: ", alert_id)
			break


func get_active_alerts() -> Array[Dictionary]:
	return active_alerts.filter(func(alert): return alert.active)


func get_alert_history() -> Array[Dictionary]:
	return alert_history


func clear_triggered_alerts():
	active_alerts = active_alerts.filter(func(alert): return not alert.triggered)
	print("Cleared triggered alerts")


func generate_alert_id() -> String:
	return "alert_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
