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


const Library = preload("Database_Library.gd")
const DBSettings = preload("Database_Settings.gd")
const SettingsDialog = preload("Database_Settings_Dialog.gd")
const Pane = preload("Database_Pane.gd")

enum Menu {
	REFRESH, OPEN_FOLDER, SETTINGS,
	SIDEBAR_LEFT, SIDEBAR_RIGHT, TOGGLE_SIDEBAR, SHOW_HEADER, SHOW_FOOTER, ZOOM_IN, ZOOM_OUT, ZOOM_RESET,
}

#^ About menu item ids - this + the page's index in about_pages:
const ABOUT_FIRST_ID := 1000
const DEFAULT_FONT_SIZE := 16
const MAX_PANES := 2
const MODS_FOLDER := "Mods"
const MOD_SCRIPT := "Mod.gd"
#^ Link target of a shrunk image - this + its texture's path:
const IMAGE_LINK := "image:"
#^ Image viewer room around the image (borders, title, Close button):
const IMAGE_DIALOG_MARGIN := Vector2i(48, 96)

#* A pane was opened, for mods:
signal pane_opened(pane: Pane)
#* Colors, fonts or text size changed (see text_look()):
signal appearance_changed

#^ Loaded mods, and their checks before pages are left:
var mods: Array[Node] = []
var leave_checks: Array[Callable] = []

var databases: Array[Dictionary] = []
var current_database: Dictionary = {}
var current_version := ""
var current_language := ""
#^ The version's languages, in picker order (preferred first):
var version_languages: Array[String] = []
var version_data: Dictionary = {}

#^ Pages shown, main first, and the last one clicked (About pages open there):
var panes: Array[Pane] = []
var active_pane: Pane = null

var image_cache: Dictionary = {}
var icon_cache: Dictionary = {}
var image_counter := 0
var page_items: Dictionary = {}
var marked_items: Array[TreeItem] = []
#^ True while building the page list, so its folding isn't saved as the user's:
var building_tree := false
var selection_color := Color.TRANSPARENT
var selection_font_color := Color.TRANSPARENT
var second_page_color := Color.TRANSPARENT

var database_menu: MenuButton
var view_menu: MenuButton
var about_menu: MenuButton
#^ About menu page ids, in menu order:
var about_pages: Array[String] = []
var database_picker: OptionButton
var version_picker: OptionButton
var language_picker: OptionButton
var settings_button: Button

var body: HSplitContainer
var toolbar_panel: PanelContainer
var sidebar: PanelContainer
var sidebar_box: VBoxContainer
var search_edit: LineEdit
var tree: Tree
var pages_split: SplitContainer

var settings_dialog: SettingsDialog
var link_dialog: ConfirmationDialog
var pending_link := ""
var image_dialog: AcceptDialog
var image_scroll: ScrollContainer
var image_view: TextureRect

var image_regex := RegEx.create_from_string("\\[img([^\\]]*)\\]([^\\[]*)\\[/img\\]")
var url_regex := RegEx.create_from_string("\\[url(=[^\\]]*)?\\]")


func _ready() -> void:
	_build()
	_load_mods()
	_open_pane()
	apply_layout()
	reload_library()


func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	toolbar_panel = PanelContainer.new()
	toolbar_panel.theme_type_variation = "ToolbarPanel"
	add_child(toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar_panel.add_child(toolbar)
	database_menu = _add_menu(toolbar, "Database")
	database_menu.get_popup().add_item("Refresh", Menu.REFRESH)
	database_menu.get_popup().add_item("Open Library Folder", Menu.OPEN_FOLDER)
	database_menu.get_popup().add_separator()
	database_menu.get_popup().add_item("Settings...", Menu.SETTINGS)
	view_menu = _add_menu(toolbar, "View")
	view_menu.get_popup().add_radio_check_item("Sidebar on the Left", Menu.SIDEBAR_LEFT)
	view_menu.get_popup().add_radio_check_item("Sidebar on the Right", Menu.SIDEBAR_RIGHT)
	view_menu.get_popup().add_check_item("Show Sidebar", Menu.TOGGLE_SIDEBAR)
	view_menu.get_popup().set_item_checked(view_menu.get_popup().get_item_index(Menu.TOGGLE_SIDEBAR), true)
	view_menu.get_popup().add_check_item("Show Page Header", Menu.SHOW_HEADER)
	view_menu.get_popup().add_check_item("Show Page Footer", Menu.SHOW_FOOTER)
	view_menu.get_popup().add_separator()
	view_menu.get_popup().add_item("Increase Text Size", Menu.ZOOM_IN)
	view_menu.get_popup().add_item("Decrease Text Size", Menu.ZOOM_OUT)
	view_menu.get_popup().add_item("Reset Text Size", Menu.ZOOM_RESET)
	#Ł About menu, filled by _update_about_menu():
	about_menu = _add_menu(toolbar, "About")
	about_menu.visible = false
	for menu_button in [database_menu, view_menu, about_menu]:
		menu_button.get_popup().id_pressed.connect(_on_menu_pressed)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	settings_button = Button.new()
	settings_button.flat = true
	settings_button.icon = get_theme_icon("Tools", "EditorIcons")
	settings_button.tooltip_text = "Settings"
	settings_button.pressed.connect(_open_settings)
	toolbar.add_child(settings_button)

	body = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	sidebar = PanelContainer.new()
	sidebar.theme_type_variation = "SidebarPanel"
	sidebar.custom_minimum_size = Vector2(260, 0)
	body.add_child(sidebar)
	sidebar_box = VBoxContainer.new()
	sidebar.add_child(sidebar_box)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search pages"
	search_edit.clear_button_enabled = true
	search_edit.right_icon = get_theme_icon("Search", "EditorIcons")
	search_edit.text_changed.connect(func(_text: String) -> void: _rebuild_tree())
	sidebar_box.add_child(search_edit)
	database_picker = OptionButton.new()
	database_picker.fit_to_longest_item = false
	database_picker.clip_text = true
	database_picker.tooltip_text = "Database"
	database_picker.item_selected.connect(_on_database_picked)
	sidebar_box.add_child(database_picker)
	var picker_row := HBoxContainer.new()
	sidebar_box.add_child(picker_row)
	version_picker = OptionButton.new()
	version_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version_picker.fit_to_longest_item = false
	version_picker.tooltip_text = "Version"
	version_picker.item_selected.connect(_on_version_picked)
	picker_row.add_child(version_picker)
	language_picker = OptionButton.new()
	language_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_picker.fit_to_longest_item = false
	language_picker.tooltip_text = "Language"
	language_picker.item_selected.connect(_on_language_picked)
	picker_row.add_child(language_picker)
	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(_on_tree_selected)
	tree.item_collapsed.connect(_on_item_collapsed)
	sidebar_box.add_child(tree)

	#Ł Pages, arranged by _arrange_panes():
	pages_split = SplitContainer.new()
	pages_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pages_split)

	settings_dialog = SettingsDialog.new()
	settings_dialog.settings_changed.connect(_on_settings_changed)
	settings_dialog.language_changed.connect(func() -> void: _leave(panes.duplicate(), reselect_language))
	add_child(settings_dialog)
	link_dialog = ConfirmationDialog.new()
	link_dialog.title = "Open Link"
	link_dialog.confirmed.connect(func() -> void: OS.shell_open(pending_link))
	add_child(link_dialog)
	#Ł Full-size image viewer, opened by clicking a shrunk image:
	image_dialog = AcceptDialog.new()
	image_dialog.ok_button_text = "Close"
	add_child(image_dialog)
	image_scroll = ScrollContainer.new()
	image_dialog.add_child(image_scroll)
	image_view = TextureRect.new()
	image_view.stretch_mode = TextureRect.STRETCH_KEEP
	image_scroll.add_child(image_view)


