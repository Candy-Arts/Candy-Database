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
extends RefCounted


const Library = preload("Database_Library.gd")

const PREFIX := "candy_database/"
const STATE_PREFIX := "candy_database/state/"

const TEXTURE_MODES: Array[String] = ["Cover", "Stretch", "Tile"]
const SIDEBAR_SIDES: Array[String] = ["Left", "Right"]
const SECOND_PAGE_SIDES: Array[String] = ["Left", "Right", "Above", "Below"]
#^ Fallback second page color:
const SECOND_PAGE_COLOR := Color(0.88, 0.52, 0.18)

#^ The tab's name when none is set:
const DEFAULT_TAB_NAME := "Candy DB"

const DEFAULTS := {
	#? The tab's name in the editor's top bar ("" = DEFAULT_TAB_NAME).
	"tab_name": "",
	"sidebar_side": "Left",
	"font_size": 16,
	"show_header": true,
	"show_footer": true,
	"max_text_width": 900,
	"theme": "Standard",
	#? Comma-separated, most wanted first ("Français, English"). Fallback: default_language.
	"preferred_language": "",
	"background_color": Color(0, 0, 0, 0),
	"text_color": Color(0, 0, 0, 0),
	"link_color": Color(0, 0, 0, 0),
	"code_color": Color(0, 0, 0, 0),
	"background_texture": "",
	"background_texture_mode": "Cover",
	"background_opacity": 1.0,
	"header_background_color": Color(0, 0, 0, 0),
	"header_text_color": Color(0, 0, 0, 0),
	"header_background_texture": "",
	"header_background_mode": "Cover",
	"footer_background_color": Color(0, 0, 0, 0),
	"footer_text_color": Color(0, 0, 0, 0),
	"footer_background_texture": "",
	"footer_background_mode": "Cover",
	"ignored_database_styles": {},
	"ignore_database_themes": false,
	"ignored_database_themes": {},
	#? Mark the second page in the page list in its own color (else the selection color).
	"split_page_colors": true,
	"second_page_mark_color": Color(0, 0, 0, 0),
	#? Second page's side of the first.
	"second_page_side": "Right",
}

const STATE_DEFAULTS := {
	"last_database": "",
	"last_versions": {},
	"last_languages": {},
	"last_pages": {},
	#? Per database id: {category key: true} per folded category.
	"folded_categories": {},
}

#^ Fallback page style:
const BASE_STYLE := {
	"background_color": Color(0.12, 0.13, 0.16),
	"text_color": Color(0.87, 0.89, 0.92),
	"link_color": Color(0.43, 0.70, 1.0),
	#? [code] text.
	"code_color": Color(0.95, 0.66, 0.42),
	#? Transparent: the page's background and text color.
	"header_background_color": Color(0, 0, 0, 0),
	"header_text_color": Color(0, 0, 0, 0),
	"footer_background_color": Color(0, 0, 0, 0),
	"footer_text_color": Color(0, 0, 0, 0),
}
const COLOR_KEYS: Array[String] = ["background_color", "text_color", "link_color", "code_color", "header_background_color", "header_text_color", "footer_background_color", "footer_text_color"]
#^ Page scroll bar (themes and databases only):
#? Transparent: made from the text color (see Database_Pane.gd).
const SCROLL_BAR_COLOR_KEYS: Array[String] = ["scroll_bar_color", "scroll_grabber_color", "scroll_grabber_hover_color", "scroll_grabber_pressed_color"]
const SCROLL_BAR_WIDTH := 10
const SCROLL_BAR_RADIUS := 4
const THEMES_FOLDER := "Themes"

const BUTTON_TYPES: Array[String] = ["Button", "OptionButton", "MenuButton"]
const TEXT_TYPES: Array[String] = ["Button", "OptionButton", "MenuButton", "CheckBox", "Label", "LineEdit", "Tree", "ItemList", "PopupMenu", "TabContainer"]

static var _memory: Dictionary = {}
static var _font_cache: Dictionary = {}


static func _editor_settings() -> EditorSettings:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_settings()
	return null


