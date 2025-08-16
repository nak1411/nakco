# scripts/ui/dialogs/PriceAlertDialog.gd
class_name PriceAlertDialog
extends AcceptDialog

signal alert_created(alert_data: Dictionary)

var current_item_id: int = 0
var current_item_name: String = ""

@onready var item_name_label: Label
@onready var price_input: SpinBox
@onready var condition_selector: OptionButton
@onready var notes_input: TextEdit


func _ready():
	setup_dialog()


func setup_dialog():
	title = "Create Price Alert"

	var vbox = VBoxContainer.new()
	add_child(vbox)

	# Item info
	item_name_label = Label.new()
	item_name_label.text = "No item selected"
	vbox.add_child(item_name_label)

	# Price input
	var price_container = HBoxContainer.new()
	vbox.add_child(price_container)

	var price_label = Label.new()
	price_label.text = "Target Price:"
	price_container.add_child(price_label)

	price_input = SpinBox.new()
	price_input.min_value = 0.01
	price_input.max_value = 999999999999.0
	price_input.step = 0.01
	price_container.add_child(price_input)

	# Condition selector
	var condition_container = HBoxContainer.new()
	vbox.add_child(condition_container)

	var condition_label = Label.new()
	condition_label.text = "Condition:"
	condition_container.add_child(condition_label)

	condition_selector = OptionButton.new()
	condition_selector.add_item("Price goes above")
	condition_selector.add_item("Price goes below")
	condition_container.add_child(condition_selector)

	# Notes
	var notes_label = Label.new()
	notes_label.text = "Notes (optional):"
	vbox.add_child(notes_label)

	notes_input = TextEdit.new()
	notes_input.custom_minimum_size.y = 60
	notes_input.placeholder_text = "Add notes about this alert..."
	vbox.add_child(notes_input)

	# Buttons
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)

	var create_button = Button.new()
	create_button.text = "Create Alert"
	create_button.pressed.connect(_on_create_alert)
	button_container.add_child(create_button)

	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(hide)
	button_container.add_child(cancel_button)


func show_for_item(item_id: int, item_name: String, current_price: float = 0.0):
	current_item_id = item_id
	current_item_name = item_name

	item_name_label.text = "Alert for: %s (ID: %d)" % [item_name, item_id]
	price_input.value = current_price

	popup_centered()


func _on_create_alert():
	var condition_text = "above" if condition_selector.selected == 0 else "below"

	var alert_data = {"item_id": current_item_id, "item_name": current_item_name, "target_price": price_input.value, "condition": condition_text, "notes": notes_input.text}

	emit_signal("alert_created", alert_data)
	hide()