func _add_menu(toolbar: HBoxContainer, title_text: String) -> MenuButton:
	var menu_button := MenuButton.new()
	menu_button.text = title_text
	menu_button.flat = true
	menu_button.switch_on_hover = true
	toolbar.add_child(menu_button)
	return menu_button


# ---------------------------------------------------------------- Mods

#* Load the mods, in folder name order:
func _load_mods() -> void:
	var folder := (get_script() as Script).resource_path.get_base_dir().get_base_dir().path_join(MODS_FOLDER)
	if not DirAccess.dir_exists_absolute(folder):
		return
	var mod_folders := Array(DirAccess.get_directories_at(folder))
	mod_folders.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for mod_folder: String in mod_folders:
		if mod_folder.begins_with(".") or mod_folder.begins_with("_"):
			continue
		var script_path := folder.path_join(mod_folder).path_join(MOD_SCRIPT)
		if not ResourceLoader.exists(script_path):
			continue
		var script := load(script_path) as Script
		if script == null or not script.can_instantiate() or not script.is_tool():
			push_warning("Candy Database: the mod \"%s\" was not loaded (its %s must be a @tool script that can be instanced)." % [mod_folder, MOD_SCRIPT])
			continue
		var mod: Variant = script.new()
		if not mod is Node:
			push_warning("Candy Database: the mod \"%s\" was not loaded (its %s must extend Node)." % [mod_folder, MOD_SCRIPT])
			if mod is Object and not mod is RefCounted:
				mod.free()
			continue
		mod.name = mod_folder.validate_node_name()
		add_child(mod)
		mods.append(mod)
		if mod.has_method("setup"):
			mod.setup(self)
		if mod.has_method("settings_tab"):
			_add_settings_tab(mod, mod_folder)


#* Add a mod's settings tab, titled by its control's name, else by the mod's folder:
#? `settings_tab()` is called once, after `setup()`, and returns a Control (or null for no tab).
func _add_settings_tab(mod: Node, mod_folder: String) -> void:
	var tab: Variant = mod.settings_tab()
	if tab == null:
		return
	if not tab is Control:
		push_warning("Candy Database: the mod \"%s\" has no settings tab (its settings_tab() must return a Control)." % mod_folder)
		return
	var content: Control = tab
	var title_text := str(content.name)
	if title_text.is_empty():
		title_text = mod_folder.replace("_", " ")
	settings_dialog.add_mod_tab(title_text, content)


#* Run `action` once every leave check lets `leaving` go, else `cancel` (if given):
func _leave(leaving: Array, action: Callable, cancel := Callable()) -> void:
	for check in leave_checks:
		var retry := func() -> void: _leave(leaving, action, cancel)
		if not check.call(leaving, retry, cancel):
			return
	action.call()


#* Mods' unsaved changes, asked when the editor closes ("" if none):
func unsaved_status() -> String:
	var messages := PackedStringArray()
	for mod in mods:
		if is_instance_valid(mod) and mod.has_method("unsaved_status"):
			var message := str(mod.unsaved_status())
			if not message.is_empty():
				messages.append(message)
	return "\n".join(messages)


#* Editor saving - mods save too:
func save_external_data() -> void:
	for mod in mods:
		if is_instance_valid(mod) and mod.has_method("save_all"):
			mod.save_all()