#* Register every setting in the EditorSettings:
static func ensure_defaults() -> void:
	var editor_settings := _editor_settings()
	if editor_settings == null:
		return
	for key: String in DEFAULTS:
		if not editor_settings.has_setting(PREFIX + key):
			editor_settings.set_setting(PREFIX + key, DEFAULTS[key])
		editor_settings.set_initial_value(PREFIX + key, DEFAULTS[key], false)
	editor_settings.add_property_info({"name": PREFIX + "sidebar_side", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(SIDEBAR_SIDES)})
	editor_settings.add_property_info({"name": PREFIX + "second_page_side", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(SECOND_PAGE_SIDES)})
	editor_settings.add_property_info({"name": PREFIX + "background_texture_mode", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(TEXTURE_MODES)})
	editor_settings.add_property_info({"name": PREFIX + "font_size", "type": TYPE_INT, "hint": PROPERTY_HINT_RANGE, "hint_string": "8,40,1"})
	editor_settings.add_property_info({"name": PREFIX + "background_opacity", "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,1,0.01"})


#* The tab's name in the editor's top bar:
static func tab_name() -> String:
	var chosen := str(get_value("tab_name")).strip_edges()
	if chosen == "":
		return DEFAULT_TAB_NAME
	return chosen


#* Rename the tab's button in the editor's top bar (Godot only reads the name when the plugin loads):
static func rename_tab(old_name: String, new_name: String) -> void:
	var base := EditorInterface.get_base_control()
	for button: Button in base.find_children("*", "Button", true, false):
		if button.theme_type_variation == &"MainScreenButton" and button.text == old_name:
			button.text = new_name
			return


static func get_value(key: String) -> Variant:
	var full_key := PREFIX + key
	var default: Variant = DEFAULTS.get(key)
	if default == null:
		full_key = STATE_PREFIX + key
		default = STATE_DEFAULTS.get(key)
	var editor_settings := _editor_settings()
	if editor_settings != null and editor_settings.has_setting(full_key):
		return editor_settings.get_setting(full_key)
	if _memory.has(key):
		return _memory[key]
	if default is Dictionary or default is Array:
		return default.duplicate(true)
	return default


static func set_value(key: String, value: Variant) -> void:
	var full_key := PREFIX + key
	if not DEFAULTS.has(key):
		full_key = STATE_PREFIX + key
	var editor_settings := _editor_settings()
	if editor_settings != null:
		editor_settings.set_setting(full_key, value)
	else:
		_memory[key] = value


static func reset_style() -> void:
	for key: String in ["background_color", "text_color", "link_color", "code_color", "background_texture", "background_texture_mode", "background_opacity", "header_background_color", "header_text_color", "header_background_texture", "header_background_mode", "footer_background_color", "footer_text_color", "footer_background_texture", "footer_background_mode", "second_page_mark_color"]:
		set_value(key, DEFAULTS[key])


static func style_is_ignored(database_id: String) -> bool:
	var ignored: Dictionary = get_value("ignored_database_styles")
	return ignored.has(database_id)


static func set_style_ignored(database_id: String, ignored: bool) -> void:
	var all_ignored: Dictionary = get_value("ignored_database_styles")
	if ignored:
		all_ignored[database_id] = true
	else:
		all_ignored.erase(database_id)
	set_value("ignored_database_styles", all_ignored)


#* Theme folders - built-in, then the user's:
static func theme_folders() -> Array[String]:
	var library_script: Script = Library
	var builtin: String = library_script.resource_path.get_base_dir().get_base_dir().path_join(THEMES_FOLDER)
	var user: String = Library.user_library_path().get_base_dir().path_join(THEMES_FOLDER)
	return [builtin, user]


#* Every theme file ({"title", "style", "theme"}), by file name:
static func available_themes() -> Dictionary:
	var found: Dictionary = {}
	for folder in theme_folders():
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file_name in DirAccess.get_files_at(folder):
			if file_name.get_extension().to_lower() != "json":
				continue
			var data := Library.read_json(folder.path_join(file_name))
			if not data.is_empty():
				found[file_name.get_basename()] = data	#/ The user's folder (last) overrides the built-in one
	return found


#* The user's theme (Standard if it's gone):
static func selected_theme() -> Dictionary:
	var themes := available_themes()
	var chosen := str(get_value("theme"))
	if themes.has(chosen):
		return themes[chosen]
	if themes.has("Standard"):
		return themes["Standard"]
	return {}


static func theme_is_ignored(database_id: String) -> bool:
	var ignored: Dictionary = get_value("ignored_database_themes")
	return ignored.has(database_id)


