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
extends AcceptDialog


const DBSettings = preload("Database_Settings.gd")

signal settings_changed
#* Preferred language changed - show the open database in it:
signal language_changed

#^ Top-level tabs (the standard settings, then each mod's), and the standard settings' sub-tabs:
var tabs: TabContainer
var standard_tabs: TabContainer
var language_edit: LineEdit
var tab_name_edit: LineEdit
var sidebar_option: OptionButton
var font_size_box: SpinBox
var width_box: SpinBox
var split_colors_check: CheckBox
var second_color_picker: ColorPickerButton
var second_side_option: OptionButton
var background_picker: ColorPickerButton
var text_picker: ColorPickerButton
var link_picker: ColorPickerButton
var code_picker: ColorPickerButton
var texture_edit: LineEdit
#^ The header's and footer's background controls, by band ("header", "footer") - {"picker", "auto_check", "texture_edit", "mode_option"}:
var band_controls: Dictionary = {}
var texture_target_key := ""
var texture_target_edit: LineEdit = null
var mode_option: OptionButton
var opacity_slider: HSlider
var database_list: VBoxContainer
var file_dialog: FileDialog
var ignore_themes_check: CheckBox
var theme_option: OptionButton
var theme_ids: Array[String] = []

var loading := false
var shown_colors: Dictionary = {}