# ---------------------------------------------------------------- Panes

#* Add a styled page after the others:
func _open_pane() -> Pane:
	var pane := Pane.new()
	pages_split.add_child(pane)
	panes.append(pane)
	if active_pane == null:
		active_pane = pane
	pane.back_button.pressed.connect(func() -> void: _go_back(pane))
	pane.forward_button.pressed.connect(func() -> void: _go_forward(pane))
	pane.close_button.pressed.connect(func() -> void: _leave([pane], func() -> void: _close_pane(pane)))
	pane.activated.connect(func() -> void: _set_active(pane))
	pane.link_clicked.connect(func(target: String) -> void: _on_link_clicked(target, pane))
	pane.set_font_size(int(DBSettings.get_value("font_size")))
	pane.apply_style(DBSettings.resolve_style(current_database))
	pane.update_buttons()
	_render_header(pane)
	_render_footer(pane)
	#Ł Equal widths:
	pages_split.split_offset = 0
	_update_panes()
	pane_opened.emit(pane)
	return pane


func _close_pane(pane: Pane) -> void:
	if panes.size() < 2 or not panes.has(pane):
		return
	panes.erase(pane)
	pane.queue_free()
	if active_pane == pane:
		active_pane = panes[0]
	_update_panes()


#* Back to the first page only, history cleared (database, version or language changed):
func _single_pane() -> void:
	while panes.size() > 1:
		_close_pane(panes[panes.size() - 1])
	active_pane = panes[0]
	active_pane.clear_history()


#* The page beside `pane`, opened if needed:
func _other_pane(pane: Pane) -> Pane:
	if panes.size() < MAX_PANES:
		return _open_pane()
	return panes[1 - panes.find(pane)]


#* The page beside `pane`, or null:
func _pane_beside(pane: Pane) -> Pane:
	if panes.size() < MAX_PANES or not panes.has(pane):
		return null
	return panes[1 - panes.find(pane)]


#* Open a page in `pane` or the page beside, once leave checks allow:
func _open_from(page_id: String, pane: Pane, beside: bool) -> void:
	var leaving: Array[Pane] = []
	var target := pane
	if beside:
		target = _pane_beside(pane)
	if target != null:
		leaving.append(target)
	_leave(leaving, func() -> void:
		if not is_instance_valid(pane) or not panes.has(pane):
			return
		if beside:
			navigate(page_id, _other_pane(pane))
		else:
			navigate(page_id, pane))


#* Open a page beside `pane`, like Ctrl+click:
func open_beside(pane: Pane, page_id: String) -> void:
	_open_from(page_id, pane, true)


func _set_active(pane: Pane) -> void:
	if active_pane == pane:
		return
	active_pane = pane
	_sync_tree()


#* Update close buttons and color markers:
func _update_panes() -> void:
	var split := panes.size() > 1
	for pane in panes:
		pane.set_closable(split)
		if split and bool(DBSettings.get_value("split_page_colors")):
			pane.set_marker(_pane_color(pane))
		else:
			pane.set_marker(Color.TRANSPARENT)
	_arrange_panes()
	_sync_tree()


#* Place the second page (left, right, above or below):
func _arrange_panes() -> void:
	var side := str(DBSettings.get_value("second_page_side"))
	pages_split.vertical = side == "Above" or side == "Below"
	if panes.size() < 2:
		return
	if side == "Left" or side == "Above":
		pages_split.move_child(panes[1], 0)
	else:
		pages_split.move_child(panes[1], 1)


#* A pane's marker color: the selection color, or second_page_color for the second page:
func _pane_color(pane: Pane) -> Color:
	if panes.find(pane) > 0 and bool(DBSettings.get_value("split_page_colors")):
		return second_page_color
	return selection_color


func _pane_font_color(pane: Pane) -> Color:
	if panes.find(pane) > 0 and bool(DBSettings.get_value("split_page_colors")):
		return DBSettings.contrast_color(second_page_color)
	return selection_font_color


#* Ctrl (Cmd on macOS) held - open beside:
func _beside_held() -> bool:
	if OS.get_name() == "macOS":
		return Input.is_key_pressed(KEY_META)
	return Input.is_key_pressed(KEY_CTRL)


# ---------------------------------------------------------------- Library

#* Rescan databases and reopen the current one:
func reload_library() -> void:
	image_cache.clear()
	databases = Library.scan()
	database_picker.clear()
	for database in databases:
		database_picker.add_item(database["title"])
	if databases.is_empty():
		_single_pane()
		current_database = {}
		version_picker.clear()
		language_picker.clear()
		version_data = {}
		_update_about_menu()
		_rebuild_tree()
		apply_style()
		active_pane.show_message("[center][b]No databases found.[/b][/center]\n\nDrop a database folder (one holding a [code]database.json[/code]) in the library folder, then choose [i]Database > Refresh[/i]:\n\n[code]%s[/code]" % Library.user_library_path())
		return
	var index := 0
	var wanted: String = DBSettings.get_value("last_database")
	for candidate in databases.size():
		if databases[candidate]["id"] == wanted:
			index = candidate
	database_picker.select(index)
	_select_database(index)


