#!###########################################################################################
#!																							#
#!         THIS SCRIPT CONTAINS CODE THAT IS THE INTELLECTUAL PROPERTY OF CANDY ARTS        #
#!                             Copyright © 2025-2026 Candy Arts                             #
#!																							#
#!    Such code may only be used in compliance with the appropriate Candy Arts licenses.    #
#!                 Any unauthorized use constitutes copyright infringement.                 #
#!																							#
#!   This disclaimer must be featured at the top of any script featuring Candy Arts code,   #
#!                            and may not be removed or modified.                           #
#!																							#
#!###########################################################################################


@tool
extends VBoxContainer


const DBSettings = preload("Database_Settings.gd")
const Library = preload("Database_Library.gd")

const MIN_TEXT_MARGIN := 24
const MARKER_WIDTH := 4

#* Any click in the pane (selects the pane the margin and About menu act on):
signal activated
#* A page, header or footer link was clicked:
signal link_clicked(target: String)
#* Page text shown again (new page, message or redraw):
signal content_changed

var current_page := ""
var history: Array[String] = []
var history_index := -1

var bar: PanelContainer
var bar_row: HBoxContainer
var marker: ColorRect
var back_button: Button
var forward_button: Button
var close_button: Button
var reader: Control
var background_rect: ColorRect
var texture_rect: TextureRect
var column: VBoxContainer
var scroll_box: ScrollContainer
var content_box: VBoxContainer
var header_holder: PanelContainer
var header_background: ColorRect
var header_texture_rect: TextureRect
var header_label: RichTextLabel
var header_box := StyleBoxEmpty.new()
var label: RichTextLabel
var label_box := StyleBoxEmpty.new()
#^ Pushes a scrolling footer to the bottom of a short page:
var footer_spacer: Control
var footer_holder: PanelContainer
var footer_background: ColorRect
var footer_texture_rect: TextureRect
var footer_label: RichTextLabel
var footer_box := StyleBoxEmpty.new()
#^ Header scrolls with the page (database's choice), or is pinned above it (pin_header()):
var header_scrolls := true
var header_pinned := false
#^ Footer scrolls with the page (database's choice), or is pinned below it (pin_footer()):
var footer_scrolls := true
var footer_pinned := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(240, 0)
	add_theme_constant_override("separation", 0)

	bar = PanelContainer.new()
	bar.theme_type_variation = "ToolbarPanel"
	add_child(bar)
	bar_row = HBoxContainer.new()
	bar.add_child(bar_row)
	#Ł Pane color marker, shown when there are two panes:
	marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(MARKER_WIDTH, 0)
	marker.visible = false
	bar_row.add_child(marker)
	back_button = _add_button(bar_row, "Back")
	forward_button = _add_button(bar_row, "Forward")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(spacer)
	close_button = _add_button(bar_row, "Close this page")
	close_button.visible = false

	reader = Control.new()
	reader.clip_contents = true
	reader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reader.resized.connect(update_margins)
	add_child(reader)
	background_rect = ColorRect.new()
	reader.add_child(background_rect)
	texture_rect = TextureRect.new()
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reader.add_child(texture_rect)
	#? The header and footer go in the scroll container (scroll) or the column around it (fixed), see set_header_scrolls() and set_footer_scrolls().
	#? The label fits its content; the container scrolls.
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	reader.add_child(column)
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll_box)
	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#? Fills the page's height when the text is shorter, so the footer_spacer can push the footer down.
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 0)
	scroll_box.add_child(content_box)
	var header := _add_band(content_box, header_box)
	header_holder = header["holder"]
	header_background = header["background"]
	header_texture_rect = header["texture_rect"]
	header_label = header["label"]
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.meta_underlined = false
	label.fit_content = true
	label.scroll_active = false
	label.add_theme_stylebox_override("normal", label_box)
	label.meta_clicked.connect(func(meta: Variant) -> void: link_clicked.emit(str(meta)))
	content_box.add_child(label)
	footer_spacer = Control.new()
	footer_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	footer_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	content_box.add_child(footer_spacer)
	var footer := _add_band(content_box, footer_box)
	footer_holder = footer["holder"]
	footer_background = footer["background"]
	footer_texture_rect = footer["texture_rect"]
	footer_label = footer["label"]
	for control: Control in [background_rect, texture_rect, column]:
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for control: Control in [bar, scroll_box, header_label, label, footer_label]:
		control.gui_input.connect(_on_gui_input)