static func set_theme_ignored(database_id: String, ignored: bool) -> void:
	var all_ignored: Dictionary = get_value("ignored_database_themes")
	if ignored:
		all_ignored[database_id] = true
	else:
		all_ignored.erase(database_id)
	set_value("ignored_database_themes", all_ignored)


#* A database's base theme: its theme_name, or the user's:
static func base_theme_for(database: Dictionary) -> Dictionary:
	if not database.is_empty() and not bool(get_value("ignore_database_themes")) and not theme_is_ignored(str(database["id"])):
		var themes := available_themes()
		var named := str(database["theme_name"])
		if themes.has(named):
			return themes[named]
	return selected_theme()	#/ Also when database themes are ignored


#* Theme for the whole tab - the base theme's "theme", with the database's own over it:
static func resolve_theme(database: Dictionary) -> Theme:
	var merged: Dictionary = {}
	var chosen := base_theme_for(database)
	if chosen.get("theme") is Dictionary:
		merged = chosen["theme"].duplicate()
	var base_path := ""
	if not database.is_empty() and not bool(get_value("ignore_database_themes")) and not theme_is_ignored(str(database["id"])):
		var own: Dictionary = database["theme"]
		for key: String in own:
			merged[key] = own[key]
		base_path = str(database["path"])
	return build_theme(merged, base_path)	#/ Set on the tab only: the editor fills what it leaves out


#* Second page's mark color: the user's, else the theme's second_page_color, else SECOND_PAGE_COLOR:
static func resolve_second_page_color(database: Dictionary) -> Color:
	var chosen: Color = get_value("second_page_mark_color")
	if chosen.a > 0.0:
		return chosen
	var text := ""
	var base_theme := base_theme_for(database)
	if base_theme.get("theme") is Dictionary:
		text = str(base_theme["theme"].get("second_page_color", ""))
	#Ł The database's theme overrides the base theme:
	if not database.is_empty() and not bool(get_value("ignore_database_themes")) and not theme_is_ignored(str(database["id"])):
		var own: Dictionary = database["theme"]
		if own.has("second_page_color"):
			text = str(own["second_page_color"])
	if text.is_empty():
		return SECOND_PAGE_COLOR
	return parse_color(text, SECOND_PAGE_COLOR)