func _select_database(index: int) -> void:
	_single_pane()
	current_database = databases[index]
	DBSettings.set_value("last_database", current_database["id"])
	version_picker.clear()
	language_picker.clear()
	var versions: Array = current_database["versions"]
	for version: String in versions:
		version_picker.add_item(version)
	if versions.is_empty():
		current_version = ""
		current_language = ""
		version_data = {}
		_update_about_menu()
		_rebuild_tree()
		apply_style()
		active_pane.show_message("[center][b]%s[/b][/center]\n\nThis database has no version folder yet." % current_database["title"])
		return
	var pick := 0
	var hinted := Library.hinted_version(current_database)
	var last_versions: Dictionary = DBSettings.get_value("last_versions")
	var remembered: String = str(last_versions.get(current_database["id"], ""))
	if not hinted.is_empty():
		pick = versions.find(hinted)
	elif versions.has(remembered):
		pick = versions.find(remembered)
	version_picker.select(pick)
	_select_version(pick)


func _select_version(index: int) -> void:
	_single_pane()
	var versions: Array = current_database["versions"]
	current_version = versions[index]
	var last_versions: Dictionary = DBSettings.get_value("last_versions")
	last_versions[current_database["id"]] = current_version
	DBSettings.set_value("last_versions", last_versions)
	language_picker.clear()
	var preferred := str(DBSettings.get_value("preferred_language"))
	version_languages = Library.preferred_first(Library.languages(current_database, current_version), preferred)
	var languages := version_languages
	for language in languages:
		language_picker.add_item(Library.prettify(language))
	if languages.is_empty():
		current_language = ""
		version_data = {}
		_update_about_menu()
		_rebuild_tree()
		apply_style()
		active_pane.show_message("[center][b]%s %s[/b][/center]\n\nThis version has no language folder yet." % [current_database["title"], current_version])
		return
	var last_languages: Dictionary = DBSettings.get_value("last_languages")
	var remembered := str(last_languages.get(current_database["id"], ""))
	var pick := Library.pick_language(current_database, languages, remembered, preferred)
	if pick < 0:
		pick = 0
	language_picker.select(pick)
	_select_language(pick)


#* Reopen the language the settings point to (preferred language changed):
func reselect_language() -> void:
	if current_database.is_empty() or current_version.is_empty():
		return
	_select_version(maxi(0, current_database["versions"].find(current_version)))


func _select_language(index: int) -> void:
	_single_pane()
	current_language = version_languages[index]
	version_data = Library.load_version(current_database, current_version, current_language)
	_update_about_menu()
	search_edit.text = ""
	_rebuild_tree()
	apply_style()
	var pages: Dictionary = version_data["pages"]
	var last_pages: Dictionary = DBSettings.get_value("last_pages")
	var start: String = str(last_pages.get(_page_key(), ""))
	if not pages.has(start):
		start = str(current_database["home"])
	if not pages.has(start):
		start = version_data["first"]
	if start.is_empty():
		active_pane.show_message("[center][b]%s %s (%s)[/b][/center]\n\nThis language has no pages yet." % [current_database["title"], current_version, Library.prettify(current_language)])
		return
	navigate(start, active_pane)


func _page_key() -> String:
	return "%s/%s/%s" % [current_database["id"], current_version, current_language]


#* Pickers change every page - if one can't be left, the picker reverts:
func _on_database_picked(index: int) -> void:
	var previous := databases.find(current_database)
	_leave(panes.duplicate(), func() -> void: _select_database(index), func() -> void: database_picker.select(previous))


func _on_version_picked(index: int) -> void:
	var previous: int = current_database["versions"].find(current_version)
	_leave(panes.duplicate(), func() -> void: _select_version(index), func() -> void: version_picker.select(previous))


#* Remember only picked languages, so preferred / default ones still apply elsewhere:
func _on_language_picked(index: int) -> void:
	var previous := version_languages.find(current_language)
	_leave(panes.duplicate(), func() -> void:
		var last_languages: Dictionary = DBSettings.get_value("last_languages")
		last_languages[current_database["id"]] = version_languages[index]
		DBSettings.set_value("last_languages", last_languages)
		_select_language(index),
		func() -> void: language_picker.select(previous))


# ---------------------------------------------------------------- Navigation

#* Show a page in `pane` (the active one by default):
func navigate(page_id: String, pane: Pane = null, record := true) -> void:
	if pane == null:
		pane = active_pane
	var pages: Dictionary = version_data.get("pages", {})
	if not pages.has(page_id):
		pane.show_message("[b]Page not found:[/b] [code]%s[/code]" % page_id)
		_sync_tree()
		return
	pane.current_page = page_id
	if record:
		pane.record(page_id)
	var last_pages: Dictionary = DBSettings.get_value("last_pages")
	last_pages[_page_key()] = page_id
	DBSettings.set_value("last_pages", last_pages)
	_render(pane)
	pane.update_buttons()
	_sync_tree(pane)


func _go_back(pane: Pane) -> void:
	_set_active(pane)
	if not pane.can_go_back():
		return
	_leave([pane], func() -> void:
		if is_instance_valid(pane) and pane.can_go_back():
			pane.history_index -= 1
			navigate(pane.history[pane.history_index], pane, false))


func _go_forward(pane: Pane) -> void:
	_set_active(pane)
	if not pane.can_go_forward():
		return
	_leave([pane], func() -> void:
		if is_instance_valid(pane) and pane.can_go_forward():
			pane.history_index += 1
			navigate(pane.history[pane.history_index], pane, false))


#* List the language's About pages, hidden if none:
func _update_about_menu() -> void:
	var popup := about_menu.get_popup()
	popup.clear()
	about_pages.clear()
	var pages: Dictionary = version_data.get("pages", {})
	for page_id: String in version_data.get("about", []):
		popup.add_item(str(pages[page_id]["title"]), ABOUT_FIRST_ID + about_pages.size())
		about_pages.append(page_id)
	about_menu.visible = not about_pages.is_empty()


