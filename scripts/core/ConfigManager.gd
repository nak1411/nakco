# scripts/core/ConfigManager.gd
class_name ConfigManager
extends Node

signal settings_changed(setting_name: String, new_value)

const SETTINGS_FILE = "user://settings.cfg"
const DEFAULT_SETTINGS = {
	"ui_theme": "dark",  # Changed to just theme name
	"refresh_interval": 30,
	"api_cache_duration": 60,
	"auto_refresh": true,
	"sound_enabled": true,
	"notification_enabled": true,
	"default_region": 10000002,  # Jita
	"chart_style": "candlestick",
	"grid_update_interval": 5,
	"alert_volume_threshold": 1000000,
	"profit_margin_threshold": 5.0
}

var settings: Dictionary = {}
var config_file: ConfigFile
var is_loaded: bool = false


func _ready():
	config_file = ConfigFile.new()
	load_settings()


func load_settings():
	var error = config_file.load(SETTINGS_FILE)

	if error == OK:
		# Load existing settings
		for section in config_file.get_sections():
			for key in config_file.get_section_keys(section):
				var setting_key = "%s.%s" % [section, key] if section != "general" else key
				settings[setting_key] = config_file.get_value(section, key)

	# Apply defaults for missing settings
	for key in DEFAULT_SETTINGS:
		if not settings.has(key):
			settings[key] = DEFAULT_SETTINGS[key]

	is_loaded = true
	print("Settings loaded: ", settings.size(), " entries")


func save_settings():
	if not is_loaded:
		print("Warning: Attempting to save settings before they were loaded")
		return

	# Organize settings by section
	var sections = {}

	for key in settings:
		var parts = key.split(".", false, 1)
		var section = "general"
		var setting_key = key

		if parts.size() > 1:
			section = parts[0]
			setting_key = parts[1]

		if not sections.has(section):
			sections[section] = {}
		sections[section][setting_key] = settings[key]

	# Write to config file
	for section in sections:
		for key in sections[section]:
			config_file.set_value(section, key, sections[section][key])

	var error = config_file.save(SETTINGS_FILE)
	if error == OK:
		print("Settings saved successfully")
	else:
		print("Error saving settings: ", error)


func get_setting(key: String, default_value = null):
	if not is_loaded:
		print("Warning: Getting setting before ConfigManager is loaded, using default")
		return default_value if default_value != null else DEFAULT_SETTINGS.get(key)

	if settings.has(key):
		return settings[key]
	return default_value if default_value != null else DEFAULT_SETTINGS.get(key)


func set_setting(key: String, value):
	if not is_loaded:
		print("Warning: Setting value before ConfigManager is loaded")
		return

	var old_value = settings.get(key)
	settings[key] = value

	if old_value != value:
		emit_signal("settings_changed", key, value)

	# Auto-save critical settings
	if key in ["ui_theme", "default_region"]:
		save_settings()


func get_theme_path(theme_name: String) -> String:
	match theme_name:
		"dark":
			return "res://assets/themes/dark_theme.tres"
		"light":
			return "res://assets/themes/light_theme.tres"
		_:
			return "res://assets/themes/dark_theme.tres"


func reset_to_defaults():
	settings = DEFAULT_SETTINGS.duplicate()
	save_settings()
	print("Settings reset to defaults")


func export_settings() -> String:
	return JSON.stringify(settings)


func import_settings(json_string: String) -> bool:
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result == OK:
		var imported_settings = json.data
		if typeof(imported_settings) == TYPE_DICTIONARY:
			settings = imported_settings
			save_settings()
			return true

	return false