func _init() -> void:
	title = "Candy Database Settings"
	ok_button_text = "Close"
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 400)
	add_child(tabs)
	standard_tabs = TabContainer.new()
	tabs.add_child(standard_tabs)
	tabs.set_tab_title(0, "Candy Database")
	_update_tab_bar()

	#@ Step 1 - General:
	var root := _page("General")
	root.add_child(_heading("Tab"))
	var tab_grid := _grid(root)
	tab_name_edit = LineEdit.new()
	tab_name_edit.placeholder_text = DBSettings.DEFAULT_TAB_NAME
	tab_name_edit.tooltip_text = "The tab's name in the editor's top bar. Leave it empty for %s." % DBSettings.DEFAULT_TAB_NAME
	tab_name_edit.text_submitted.connect(func(_text: String) -> void: _save_tab_name())
	tab_name_edit.focus_exited.connect(_save_tab_name)
	_row(tab_grid, "Tab name", tab_name_edit)

	root.add_child(_heading("Language"))
	var language_note := Label.new()
	language_note.text = "The languages to read in, most wanted first, separated by commas (Français, English). A database you haven't picked a language in opens in the first of them it has, or else in its own default language. Changing this forgets the languages you picked in the sidebar."
	language_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(language_note)
	var language_grid := _grid(root)
	language_edit = LineEdit.new()
	language_edit.placeholder_text = "Each database's default"
	language_edit.text_submitted.connect(func(_text: String) -> void: _save_language())
	language_edit.focus_exited.connect(_save_language)
	_row(language_grid, "Preferred language", language_edit)

	#@ Step 2 - Layout:
	root = _page("Layout")
	root.add_child(_heading("Layout"))
	var layout := _grid(root)
	sidebar_option = OptionButton.new()
	for side in DBSettings.SIDEBAR_SIDES:
		sidebar_option.add_item(side)
	sidebar_option.item_selected.connect(func(index: int) -> void: _save("sidebar_side", DBSettings.SIDEBAR_SIDES[index]))
	_row(layout, "Sidebar", sidebar_option)
	font_size_box = _spin_box(8, 40, 1)
	font_size_box.value_changed.connect(func(value: float) -> void: _save("font_size", int(value)))
	_row(layout, "Text size", font_size_box)
	width_box = _spin_box(0, 4000, 10)
	width_box.suffix = "px"
	width_box.tooltip_text = "The widest the text gets, centered in the page. 0 lets it fill the page."
	width_box.value_changed.connect(func(value: float) -> void: _save("max_text_width", int(value)))
	_row(layout, "Text width limit", width_box)

	root.add_child(_heading("Two pages"))
	var split_note := Label.new()
	split_note.text = "Ctrl+click a page in the list to open it in the second page, or a link to open it in the other page."
	split_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(split_note)
	var split_grid := _grid(root)
	second_side_option = OptionButton.new()
	for side in DBSettings.SECOND_PAGE_SIDES:
		second_side_option.add_item(side)
	second_side_option.item_selected.connect(func(index: int) -> void: _save("second_page_side", DBSettings.SECOND_PAGE_SIDES[index]))
	_row(split_grid, "Second page opens", second_side_option)
	split_colors_check = CheckBox.new()
	split_colors_check.text = "Mark the second page in a color of its own"
	split_colors_check.toggled.connect(func(pressed: bool) -> void:
		second_color_picker.disabled = not pressed
		_save("split_page_colors", pressed))
	_row(split_grid, "Page list", split_colors_check)
	second_color_picker = _color_button("second_page_mark_color")
	_row(split_grid, "Second page's color", second_color_picker)

	#@ Step 3 - Look:
	root = _page("Look")
	root.add_child(_heading("Theme"))
	var theme_grid := _grid(root)
	theme_option = OptionButton.new()
	theme_option.item_selected.connect(func(index: int) -> void:
		_save("theme", theme_ids[index])
		load_values())
	_row(theme_grid, "Look of the tab", theme_option)

	root.add_child(_heading("Colors and background"))
	var colors := _grid(root)
	background_picker = _color_button("background_color")
	_row(colors, "Background color", background_picker)
	text_picker = _color_button("text_color")
	_row(colors, "Text color", text_picker)
	link_picker = _color_button("link_color")
	_row(colors, "Link color", link_picker)
	code_picker = _color_button("code_color")
	_row(colors, "Code color", code_picker)

	texture_edit = _texture_row(colors, "Background image", "background_texture")

	mode_option = OptionButton.new()
	for mode in DBSettings.TEXTURE_MODES:
		mode_option.add_item(mode)
	mode_option.item_selected.connect(func(index: int) -> void: _save("background_texture_mode", DBSettings.TEXTURE_MODES[index]))
	_row(colors, "Image fit", mode_option)
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0.0
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.01
	opacity_slider.custom_minimum_size = Vector2(200, 0)
	opacity_slider.value_changed.connect(func(value: float) -> void: _save("background_opacity", value))
	_row(colors, "Image opacity", opacity_slider)

	_add_band_section(root, "header", "Header background")
	_add_band_section(root, "footer", "Footer background")

	var reset := Button.new()
	reset.text = "Back to the theme's colors and no background images"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		DBSettings.reset_style()
		load_values()
		settings_changed.emit())
	root.add_child(reset)

	#@ Step 4 - Databases:
	root = _page("Databases")
	root.add_child(_heading("Database styles and themes"))
	ignore_themes_check = CheckBox.new()
	ignore_themes_check.text = "Ignore every database theme (keep the editor's look for the bars and menus)"
	ignore_themes_check.toggled.connect(func(pressed: bool) -> void: _save("ignore_database_themes", pressed))
	root.add_child(ignore_themes_check)
	var note := Label.new()
	note.text = "A database can ask for its own page colors and background (style) and for its own look for the whole tab (theme). Untick one to keep yours."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)
	database_list = VBoxContainer.new()
	root.add_child(database_list)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg ; Images"])
	file_dialog.file_selected.connect(func(path: String) -> void:
		texture_target_edit.text = path
		_save(texture_target_key, path))
	add_child(file_dialog)


#* Add a mod's settings as a top-level tab, after the standard settings:
func add_mod_tab(title_text: String, content: Control) -> void:
	tabs.add_child(content)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title_text)
	_update_tab_bar()


#* Show the top-level tab bar only when a mod has added a tab:
func _update_tab_bar() -> void:
	tabs.tabs_visible = tabs.get_tab_count() > 1
	#% Bar hidden - no page around the sub-tabs, which draw their own:
	if tabs.tabs_visible:
		tabs.remove_theme_stylebox_override("panel")
	else:
		tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