func _on_link_clicked(target: String, pane: Pane) -> void:
	if target.begins_with("page:"):
		var page_id := target.substr(5).strip_edges()
		var beside := _beside_held()
		if not beside:
			_set_active(pane)
		_open_from(page_id, pane, beside)
	elif target.begins_with("https://") or target.begins_with("http://"):
		pending_link = target
		link_dialog.dialog_text = "Open this link in your browser?\n\n%s" % target
		link_dialog.popup_centered()
	elif target.begins_with(IMAGE_LINK):
		_show_image(target.substr(IMAGE_LINK.length()))


#* Open the image viewer on a view image (its `candydb://` path):
func _show_image(virtual_path: String) -> void:
	for cached: Dictionary in image_cache.values():
		if cached["path"] != virtual_path:
			continue
		var texture: Texture2D = cached["texture"]
		image_dialog.title = str(cached["file"]).get_file()
		image_view.texture = texture
		image_scroll.scroll_horizontal = 0
		image_scroll.scroll_vertical = 0
		image_dialog.popup_centered_clamped(Vector2i(texture.get_size()) + IMAGE_DIALOG_MARGIN, 0.9)
		return


# ---------------------------------------------------------------- Page

#* Show the pane's page from its file, from the top or keeping the scroll:
func _render(pane: Pane, keep_scroll := false) -> void:
	var pages: Dictionary = version_data["pages"]
	var page: Dictionary = pages[pane.current_page]
	var file := FileAccess.open(page["file"], FileAccess.READ)
	if file == null:
		pane.show_text("[b]Could not read[/b] [code]%s[/code]" % page["file"])
		return
	var parsed := Library.parse_page(file.get_as_text())
	var shown := _prepare_body(str(parsed["body"]), str(page["file"]).get_base_dir(), pane)
	if keep_scroll:
		pane.update_text(shown)
	else:
		pane.show_text(shown)


#* Show unsaved page text (the whole file) in `pane`, keeping the scroll:
func preview_text(pane: Pane, page_text: String) -> void:
	var pages: Dictionary = version_data.get("pages", {})
	if not pages.has(pane.current_page):
		return
	var parsed := Library.parse_page(page_text)
	pane.update_text(_prepare_body(str(parsed["body"]), str(pages[pane.current_page]["file"]).get_base_dir(), pane))


#* Reload the language's pages (one was saved), keeping each pane's scroll:
func reload_pages() -> void:
	if current_database.is_empty() or current_version.is_empty() or current_language.is_empty():
		return
	version_data = Library.load_version(current_database, current_version, current_language)
	_update_about_menu()
	_rebuild_tree()
	var pages: Dictionary = version_data["pages"]
	for pane in panes:
		if pages.has(pane.current_page):
			_render(pane, true)


#* The database's text look, for mods showing BBCode:
#? {"text_color", "link_color", "code_color", "background_color", "font_size", "tags" (see _resolved_tags())}.
func text_look() -> Dictionary:
	var style := DBSettings.resolve_style(current_database)
	var tags := _resolved_tags()
	var link_color: Color = style["link_color"]
	if tags.has("url") and tags["url"]["color"].a > 0.0:
		link_color = tags["url"]["color"]
	var code_color: Color = style["code_color"]
	if tags.has("code") and tags["code"]["color"].a > 0.0:
		code_color = tags["code"]["color"]
	return {
		"text_color": style["text_color"],
		"background_color": style["background_color"],
		"link_color": link_color,
		"code_color": code_color,
		"font_size": int(DBSettings.get_value("font_size")),
		"tags": tags,
	}


#* The database's tags as shown:
#? {name: {"color" (transparent if none or style ignored), "bold", "italic"}}.
func _resolved_tags() -> Dictionary:
	var resolved: Dictionary = {}
	var tags: Dictionary = current_database.get("tags", {})
	var show_colors := current_database.is_empty() or not DBSettings.style_is_ignored(str(current_database["id"]))
	var background: Color = DBSettings.resolve_style(current_database)["background_color"]
	var dark_page := background.get_luminance() < 0.5
	for tag_name: String in tags:
		var tag: Dictionary = tags[tag_name]
		var color := Color.TRANSPARENT
		if show_colors:
			color = _tag_color(tag, dark_page, Color.TRANSPARENT)
		resolved[tag_name] = {
			"color": color,
			"bold": str(tag.get("bold", "0")) == "1",
			"italic": str(tag.get("italic", "0")) == "1",
		}
	return resolved


#* Show the header (Database_Library.header_file()), unless hidden in the View menu:
func _render_header(pane: Pane) -> void:
	var file_path := ""
	if not current_database.is_empty() and not current_version.is_empty() and not current_language.is_empty() and bool(DBSettings.get_value("show_header")):
		file_path = Library.header_file(current_database, current_version, current_language)
	var file: FileAccess = null
	if not file_path.is_empty():
		file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		pane.show_header("", false)
		return
	pane.set_header_scrolls(bool(current_database.get("header_scrolls", true)))
	var parsed := Library.parse_page(file.get_as_text())
	pane.show_header(_prepare_body(str(parsed["body"]), file_path.get_base_dir(), pane), true)