static func build_theme(own: Dictionary, base_path: String) -> Theme:
	var theme := Theme.new()
	#Ł Bar panels, invisible unless the theme colors them:
	theme.set_type_variation("SidebarPanel", "PanelContainer")
	theme.set_type_variation("ToolbarPanel", "PanelContainer")
	theme.set_stylebox("panel", "SidebarPanel", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "ToolbarPanel", StyleBoxEmpty.new())
	if own.is_empty():
		return theme
	var accent := _own_color(own, "accent_color")
	var text := _own_color(own, "text_color")
	var button := _own_color(own, "button_color")
	var hover := _own_color(own, "hover_color")
	var pressed := _own_color(own, "pressed_color")
	var field := _own_color(own, "field_color")
	var border := _own_color(own, "border_color")
	var sidebar := _own_color(own, "sidebar_color")
	var toolbar := _own_color(own, "toolbar_color")
	var list_color := _own_color(own, "list_color")
	var icon_color := _own_color(own, "icon_color")
	var list_icon_color := _own_color(own, "list_icon_color")
	var arrow_color := _own_color(own, "arrow_color")
	var border_width := 0
	if str(own.get("border_width", "")).is_valid_int():
		border_width = clampi(int(own["border_width"]), 0, 4)
	var radius := 3
	if str(own.get("corner_radius", "")).is_valid_int():
		radius = clampi(int(own["corner_radius"]), 0, 16)
	if border.a == 0.0:
		border_width = 0
	if sidebar.a > 0.0:
		theme.set_stylebox("panel", "SidebarPanel", _box(sidebar, 6, 6, 0))
	if toolbar.a > 0.0:
		theme.set_stylebox("panel", "ToolbarPanel", _box(toolbar, 6, 3, 0))
	#Ł Dialog panels, so their text matches their background:
	var dialog_color := sidebar
	for candidate in [field, toolbar, button]:
		if dialog_color.a == 0.0:
			dialog_color = candidate
	if dialog_color.a > 0.0:
		theme.set_stylebox("panel", "AcceptDialog", _box(dialog_color, 8, 8, 0))
		theme.set_stylebox("panel", "PopupPanel", _box(dialog_color, 8, 8, radius, border, border_width))
		#Ł Tooltips are PopupPanels too - give them a compact panel:
		theme.set_type_variation("TooltipPanel", "PopupPanel")
		theme.set_stylebox("panel", "TooltipPanel", _box(dialog_color, 4, 2, mini(radius, 4), border, mini(border_width, 1)))
	var tree_color := list_color
	if tree_color.a == 0.0:
		tree_color = sidebar
	if tree_color.a == 0.0:
		tree_color = field
	if tree_color.a > 0.0:
		theme.set_stylebox("panel", "Tree", _box(tree_color, 4, 4, radius, border, border_width))
		theme.set_stylebox("panel", "ItemList", _box(tree_color, 4, 4, radius, border, border_width))
	if field.a > 0.0:
		theme.set_stylebox("normal", "LineEdit", _box(field, 6, 4, radius, border, border_width))
		theme.set_stylebox("focus", "LineEdit", _box(field.lightened(0.1), 6, 4, radius, border, border_width))
	if button.a > 0.0:
		if hover.a == 0.0:
			hover = button.lightened(0.15)
		if pressed.a == 0.0:
			pressed = accent
		if pressed.a == 0.0:
			pressed = button.darkened(0.2)
		for type in BUTTON_TYPES:
			theme.set_stylebox("normal", type, _box(button, 6, 4, radius, border, border_width))
			theme.set_stylebox("hover", type, _box(hover, 6, 4, radius, border, border_width))
			theme.set_stylebox("pressed", type, _box(pressed, 6, 4, radius, border, border_width))
			theme.set_stylebox("hover_pressed", type, _box(pressed.lightened(0.1), 6, 4, radius, border, border_width))
			theme.set_stylebox("disabled", type, _box(Color(button, 0.5), 6, 4, radius, border, border_width))
		var popup_color := field
		if popup_color.a == 0.0:
			popup_color = button.darkened(0.1)
		theme.set_stylebox("panel", "PopupMenu", _box(popup_color, 4, 4, radius, border, border_width))
	#Ł Tabs (the settings window): the page in the field color, joined to the selected tab:
	var tab_page := field
	if tab_page.a == 0.0:
		tab_page = dialog_color
	if tab_page.a > 0.0:
		var tab_color := button
		if tab_color.a == 0.0:
			tab_color = tab_page.darkened(0.12)
		var tab_hover := hover
		if tab_hover.a == 0.0:
			tab_hover = tab_color.lightened(0.15)
		var tab_panel := _box(tab_page, 8, 8, radius, border, border_width)
		tab_panel.corner_radius_top_left = 0	#/ Square under the first tab, so the two join
		theme.set_stylebox("panel", "TabContainer", tab_panel)
		theme.set_stylebox("tab_selected", "TabContainer", _tab_box(tab_page, radius, border, border_width, true))
		theme.set_stylebox("tab_unselected", "TabContainer", _tab_box(tab_color, radius, border, border_width, false))
		theme.set_stylebox("tab_hovered", "TabContainer", _tab_box(tab_hover, radius, border, border_width, false))
		theme.set_stylebox("tab_disabled", "TabContainer", _tab_box(Color(tab_color, 0.5), radius, border, border_width, false))
		theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
		#? The editor's tab bar background is dark: let the window's color show behind the tabs.
		theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	if accent.a > 0.0:
		var on_accent := contrast_color(accent)
		theme.set_stylebox("selected", "Tree", _box(accent, 2, 2, 2))
		theme.set_stylebox("selected_focus", "Tree", _box(accent, 2, 2, 2))
		theme.set_color("font_selected_color", "Tree", on_accent)
		theme.set_stylebox("hover", "PopupMenu", _box(accent, 2, 2, 2))
		theme.set_color("font_hover_color", "PopupMenu", on_accent)
	if pressed.a > 0.0:
		var on_pressed := contrast_color(pressed)
		for type in BUTTON_TYPES:
			theme.set_color("font_pressed_color", type, on_pressed)
			theme.set_color("font_hover_pressed_color", type, on_pressed)
	if text.a > 0.0:
		for type in TEXT_TYPES:
			theme.set_color("font_color", type, text)
		for type in BUTTON_TYPES:
			theme.set_color("font_hover_color", type, text)
			theme.set_color("font_focus_color", type, text)
		for item_name in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
			theme.set_color(item_name, "TabContainer", text)
		theme.set_color("font_disabled_color", "TabContainer", Color(text, 0.5))
		theme.set_color("font_placeholder_color", "LineEdit", Color(text, 0.5))
		theme.set_color("caret_color", "LineEdit", text)
	#Ł Page list icon and fold arrow colors (the editor's are light, for dark backgrounds):
	if list_icon_color.a > 0.0:
		theme.set_color("tree_icon", "CandyDatabase", list_icon_color)
	if arrow_color.a > 0.0:
		theme.set_color("tree_arrow", "CandyDatabase", arrow_color)
	if icon_color.a > 0.0:
		for type in BUTTON_TYPES:
			for item_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
				theme.set_color(item_name, type, icon_color)
			theme.set_color("icon_disabled_color", type, Color(icon_color, 0.5))
	var font := _load_font(str(own.get("font", "")), base_path)
	if font != null:
		for type in TEXT_TYPES:
			theme.set_font("font", type, font)
		theme.set_font("normal_font", "RichTextLabel", font)
	var bold_font := _load_font(str(own.get("bold_font", "")), base_path)
	if bold_font != null:
		theme.set_font("bold_font", "RichTextLabel", bold_font)
	#Ł Mono font for [code] (the editor theme's is its regular font):
	var mono_font := _load_font(str(own.get("mono_font", "")), base_path)
	if mono_font == null:
		mono_font = _editor_mono_font()
	theme.set_font("mono_font", "RichTextLabel", mono_font)
	var font_size := str(own.get("font_size", ""))
	if font_size.is_valid_int():
		for type in TEXT_TYPES:
			theme.set_font_size("font_size", type, clampi(int(font_size), 8, 40))
	return theme