#* A sub-tab of the standard settings, scrolled so the window can be shorter than it. Returns its column:
func _page(title_text: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	standard_tabs.add_child(scroll)
	standard_tabs.set_tab_title(standard_tabs.get_tab_count() - 1, title_text)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


#* Fill the controls, and list the databases with a style or theme of their own:
func open(databases: Array[Dictionary]) -> void:
	_fill_themes()
	load_values()
	for child in database_list.get_children():
		child.queue_free()
	var any := false
	for database in databases:
		var database_id: String = database["id"]
		var database_style: Dictionary = database["style"]
		if not database_style.is_empty():
			any = true
			var check := CheckBox.new()
			check.text = "%s: use its own style" % database["title"]
			check.button_pressed = not DBSettings.style_is_ignored(database_id)
			check.toggled.connect(func(pressed: bool) -> void:
				DBSettings.set_style_ignored(database_id, not pressed)
				settings_changed.emit())
			database_list.add_child(check)
		var database_theme: Dictionary = database["theme"]
		if not database_theme.is_empty() or not str(database["theme_name"]).is_empty():
			any = true
			var theme_check := CheckBox.new()
			theme_check.text = "%s: use its own theme" % database["title"]
			theme_check.button_pressed = not DBSettings.theme_is_ignored(database_id)
			theme_check.toggled.connect(func(pressed: bool) -> void:
				DBSettings.set_theme_ignored(database_id, not pressed)
				settings_changed.emit())
			database_list.add_child(theme_check)
	if not any:
		var none := Label.new()
		none.text = "No database asks for its own style or theme."
		database_list.add_child(none)
	popup_centered_clamped(Vector2i(620, 720), 0.85)


func _fill_themes() -> void:
	loading = true
	theme_option.clear()
	theme_ids.clear()
	var themes := DBSettings.available_themes()
	var ids: Array = themes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if a == "Standard" or b == "Standard":
			return a == "Standard" and b != "Standard"
		return str(themes[a].get("title", a)).naturalnocasecmp_to(str(themes[b].get("title", b))) < 0)
	for id: String in ids:
		theme_ids.append(id)
		theme_option.add_item(str(themes[id].get("title", id)))
	loading = false


#* Fill the controls from the settings:
func load_values() -> void:
	loading = true
	theme_option.select(maxi(0, theme_ids.find(str(DBSettings.get_value("theme")))))
	language_edit.text = str(DBSettings.get_value("preferred_language"))
	tab_name_edit.text = str(DBSettings.get_value("tab_name"))
	var shown := DBSettings.resolve_style({})	#/ Colors in use: the theme's, or the user's over them
	sidebar_option.select(maxi(0, DBSettings.SIDEBAR_SIDES.find(str(DBSettings.get_value("sidebar_side")))))
	font_size_box.value = float(DBSettings.get_value("font_size"))
	width_box.value = float(DBSettings.get_value("max_text_width"))
	split_colors_check.button_pressed = bool(DBSettings.get_value("split_page_colors"))
	second_color_picker.disabled = not split_colors_check.button_pressed
	second_side_option.select(maxi(0, DBSettings.SECOND_PAGE_SIDES.find(str(DBSettings.get_value("second_page_side")))))
	second_color_picker.color = DBSettings.resolve_second_page_color({})
	shown_colors["second_page_mark_color"] = second_color_picker.color
	background_picker.color = shown["background_color"]
	text_picker.color = shown["text_color"]
	link_picker.color = shown["link_color"]
	code_picker.color = shown["code_color"]
	for key in DBSettings.COLOR_KEYS:
		shown_colors[key] = shown[key]
	texture_edit.text = str(DBSettings.get_value("background_texture"))
	for band: String in band_controls:
		_load_band_values(band, shown)
	mode_option.select(maxi(0, DBSettings.TEXTURE_MODES.find(str(DBSettings.get_value("background_texture_mode")))))
	opacity_slider.value = float(DBSettings.get_value("background_opacity"))
	ignore_themes_check.button_pressed = bool(DBSettings.get_value("ignore_database_themes"))
	loading = false


func _save(key: String, value: Variant) -> void:
	if loading:
		return
	DBSettings.set_value(key, value)
	settings_changed.emit()


#* Save the typed tab name if changed, and rename the tab:
func _save_tab_name() -> void:
	var typed := tab_name_edit.text.strip_edges()
	if loading or typed == str(DBSettings.get_value("tab_name")).strip_edges():
		return
	var old_name := DBSettings.tab_name()
	DBSettings.set_value("tab_name", typed)
	DBSettings.rename_tab(old_name, DBSettings.tab_name())


#* Save the typed languages if changed:
func _save_language() -> void:
	var typed := language_edit.text.strip_edges()
	if loading or typed == str(DBSettings.get_value("preferred_language")):
		return
	DBSettings.set_value("preferred_language", typed)
	DBSettings.set_value("last_languages", {})	#/ Forget the sidebar's picks: the preference applies to every database
	language_changed.emit()