#* Show the footer (Database_Library.footer_file()), unless hidden in the View menu:
func _render_footer(pane: Pane) -> void:
	var file_path := ""
	if not current_database.is_empty() and not current_version.is_empty() and not current_language.is_empty() and bool(DBSettings.get_value("show_footer")):
		file_path = Library.footer_file(current_database, current_version, current_language)
	var file: FileAccess = null
	if not file_path.is_empty():
		file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		pane.show_footer("", false)
		return
	pane.set_footer_scrolls(bool(current_database.get("footer_scrolls", true)))
	var parsed := Library.parse_page(file.get_as_text())
	pane.show_footer(_prepare_body(str(parsed["body"]), file_path.get_base_dir(), pane), true)


#* Prepare BBCode for the label - color links and [code], apply database tags, load images:
func _prepare_body(text: String, page_dir: String, pane: Pane) -> String:
	var out := text
	var look := text_look()
	var tags: Dictionary = look["tags"]
	var link_color: Color = look["link_color"]
	out = url_regex.sub(out, "[color=#%s][u][url$1]" % link_color.to_html(false), true)
	out = out.replace("[/url]", "[/url][/u][/color]")
	var code_color: Color = look["code_color"]
	out = out.replace("[code]", "[color=#%s][code]" % code_color.to_html(false))
	out = out.replace("[/code]", "[/code][/color]")
	for tag_name: String in tags:
		if Library.RESTYLED_TAGS.has(tag_name):
			continue
		var tag: Dictionary = tags[tag_name]
		var opening := ""
		var closing := ""
		var color: Color = tag["color"]
		if color.a > 0.0:
			opening += "[color=#%s]" % color.to_html(false)
			closing = "[/color]" + closing
		if tag["bold"]:
			opening += "[b]"
			closing = "[/b]" + closing
		if tag["italic"]:
			opening += "[i]"
			closing = "[/i]" + closing
		out = out.replace("[%s]" % tag_name, opening).replace("[/%s]" % tag_name, closing)
	#Ł Images last, so their own links aren't styled:
	var shown := ""
	var cursor := 0
	for found in image_regex.search_all(out):
		shown += out.substr(cursor, found.get_start() - cursor)
		var in_link := url_regex.search_all(out.substr(0, found.get_start())).size() > out.substr(0, found.get_start()).count("[/url]")
		shown += _image_tag(found.get_string(1), found.get_string(2).strip_edges(), page_dir, pane, in_link)
		cursor = found.get_end()
	return shown + out.substr(cursor)


#* Tag color - `dark_color` on a dark page, else `color`, else `fallback`:
func _tag_color(tag: Dictionary, dark_page: bool, fallback: Color) -> Color:
	var text := str(tag.get("color", ""))
	if dark_page and not str(tag.get("dark_color", "")).is_empty():
		text = str(tag["dark_color"])
	if text.is_empty():
		return fallback
	return DBSettings.parse_color(text, fallback)


#* An `[img]` tag for a database file, linked to the image viewer when shrunk:
func _image_tag(options: String, source: String, page_dir: String, pane: Pane, in_link: bool) -> String:
	var resolved := _resolve_image(source, page_dir)
	if resolved.is_empty():
		return "[i](image not found: %s)[/i]" % source.get_file()
	if not image_cache.has(resolved):
		var loaded := Library.load_texture(resolved)
		if loaded == null:
			return "[i](image could not be read: %s)[/i]" % source.get_file()
		#Ł Register the texture under a path of its own (the label only loads resources):
		image_counter += 1
		var virtual_path := Library.VIEW_IMAGE_PREFIX + "image_%d.png" % image_counter
		loaded.take_over_path(virtual_path)
		image_cache[resolved] = {"path": virtual_path, "texture": loaded, "file": resolved}
	var cached: Dictionary = image_cache[resolved]
	var texture: Texture2D = cached["texture"]
	var sized := options.contains("width") or options.contains("height") or options.begins_with("=")
	var shrunk := false
	if not sized and texture.get_width() > pane.content_width():
		options += " width=100%"
		shrunk = true
	elif sized:
		shrunk = _shown_width(options, texture, pane) < texture.get_width()
	var tag := "[img%s]%s[/img]" % [options, cached["path"]]
	#% Shrunk, and not already a link:
	if shrunk and not in_link:
		return "[url=%s%s]%s[/url]" % [IMAGE_LINK, cached["path"], tag]
	return tag


#* The width an `[img]` with size options shows `texture` at:
func _shown_width(options: String, texture: Texture2D, pane: Pane) -> float:
	var width := ""
	var height := ""
	#¦ 1. [img=WxH] or [img=W]:
	if options.begins_with("="):
		var sizes := options.substr(1).strip_edges().split(" ")[0].split("x")
		width = sizes[0]
		if sizes.size() > 1:
			height = sizes[1]
	#¦ 2. [img width=W height=H]:
	else:
		for option in options.strip_edges().split(" ", false):
			if option.begins_with("width="):
				width = option.substr(6)
			elif option.begins_with("height="):
				height = option.substr(7)
	var shown_width := _image_length(width, pane.content_width())
	if shown_width >= 0.0:
		return shown_width
	var shown_height := _image_length(height, pane.content_width())
	#% Height only - the width keeps the image's proportions:
	if shown_height >= 0.0:
		return texture.get_width() * shown_height / texture.get_height()
	return texture.get_width()


#* An `[img]` width or height in pixels (`percent_of` is 100%), or -1 when not set:
func _image_length(value: String, percent_of: float) -> float:
	value = value.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if value.ends_with("%") and value.trim_suffix("%").is_valid_float():
		return percent_of * value.trim_suffix("%").to_float() / 100.0
	if value.is_valid_float() and value.to_float() > 0.0:
		return value.to_float()
	return -1.0


