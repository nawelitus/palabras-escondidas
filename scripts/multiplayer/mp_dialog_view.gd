class_name MpDialogView
extends MpPanel
## A small message with one or two buttons: "the room was closed", "leave the room?".

signal accepted
signal cancelled

var _message_label: Label
var _accept_button: Button
var _cancel_button: Button


func _init() -> void:
	super("", true)
	_message_label = make_label("", 30, true)
	body.add_child(_message_label)
	_accept_button = make_button("Aceptar", 32, 84)
	_accept_button.pressed.connect(func() -> void:
		hide_panel()
		accepted.emit())
	footer.add_child(_accept_button)
	_cancel_button = make_button("Cancelar", 28, 72)
	_cancel_button.pressed.connect(func() -> void:
		hide_panel()
		cancelled.emit())
	footer.add_child(_cancel_button)


## cancel_text empty = a single-button message.
func ask(title: String, message: String, accept_text: String = "Aceptar", cancel_text: String = "") -> void:
	title_label.text = title
	_message_label.text = message
	_accept_button.text = accept_text
	_cancel_button.text = cancel_text
	_cancel_button.visible = not cancel_text.is_empty()
	show_panel()