#* A header or footer, hidden until shown. Returns {"holder", "background", "texture_rect", "label"}:
#? PanelContainer stacks the background and image behind the text, at the text's height.
func _add_band(parent: Control, box: StyleBoxEmpty) -> Dictionary:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	holder.visible = false
	parent.add_child(holder)
	var background := ColorRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(background)
	var band_texture_rect := TextureRect.new()
	band_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(band_texture_rect)
	var band_label := RichTextLabel.new()
	band_label.bbcode_enabled = true
	band_label.fit_content = true
	band_label.scroll_active = false
	band_label.selection_enabled = true
	#? Links are underlined by the view ([u]), so linked images aren't.
	band_label.meta_underlined = false
	band_label.add_theme_stylebox_override("normal", box)
	band_label.meta_clicked.connect(func(meta: Variant) -> void: link_clicked.emit(str(meta)))
	holder.add_child(band_label)
	return {"holder": holder, "background": background, "texture_rect": band_texture_rect, "label": band_label}


func _ready() -> void:
	back_button.icon = get_theme_icon("Back", "EditorIcons")
	forward_button.icon = get_theme_icon("Forward", "EditorIcons")
	close_button.icon = get_theme_icon("Close", "EditorIcons")


func _add_button(row: HBoxContainer, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.tooltip_text = tooltip
	row.add_child(button)
	return button


#* Clicks only - the mouse wheel is a button press too, and scrolling must not change the active pane:
func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		activated.emit()


# ---------------------------------------------------------------- History

#* Add a page after the current one, dropping forward history:
func record(page_id: String) -> void:
	history = history.slice(0, history_index + 1)
	history.append(page_id)
	history_index = history.size() - 1


func clear_history() -> void:
	history.clear()
	history_index = -1
	update_buttons()


func can_go_back() -> bool:
	return history_index > 0


func can_go_forward() -> bool:
	return history_index < history.size() - 1


func update_buttons() -> void:
	back_button.disabled = not can_go_back()
	forward_button.disabled = not can_go_forward()


# ---------------------------------------------------------------- Display

func show_text(bbcode: String) -> void:
	#! Back to the top before the text changes: scrolling while the label resizes leaves the scroll bar at the old page's height.
	scroll_box.scroll_vertical = 0
	label.text = Library.disarm(bbcode)
	content_changed.emit()


#* Show new text for the same page, keeping the scroll position:
func update_text(bbcode: String) -> void:
	var scroll := scroll_box.scroll_vertical
	label.text = Library.disarm(bbcode)
	scroll_box.set_deferred("scroll_vertical", scroll)
	content_changed.emit()


#* Show a message instead of a page:
func show_message(bbcode: String) -> void:
	current_page = ""
	show_text(bbcode)
	update_buttons()


#* Add a mod's control to the bar, before the close button:
func add_bar_control(control: Control) -> void:
	bar_row.add_child(control)
	bar_row.move_child(control, close_button.get_index())


#* Show the header with this text, or hide it:
func show_header(bbcode: String, shown: bool) -> void:
	header_holder.visible = shown
	if shown:
		header_label.text = Library.disarm(bbcode)


#* Whether the header scrolls with the page or stays fixed above it:
func set_header_scrolls(scrolls: bool) -> void:
	header_scrolls = scrolls
	_place_header()


#* Pin the header above the page, whatever the database asks:
#? For a mod replacing the page with something that scrolls on its own (an editor).
func pin_header(pinned: bool) -> void:
	header_pinned = pinned
	_place_header()


func _place_header() -> void:
	var wanted_parent: Node = column
	if header_scrolls and not header_pinned:
		wanted_parent = content_box
	if header_holder.get_parent() != wanted_parent:
		header_holder.get_parent().remove_child(header_holder)
		wanted_parent.add_child(header_holder)
	wanted_parent.move_child(header_holder, 0)


#* Show the footer with this text, or hide it:
func show_footer(bbcode: String, shown: bool) -> void:
	footer_holder.visible = shown
	if shown:
		footer_label.text = Library.disarm(bbcode)


#* Whether the footer scrolls with the page or stays fixed below it:
func set_footer_scrolls(scrolls: bool) -> void:
	footer_scrolls = scrolls
	_place_footer()


#* Pin the footer below the page, whatever the database asks:
#? For a mod replacing the page with something that scrolls on its own (an editor). Call it after adding that control to the column, so the footer goes below it.
func pin_footer(pinned: bool) -> void:
	footer_pinned = pinned
	_place_footer()


#* The footer goes last, in the scrolled content or in the column:
func _place_footer() -> void:
	var wanted_parent: Node = column
	if footer_scrolls and not footer_pinned:
		wanted_parent = content_box
	if footer_holder.get_parent() != wanted_parent:
		footer_holder.get_parent().remove_child(footer_holder)
		wanted_parent.add_child(footer_holder)
	wanted_parent.move_child(footer_holder, -1)


#* Close button - shown while another page is open beside this one:
func set_closable(closable: bool) -> void:
	close_button.visible = closable


#* Pane color in the bar; transparent hides it:
func set_marker(color: Color) -> void:
	marker.visible = color.a > 0.0
	marker.color = color


func content_width() -> int:
	return int(label.size.x - label_box.content_margin_left - label_box.content_margin_right)


func update_margins() -> void:
	var margin := MIN_TEXT_MARGIN
	var limit := int(DBSettings.get_value("max_text_width"))
	if limit > 0:
		margin = maxi(MIN_TEXT_MARGIN, int((reader.size.x - limit) / 2.0))
	label_box.content_margin_left = margin
	label_box.content_margin_right = margin
	label_box.content_margin_top = 20
	label_box.content_margin_bottom = 20
	header_box.content_margin_left = margin
	header_box.content_margin_right = margin
	header_box.content_margin_top = 12
	header_box.content_margin_bottom = 4
	footer_box.content_margin_left = margin
	footer_box.content_margin_right = margin
	footer_box.content_margin_top = 4
	footer_box.content_margin_bottom = 12


func set_font_size(size_value: int) -> void:
	for font_name in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		label.add_theme_font_size_override(font_name, size_value)
		header_label.add_theme_font_size_override(font_name, size_value)
		footer_label.add_theme_font_size_override(font_name, size_value)
	update_margins()


#* Page colors and background (from DBSettings.resolve_style()):
func apply_style(style: Dictionary) -> void:
	var text_color: Color = style["text_color"]
	background_rect.color = style["background_color"]
	var texture: Texture2D = style["texture"]
	texture_rect.texture = texture
	texture_rect.visible = texture != null
	texture_rect.modulate.a = style["opacity"]
	_set_fit(texture_rect, style["texture_mode"])
	_set_label_colors(label, text_color)
	_apply_band_style(style, "header", header_background, header_texture_rect, header_label, text_color)
	_apply_band_style(style, "footer", footer_background, footer_texture_rect, footer_label, text_color)
	_set_scroll_bar_look(style, text_color)


#* A header's or footer's background and text color; transparent colors are the page's:
#? band - "header" or "footer", the start of its style keys.
func _apply_band_style(style: Dictionary, band: String, background: ColorRect, band_texture_rect: TextureRect, band_label: RichTextLabel, text_color: Color) -> void:
	var band_texture: Texture2D = style[band + "_texture"]
	background.color = style[band + "_background_color"]
	band_texture_rect.texture = band_texture
	band_texture_rect.visible = band_texture != null
	_set_fit(band_texture_rect, style[band + "_texture_mode"])
	var band_text_color: Color = style[band + "_text_color"]
	if band_text_color.a == 0.0:
		band_text_color = text_color
	_set_label_colors(band_label, band_text_color)


func _set_fit(rect: TextureRect, mode: String) -> void:
	match mode:
		"Tile":
			rect.stretch_mode = TextureRect.STRETCH_TILE
		"Stretch":
			rect.stretch_mode = TextureRect.STRETCH_SCALE
		_:
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


func _set_label_colors(text_label: RichTextLabel, text_color: Color) -> void:
	text_label.add_theme_color_override("default_color", text_color)
	text_label.add_theme_color_override("table_border", Color(text_color, 0.35))
	text_label.add_theme_color_override("table_odd_row_bg", Color(text_color, 0.06))
	text_label.add_theme_color_override("table_even_row_bg", Color(text_color, 0.0))


#* Page scroll bar from the style's scroll_bar_ keys (the editor's is too faint over most pages):
func _set_scroll_bar_look(style: Dictionary, text_color: Color) -> void:
	#Ł Transparent colors made from the text color, hover and pressed from the grabber's:
	var track: Color = style["scroll_bar_color"]
	if track.a == 0.0:
		track = Color(text_color, 0.08)
	var grabber: Color = style["scroll_grabber_color"]
	var hover: Color = style["scroll_grabber_hover_color"]
	var pressed: Color = style["scroll_grabber_pressed_color"]
	if grabber.a == 0.0:
		grabber = Color(text_color, 0.35)
		if hover.a == 0.0:
			hover = Color(text_color, 0.5)
		if pressed.a == 0.0:
			pressed = Color(text_color, 0.65)
	if hover.a == 0.0:
		hover = grabber.lerp(text_color, 0.25)
	if pressed.a == 0.0:
		pressed = grabber.lerp(text_color, 0.45)
	var width: int = style["scroll_bar_width"]
	var radius: int = style["scroll_bar_radius"]
	var bar_node := scroll_box.get_v_scroll_bar()
	bar_node.add_theme_stylebox_override("scroll", _scroll_bar_box(track, width, radius))
	bar_node.add_theme_stylebox_override("scroll_focus", _scroll_bar_box(track, width, radius))
	bar_node.add_theme_stylebox_override("grabber", _scroll_bar_box(grabber, width, radius))
	bar_node.add_theme_stylebox_override("grabber_highlight", _scroll_bar_box(hover, width, radius))
	bar_node.add_theme_stylebox_override("grabber_pressed", _scroll_bar_box(pressed, width, radius))


#* Scroll bar box - its margins give the bar its width:
func _scroll_bar_box(color: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = width / 2.0
	box.content_margin_right = width - width / 2.0
	return box