#* The database file an `[img]` source points to, or "":
func _resolve_image(source: String, page_dir: String) -> String:
	if source.contains("://") and not source.begins_with("res://"):
		return ""
	if source.begins_with("res://"):
		if FileAccess.file_exists(source):
			return source
		return ""
	var database_path: String = current_database["path"]
	for folder in [page_dir, database_path.path_join(current_version).path_join(current_language), database_path.path_join(current_version), database_path]:
		var candidate := str(folder).path_join(source).simplify_path()
		if candidate.begins_with(database_path) and FileAccess.file_exists(candidate):
			return candidate
	return ""


# ---------------------------------------------------------------- Sidebar

func _rebuild_tree() -> void:
	marked_items.clear()
	tree.clear()
	page_items.clear()
	var root := tree.create_item()
	if version_data.is_empty():
		return
	var query := search_edit.text.strip_edges().to_lower()
	building_tree = true
	if query.is_empty():
		_add_nodes(root, version_data["tree"])
	else:
		_add_matches(root, query)
	building_tree = false
	_sync_tree()


#* Remember folded categories, per database:
func _on_item_collapsed(item: TreeItem) -> void:
	if building_tree or current_database.is_empty():
		return
	if not item.has_meta("fold_key"):
		return
	var key = item.get_meta("fold_key")
	var folded: Dictionary = DBSettings.get_value("folded_categories")
	var database_id := str(current_database["id"])
	var keys: Dictionary = folded.get(database_id, {})
	if item.collapsed:
		keys[str(key)] = true
	else:
		keys.erase(str(key))
	folded[database_id] = keys
	DBSettings.set_value("folded_categories", folded)


#* Editor icon for the page list, redrawn in the theme's list icon color if any:
func _list_icon(icon_name: String, icon_type := "EditorIcons", color_name := "tree_icon") -> Texture2D:
	var icon := get_theme_icon(icon_name, icon_type)
	if not has_theme_color(color_name, "CandyDatabase") or icon == null:
		return icon
	var color := get_theme_color(color_name, "CandyDatabase")
	var key := "%s/%s/%s" % [icon_type, icon_name, color.to_html()]
	if not icon_cache.has(key):
		var image := icon.get_image()
		if image == null:
			return icon
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				image.set_pixel(x, y, Color(color, image.get_pixel(x, y).a * color.a))
		icon_cache[key] = ImageTexture.create_from_image(image)
	return icon_cache[key]


#* Fold arrows - the arrow color, else the list icon color:
func _apply_arrow_icons() -> void:
	icon_cache.clear()
	var color_name := "tree_icon"
	if has_theme_color("tree_arrow", "CandyDatabase"):
		color_name = "tree_arrow"
	for arrow_name in ["arrow", "arrow_collapsed", "arrow_collapsed_mirrored"]:
		if has_theme_color(color_name, "CandyDatabase"):
			tree.add_theme_icon_override(arrow_name, _list_icon(arrow_name, "Tree", color_name))
		else:
			tree.remove_theme_icon_override(arrow_name)


#* Hide the Tree's selection look - pages shown are marked in their pane's color instead:
func _apply_selection_look() -> void:
	for box_name in ["selected", "selected_focus"]:
		tree.remove_theme_stylebox_override(box_name)
	var box := tree.get_theme_stylebox("selected")
	if box is StyleBoxFlat:
		selection_color = box.bg_color
	else:
		selection_color = get_theme_color("accent_color", "Editor")
	selection_font_color = tree.get_theme_color("font_selected_color")
	second_page_color = DBSettings.resolve_second_page_color(current_database)
	for box_name in ["selected", "selected_focus"]:
		tree.add_theme_stylebox_override(box_name, StyleBoxEmpty.new())	#/ The selection only receives clicks


#* Folders fold only with their arrow; a page standing in for a category opens when clicked:
func _add_nodes(parent: TreeItem, nodes: Array) -> void:
	var folded: Dictionary = DBSettings.get_value("folded_categories")
	var keys: Dictionary = folded.get(str(current_database.get("id", "")), {})
	for node: Dictionary in nodes:
		var item := tree.create_item(parent)
		item.set_text(0, node["title"])
		if node["kind"] == "page":
			item.set_metadata(0, node["id"])
			item.set_icon(0, _list_icon("Script"))
			page_items[node["id"]] = item
			if node.has("children"):
				_add_nodes(item, node["children"])
				item.set_meta("fold_key", "page:" + str(node["id"]))
				item.collapsed = keys.has(item.get_meta("fold_key"))
		else:
			item.set_icon(0, _list_icon("Folder"))
			_add_nodes(item, node["children"])
			item.set_meta("fold_key", "category:" + str(node["id"]))
			item.collapsed = keys.has(item.get_meta("fold_key"))


func _add_matches(root: TreeItem, query: String) -> void:
	var pages: Dictionary = version_data["pages"]
	var titles: Array[String] = []
	var bodies: Array[String] = []
	for page_id: String in pages:
		var page: Dictionary = pages[page_id]
		if page.get("about", false):
			continue
		if str(page["title"]).to_lower().contains(query):
			titles.append(page_id)
		elif str(page["search"]).contains(query):
			bodies.append(page_id)
	titles.sort()
	bodies.sort()
	for page_id in titles + bodies:
		var page: Dictionary = pages[page_id]
		var item := tree.create_item(root)
		item.set_text(0, page["title"])
		item.set_metadata(0, page_id)
		item.set_icon(0, _list_icon("Script"))
		item.set_tooltip_text(0, _snippet(str(page["search"]), query))
		page_items[page_id] = item