#* A database's theme color, or transparent:
static func _own_color(own: Dictionary, key: String) -> Color:
	return Color.from_string(str(own.get(key, "")), Color.TRANSPARENT)


static func _box(color: Color, margin_x := 6, margin_y := 4, radius := 3, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


#* A tab's box: top corners rounded, no bottom border (the page's top border is below); the selected tab joins the page:
#? The selected tab overflows onto the page's top border to cover it.
static func _tab_box(color: Color, radius: int, border: Color, border_width: int, selected: bool) -> StyleBoxFlat:
	var box := _box(color, 10, 4, radius, border, border_width)
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.border_width_bottom = 0
	if selected:
		box.expand_margin_bottom = border_width
	return box


#* Editor's code font, or a system monospace font outside the editor:
static func _editor_mono_font() -> Font:
	if Engine.is_editor_hint():
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme.has_font("source", "EditorFonts"):
			return editor_theme.get_font("source", "EditorFonts")
	if not _font_cache.has("monospace"):
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["monospace", "Consolas", "Menlo", "DejaVu Sans Mono", "Courier New"])
		_font_cache["monospace"] = system_font
	return _font_cache["monospace"]


#* Black or white, whichever reads on `color`:
static func contrast_color(color: Color) -> Color:
	if color.get_luminance() > 0.5:
		return Color(0.05, 0.05, 0.05)
	return Color(0.97, 0.97, 0.97)


#* A font file inside the database folder, or null:
static func _load_font(font_path: String, base_path: String) -> Font:
	if font_path.is_empty() or base_path.is_empty():
		return null
	var resolved := base_path.path_join(font_path).simplify_path()
	if not resolved.begins_with(base_path) or not FileAccess.file_exists(resolved):
		return null
	if not _font_cache.has(resolved):
		var font := FontFile.new()
		if font.load_dynamic_font(resolved) != OK:
			return null
		_font_cache[resolved] = font
	return _font_cache[resolved]