#* Image path row (type or browse), saved under `key`. Returns its text field:
#* A header's or footer's background section (band - "header" or "footer", the start of its setting keys):
func _add_band_section(root: VBoxContainer, band: String, title_text: String) -> void:
	var color_key := band + "_background_color"
	root.add_child(_heading(title_text))
	var grid := _grid(root)
	var color_row := HBoxContainer.new()
	var picker := _color_button(color_key)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(picker)
	var auto_check := CheckBox.new()
	auto_check.text = "Same as the page"
	color_row.add_child(auto_check)
	#Ł Picking a color unticks "Same as the page"; ticking it goes back to transparent:
	picker.color_changed.connect(func(_color: Color) -> void:
		if picker.get_popup().visible:
			auto_check.set_pressed_no_signal(false))
	auto_check.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_save(color_key, Color(0, 0, 0, 0))
		else:
			shown_colors[color_key] = picker.color
			_save(color_key, Color(picker.color, 1.0)))
	_row(grid, "Background color", color_row)
	var band_texture_edit := _texture_row(grid, "Background image", band + "_background_texture")
	var band_mode_option := OptionButton.new()
	for mode in DBSettings.TEXTURE_MODES:
		band_mode_option.add_item(mode)
	band_mode_option.item_selected.connect(func(index: int) -> void: _save(band + "_background_mode", DBSettings.TEXTURE_MODES[index]))
	_row(grid, "Image fit", band_mode_option)
	band_controls[band] = {"picker": picker, "auto_check": auto_check, "texture_edit": band_texture_edit, "mode_option": band_mode_option}


#* A header's or footer's background section shows the settings (shown - the resolved style's colors):
func _load_band_values(band: String, shown: Dictionary) -> void:
	var controls: Dictionary = band_controls[band]
	var color_key := band + "_background_color"
	var band_texture_edit: LineEdit = controls["texture_edit"]
	band_texture_edit.text = str(DBSettings.get_value(band + "_background_texture"))
	var band_mode_option: OptionButton = controls["mode_option"]
	band_mode_option.select(maxi(0, DBSettings.TEXTURE_MODES.find(str(DBSettings.get_value(band + "_background_mode")))))
	var own_color: Color = DBSettings.get_value(color_key)
	var auto_check: CheckBox = controls["auto_check"]
	auto_check.set_pressed_no_signal(own_color.a == 0.0)
	var shown_color: Color = shown[color_key]
	if shown_color.a == 0.0:
		shown_color = shown["background_color"]
	var picker: ColorPickerButton = controls["picker"]
	picker.color = shown_color
	shown_colors[color_key] = shown_color


func _texture_row(grid: GridContainer, title_text: String, key: String) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "No image"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text: String) -> void: _save(key, text.strip_edges()))
	edit.focus_exited.connect(func() -> void: _save(key, edit.text.strip_edges()))
	row.add_child(edit)
	var browse := Button.new()
	browse.text = "Browse"
	browse.pressed.connect(func() -> void:
		texture_target_key = key
		texture_target_edit = edit
		file_dialog.popup_centered_ratio(0.6))
	row.add_child(browse)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void:
		edit.text = ""
		_save(key, ""))
	row.add_child(clear)
	_row(grid, title_text, row)
	return edit


func _color_button(key: String) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(120, 28)
	button.edit_alpha = false
	#Ł Save picked colors only (not the picker's starting black or the color it opens on):
	button.color_changed.connect(func(color: Color) -> void:
		if not button.get_popup().visible or color == shown_colors.get(key):
			return
		shown_colors[key] = color
		_save(key, color))
	button.get_popup().about_to_popup.connect(func() -> void: _light_mode_buttons(button.get_picker()))
	return button


#* Make the text of the picker's RGB / HSV / RAW buttons light:
func _light_mode_buttons(node: Node) -> void:
	for child in node.get_children(true):
		if child is Button and child.toggle_mode and child.has_theme_stylebox_override("normal"):
			for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				child.add_theme_color_override(color_name, Color(0.95, 0.95, 0.95))	#/ Their dark background ignores the theme
		_light_mode_buttons(child)


func _spin_box(minimum: float, maximum: float, step: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	parent.add_child(grid)
	return grid


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