func _snippet(text: String, query: String) -> String:
	var position := text.find(query)
	if position < 0:
		return ""
	var start := maxi(0, position - 40)
	return "..." + text.substr(start, 100).replace("\n", " ") + "..."


#* Mark each pane's page in its color (active pane wins), scroll to `scroll_pane`'s page:
func _sync_tree(scroll_pane: Pane = null) -> void:
	for item in marked_items:
		item.clear_custom_bg_color(0)
		item.clear_custom_color(0)
	marked_items.clear()
	var ordered: Array[Pane] = []
	for pane in panes:
		if pane != active_pane:
			ordered.append(pane)
	if active_pane != null:
		ordered.append(active_pane)
	for pane in ordered:
		if not page_items.has(pane.current_page):
			continue
		var item: TreeItem = page_items[pane.current_page]
		item.set_custom_bg_color(0, _pane_color(pane))
		var font_color := _pane_font_color(pane)
		if font_color.a > 0.0:
			item.set_custom_color(0, font_color)
		marked_items.append(item)
	if scroll_pane != null and page_items.has(scroll_pane.current_page):
		tree.scroll_to_item(page_items[scroll_pane.current_page])


#* Open a page in the main pane, or with Ctrl in the second:
func _on_tree_selected() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	#Ł Once the Tree is done selecting:
	#? Cleared after each click, so a page can be clicked again.
	tree.deselect_all.call_deferred()
	var page_id: Variant = item.get_metadata(0)
	#% Folder (kept selectable, since the Tree folds an unselectable item when its name is clicked):
	if page_id == null:
		return
	_open_from(str(page_id), panes[0], _beside_held())


# ---------------------------------------------------------------- Appearance

func apply_layout() -> void:
	var on_right: bool = DBSettings.get_value("sidebar_side") == "Right"
	if on_right:
		body.move_child(sidebar, 1)
	else:
		body.move_child(sidebar, 0)
	var popup := view_menu.get_popup()
	popup.set_item_checked(popup.get_item_index(Menu.SIDEBAR_LEFT), not on_right)
	popup.set_item_checked(popup.get_item_index(Menu.SIDEBAR_RIGHT), on_right)
	var size_value := int(DBSettings.get_value("font_size"))
	for pane in panes:
		pane.set_font_size(size_value)
	popup.set_item_checked(popup.get_item_index(Menu.SHOW_HEADER), bool(DBSettings.get_value("show_header")))
	popup.set_item_checked(popup.get_item_index(Menu.SHOW_FOOTER), bool(DBSettings.get_value("show_footer")))
	appearance_changed.emit()


#* Apply the database's theme, page colors and background (else the user's):
func apply_style() -> void:
	theme = DBSettings.resolve_theme(current_database)
	var style := DBSettings.resolve_style(current_database)
	for pane in panes:
		pane.apply_style(style)
		_render_header(pane)
		_render_footer(pane)
	_apply_arrow_icons()
	_apply_selection_look()
	_rebuild_tree()
	_update_panes()
	appearance_changed.emit()


func _on_settings_changed() -> void:
	apply_layout()
	apply_style()
	for pane in panes:
		if not pane.current_page.is_empty():
			_render(pane)


func _open_settings() -> void:
	settings_dialog.open(databases)


func _change_font_size(amount: int) -> void:
	var size_value := DEFAULT_FONT_SIZE
	if amount != 0:
		size_value = clampi(int(DBSettings.get_value("font_size")) + amount, 8, 40)
	DBSettings.set_value("font_size", size_value)
	apply_layout()


func _on_menu_pressed(id: int) -> void:
	#% About page - opens like a link:
	if id >= ABOUT_FIRST_ID:
		_open_from(about_pages[id - ABOUT_FIRST_ID], active_pane, _beside_held())
		return
	match id:
		Menu.REFRESH:
			_leave(panes.duplicate(), reload_library)
		Menu.OPEN_FOLDER:
			DirAccess.make_dir_recursive_absolute(Library.user_library_path())
			OS.shell_open(Library.user_library_path())
		Menu.SETTINGS:
			_open_settings()
		Menu.SIDEBAR_LEFT:
			DBSettings.set_value("sidebar_side", "Left")
			apply_layout()
		Menu.SIDEBAR_RIGHT:
			DBSettings.set_value("sidebar_side", "Right")
			apply_layout()
		Menu.TOGGLE_SIDEBAR:
			sidebar.visible = not sidebar.visible
			var popup := view_menu.get_popup()
			popup.set_item_checked(popup.get_item_index(Menu.TOGGLE_SIDEBAR), sidebar.visible)
		Menu.SHOW_HEADER:
			DBSettings.set_value("show_header", not bool(DBSettings.get_value("show_header")))
			var header_popup := view_menu.get_popup()
			header_popup.set_item_checked(header_popup.get_item_index(Menu.SHOW_HEADER), bool(DBSettings.get_value("show_header")))
			for pane in panes:
				_render_header(pane)
		Menu.SHOW_FOOTER:
			DBSettings.set_value("show_footer", not bool(DBSettings.get_value("show_footer")))
			var footer_popup := view_menu.get_popup()
			footer_popup.set_item_checked(footer_popup.get_item_index(Menu.SHOW_FOOTER), bool(DBSettings.get_value("show_footer")))
			for pane in panes:
				_render_footer(pane)
		Menu.ZOOM_IN:
			_change_font_size(1)
		Menu.ZOOM_OUT:
			_change_font_size(-1)
		Menu.ZOOM_RESET:
			_change_font_size(0)