#* A database's colors and background: the user's, overridden key by key by the database's style:
static func resolve_style(database: Dictionary) -> Dictionary:
	var style := {
		"background_color": BASE_STYLE["background_color"],
		"text_color": BASE_STYLE["text_color"],
		"link_color": BASE_STYLE["link_color"],
		"code_color": BASE_STYLE["code_color"],
		"header_background_color": BASE_STYLE["header_background_color"],
		"header_text_color": BASE_STYLE["header_text_color"],
		"header_texture_path": str(get_value("header_background_texture")),
		"header_texture_mode": str(get_value("header_background_mode")),
		"footer_background_color": BASE_STYLE["footer_background_color"],
		"footer_text_color": BASE_STYLE["footer_text_color"],
		"footer_texture_path": str(get_value("footer_background_texture")),
		"footer_texture_mode": str(get_value("footer_background_mode")),
		"texture_path": str(get_value("background_texture")),
		"texture_mode": str(get_value("background_texture_mode")),
		"opacity": float(get_value("background_opacity")),
		"scroll_bar_width": SCROLL_BAR_WIDTH,
		"scroll_bar_radius": SCROLL_BAR_RADIUS,
	}
	for key in SCROLL_BAR_COLOR_KEYS:
		style[key] = Color.TRANSPARENT
	var theme_style: Dictionary = {}
	var chosen_theme := base_theme_for(database)
	if chosen_theme.get("style") is Dictionary:
		theme_style = chosen_theme["style"]
	_apply_colors(style, theme_style)
	_apply_scroll_bar(style, theme_style)
	for key in COLOR_KEYS:
		var chosen: Color = get_value(key)
		if chosen.a > 0.0:
			style[key] = chosen
	if not database.is_empty() and not style_is_ignored(str(database["id"])):
		var own: Dictionary = database["style"]
		_apply_colors(style, own)
		_apply_scroll_bar(style, own)
		var texture_path := str(own.get("background_texture", ""))
		if not texture_path.is_empty():
			if texture_path.is_absolute_path():
				style["texture_path"] = texture_path
			else:
				style["texture_path"] = str(database["path"]).path_join(texture_path)
		for band in ["header", "footer"]:
			var band_texture_path := str(own.get(band + "_background_texture", ""))
			if not band_texture_path.is_empty():
				if band_texture_path.is_absolute_path():
					style[band + "_texture_path"] = band_texture_path
				else:
					style[band + "_texture_path"] = str(database["path"]).path_join(band_texture_path)
			var band_mode := str(own.get(band + "_background_mode", ""))
			if TEXTURE_MODES.has(band_mode):
				style[band + "_texture_mode"] = band_mode
		var mode := str(own.get("background_texture_mode", ""))
		if TEXTURE_MODES.has(mode):
			style["texture_mode"] = mode
		var opacity := str(own.get("background_opacity", ""))
		if opacity.is_valid_float():
			style["opacity"] = clampf(float(opacity), 0.0, 1.0)
	style["texture"] = Library.load_texture(style["texture_path"])
	style["header_texture"] = Library.load_texture(style["header_texture_path"])
	style["footer_texture"] = Library.load_texture(style["footer_texture_path"])
	return style	#/ COLOR_KEYS, the scroll bar keys, textures, modes and opacity


static func _apply_colors(style: Dictionary, source: Dictionary) -> void:
	for key in COLOR_KEYS:
		var text := str(source.get(key, ""))
		if not text.is_empty():
			style[key] = parse_color(text, style[key])


static func _apply_scroll_bar(style: Dictionary, source: Dictionary) -> void:
	for key in SCROLL_BAR_COLOR_KEYS:
		var text := str(source.get(key, ""))
		if not text.is_empty():
			style[key] = parse_color(text, style[key])
	var width := str(source.get("scroll_bar_width", ""))
	if width.is_valid_int():
		style["scroll_bar_width"] = clampi(int(width), 2, 32)
	var radius := str(source.get("scroll_bar_radius", ""))
	if radius.is_valid_int():
		style["scroll_bar_radius"] = clampi(int(radius), 0, 16)


#* Theme or database color - "#rrggbb", a color name, or "editor:<name>" (an editor theme color):
static func parse_color(text: String, fallback: Color) -> Color:
	if text.begins_with("editor:"):	#/ Lets a theme follow the editor theme
		if Engine.is_editor_hint():
			var editor_theme := EditorInterface.get_editor_theme()
			var color_name := text.substr(7)
			if editor_theme.has_color(color_name, "Editor"):
				return editor_theme.get_color(color_name, "Editor")
		return fallback
	return Color.from_string(text, fallback)
