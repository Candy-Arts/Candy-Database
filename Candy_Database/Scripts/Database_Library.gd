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


const INFO_FILE := "database.json"
const PAGE_EXTENSIONS: Array[String] = ["txt"]
const HEADER_FILE := "_header.txt"
const FOOTER_FILE := "_footer.txt"
const ABOUT_FOLDER := "_About"
const USER_FOLDER := "Candy_Database/Databases"
const DEFAULT_LANGUAGE := "English"
const NO_ORDER := 100000
const MAX_DEPTH := 8
#^ Godot's BBCode tags, which database tags can't be named:
const BUILT_IN_TAGS: Array[String] = ["b", "i", "u", "s", "code", "char", "p", "br", "hr", "center", "left", "right", "fill", "indent", "url", "hint", "img", "font", "font_size", "opentype_features", "lang", "table", "cell", "ul", "ol", "lb", "rb", "lrm", "rlm", "lre", "rle", "lro", "rlo", "pdf", "alm", "lri", "rli", "fsi", "pdi", "zwj", "zwnj", "wj", "shy", "color", "bgcolor", "fgcolor", "outline_size", "outline_color", "dropcap", "wave", "tornado", "shake", "fade", "rainbow", "pulse"]
#^ ...except these, which a database can restyle:
const RESTYLED_TAGS: Array[String] = ["url", "code"]

#^ Paths of the textures the view registers for [img] (see disarm()):
const VIEW_IMAGE_PREFIX := "candydb://"

static var _tag_regex: RegEx = null
static var _font_option_regex: RegEx = null
static var _font_size_regex: RegEx = null


#* User library folder, shared by every project:
static func user_library_path() -> String:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_paths().get_data_dir().path_join(USER_FOLDER)
	return OS.get_user_data_dir().path_join(USER_FOLDER)


#* Every database in the user library and the project, sorted by title:
static func scan() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Dictionary = {}
	var roots: Array[String] = [user_library_path(), "res://"]
	for root in roots:
		_scan_folder(root, found, seen, 0)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return found


static func _scan_folder(path: String, found: Array[Dictionary], seen: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH or not DirAccess.dir_exists_absolute(path):
		return
	if FileAccess.file_exists(path.path_join(INFO_FILE)):
		_add_database(path, found, seen)
		return
	for folder in DirAccess.get_directories_at(path):
		if folder.begins_with("."):
			continue
		_scan_folder(path.path_join(folder), found, seen, depth + 1)


static func _add_database(path: String, found: Array[Dictionary], seen: Dictionary) -> void:
	var info := read_json(path.path_join(INFO_FILE))
	var id: String = str(info.get("id", path.get_file()))
	if seen.has(id):
		push_warning("Candy Database: two databases share the id \"%s\" (%s); only the first is used." % [id, path])
		return
	seen[id] = true
	var versions: Array[String] = []
	for folder in DirAccess.get_directories_at(path):
		if not folder.begins_with(".") and not folder.begins_with("_"):
			versions.append(folder)
	versions.sort_custom(version_is_newer)
	var style: Dictionary = {}
	if info.get("style") is Dictionary:
		style = info["style"]
	var theme_info: Dictionary = {}
	if info.get("theme") is Dictionary:
		theme_info = info["theme"]
	var hint: Dictionary = {}
	if info.get("version_hint") is Dictionary:
		hint = info["version_hint"]
	var tags: Dictionary = {}
	if info.get("tags") is Dictionary:
		for tag_name: String in info["tags"]:
			if not info["tags"][tag_name] is Dictionary:
				continue
			if not tag_name.is_valid_identifier() or (BUILT_IN_TAGS.has(tag_name) and not RESTYLED_TAGS.has(tag_name)):
				push_warning("Candy Database: \"%s\" can't be a tag of the database \"%s\" (a tag is a name made of letters, digits and _, and not one of Godot's own BBCode tags)." % [tag_name, id])
				continue
			tags[tag_name] = info["tags"][tag_name]
	found.append({
		"id": id,
		"title": str(info.get("title", prettify(path.get_file()))),
		"description": str(info.get("description", "")),
		"home": str(info.get("home", "")),
		"default_language": str(info.get("default_language", DEFAULT_LANGUAGE)),
		"path": path,
		"versions": versions,
		"style": style,
		"theme": theme_info,
		"theme_name": str(info.get("theme_name", "")),
		"header": str(info.get("header", "")),
		"header_scrolls": str(info.get("header_scrolls", "1")) != "0",
		"footer": str(info.get("footer", "")),
		"footer_scrolls": str(info.get("footer_scrolls", "1")) != "0",
		"version_hint": hint,
		"tags": tags,
	})


static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		return data
	return {}


#* Version `a` newer than `b` ("1.10.0" > "1.9.0", "v" ignored):
static func version_is_newer(a: String, b: String) -> bool:
	var parts_a := a.trim_prefix("v").split(".")
	var parts_b := b.trim_prefix("v").split(".")
	for index in maxi(parts_a.size(), parts_b.size()):
		var part_a := "0"
		var part_b := "0"
		if index < parts_a.size():
			part_a = parts_a[index]
		if index < parts_b.size():
			part_b = parts_b[index]
		if part_a == part_b:
			continue
		if part_a.is_valid_int() and part_b.is_valid_int():
			return int(part_a) > int(part_b)
		return part_a.naturalnocasecmp_to(part_b) > 0
	return false


#* Installed version (from `version_hint`), if the database has it, else "":
static func hinted_version(database: Dictionary) -> String:
	var hint: Dictionary = database["version_hint"]
	var file_path: String = str(hint.get("file", ""))
	if file_path.is_empty():
		return ""
	var value: Variant = read_json(file_path)
	for key in str(hint.get("key", "version")).split("."):
		if value is Dictionary and value.has(key):
			value = value[key]
		else:
			return ""
	var wanted := str(value).trim_prefix("v")
	for version: String in database["versions"]:
		if version.trim_prefix("v") == wanted:
			return version
	return ""


#* A version's languages, sorted by name:
static func languages(database: Dictionary, version: String) -> Array[String]:
	var found: Array[String] = []
	for folder in DirAccess.get_directories_at(str(database["path"]).path_join(version)):
		if not folder.begins_with(".") and not folder.begins_with("_"):
			found.append(folder)
	found.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0)
	return found


#* `languages` with the preferred ones (comma-separated) first, in typed order:
static func preferred_first(languages: Array[String], preferred: String) -> Array[String]:
	var ordered: Array[String] = []
	for entry in preferred.split(","):
		var key := _language_key(entry)
		if key.is_empty():
			continue
		for language in languages:
			if _language_key(language) == key and not ordered.has(language):
				ordered.append(language)
	for language in languages:
		if not ordered.has(language):
			ordered.append(language)
	return ordered


#* Index of the language to open (-1 if none fits):
#? `remembered`, else the first `preferred` (comma-separated), else `default_language`.
static func pick_language(database: Dictionary, languages: Array[String], remembered: String, preferred: String) -> int:
	var wanted: Array[String] = [remembered]
	for entry in preferred.split(","):
		wanted.append(entry)
	wanted.append(str(database["default_language"]))
	for candidate in wanted:
		var key := _language_key(candidate)
		if key.is_empty():
			continue
		for index in languages.size():
			if _language_key(languages[index]) == key:
				return index
	return -1


static func _language_key(language: String) -> String:
	return language.replace("_", " ").strip_edges().to_lower()


#* Header file - the language folder's, else the version's, else the database's ("" if none):
static func header_file(database: Dictionary, version: String, language: String) -> String:
	return _band_file(database, version, language, str(database["header"]), HEADER_FILE)


#* Footer file - found like the header's:
static func footer_file(database: Dictionary, version: String, language: String) -> String:
	return _band_file(database, version, language, str(database["footer"]), FOOTER_FILE)


#* A header's or footer's file - the language folder's, else the version's, else the database's ("" if none):
#? file_name - the name database.json gives it ("" for default_name).
static func _band_file(database: Dictionary, version: String, language: String, file_name: String, default_name: String) -> String:
	var database_path := str(database["path"])
	if file_name.is_empty():
		file_name = default_name
	for folder in [database_path.path_join(version).path_join(language), database_path.path_join(version), database_path]:
		var candidate := str(folder).path_join(file_name).simplify_path()
		if candidate.begins_with(database_path) and FileAccess.file_exists(candidate):
			return candidate
	return ""


#* Reads one language:
#? {"tree", "pages": id → page, "first": first page id, "about": About ids}.
#? Tree node: {"kind": "category", "title", "order", "children"} or {"kind": "page", "id",
#? "title", "order", "file"}, plus "children" for a page standing in for a category.
#? "pages" entry: {"title", "file", "search" (plain lower-case text)}, plus "about" for About pages.
static func load_version(database: Dictionary, version: String, language: String) -> Dictionary:
	var pages: Dictionary = {}
	var tree := _read_folder(str(database["path"]).path_join(version).path_join(language), "", pages)
	var about := _read_about(database, version, language, pages)
	return {"tree": tree, "pages": pages, "first": first_page(tree), "about": about}


#* Adds the About pages to `pages`, returns their ids in menu order:
static func _read_about(database: Dictionary, version: String, language: String, pages: Dictionary) -> Array[String]:
	var database_path := str(database["path"])
	var by_name: Dictionary = {}
	#? Broadest first, so more specific pages replace it.
	for folder in [database_path, database_path.path_join(version), database_path.path_join(version).path_join(language)]:
		var about_folder := str(folder).path_join(ABOUT_FOLDER)
		if not DirAccess.dir_exists_absolute(about_folder):
			continue
		for file_name in DirAccess.get_files_at(about_folder):
			if file_name.begins_with("_") or not PAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
				continue
			var file_path := about_folder.path_join(file_name)
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file == null:
				continue
			var meta: Dictionary = parse_page(file.get_as_text())["meta"]
			var split := split_prefix(file_name.get_basename())
			var order: int = split["order"]
			if str(meta.get("order", "")).is_valid_int():
				order = int(meta["order"])
			by_name[split["name"]] = {
				"id": ABOUT_FOLDER + "/" + str(split["name"]),	#/ Can't clash with page ids, which never start with "_"
				"title": str(meta.get("title", prettify(str(split["name"])))),
				"order": order,
				"file": file_path,
			}
	var entries: Array = by_name.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		pages[entry["id"]] = {"title": entry["title"], "file": entry["file"], "search": "", "about": true}
		ids.append(entry["id"])
	return ids


static func _read_folder(folder: String, id_prefix: String, pages: Dictionary) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	#Ł Pages by base name, to match folders of the same name:
	var pages_by_name: Dictionary = {}
	for file_name in DirAccess.get_files_at(folder):
		if file_name.begins_with("_") or not PAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var file_path := folder.path_join(file_name)
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		var parsed := parse_page(file.get_as_text())
		var meta: Dictionary = parsed["meta"]
		var split := split_prefix(file_name.get_basename())
		var page_id: String = id_prefix + str(split["name"])
		var order: int = split["order"]
		if str(meta.get("order", "")).is_valid_int():
			order = int(meta["order"])
		var node := {
			"kind": "page",
			"id": page_id,
			"title": str(meta.get("title", prettify(str(split["name"])))),
			"order": order,
			"file": file_path,
		}
		if pages.has(page_id):
			push_warning("Candy Database: two pages share the id \"%s\"; only the first is used." % page_id)
			continue
		pages[page_id] = {"title": node["title"], "file": file_path, "search": plain_text(str(parsed["body"])).to_lower()}
		nodes.append(node)
		pages_by_name[file_name.get_basename()] = node
	for folder_name in DirAccess.get_directories_at(folder):
		if folder_name.begins_with(".") or folder_name.begins_with("_"):
			continue
		var split := split_prefix(folder_name)
		var children := _read_folder(folder.path_join(folder_name), id_prefix + str(split["name"]) + "/", pages)
		if children.is_empty():
			continue
		if pages_by_name.has(folder_name):
			pages_by_name[folder_name]["children"] = children
			continue
		nodes.append({"kind": "category", "id": id_prefix + str(split["name"]) + "/", "title": prettify(str(split["name"])), "order": split["order"], "children": children})
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return nodes


static func first_page(nodes: Array) -> String:
	for node: Dictionary in nodes:
		if node["kind"] == "page":
			return node["id"]
		var inner := first_page(node["children"])
		if not inner.is_empty():
			return inner
	return ""


#* Splits a page into {"meta", "body"}, meta being the leading `@key: value` lines:
static func parse_page(text: String) -> Dictionary:
	var meta: Dictionary = {}
	var lines := text.replace("\r\n", "\n").split("\n")
	var index := 0
	while index < lines.size() and lines[index].begins_with("@"):
		var line := lines[index].substr(1)
		var colon := line.find(":")
		if colon > 0:
			meta[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
		index += 1
	var body := "\n".join(lines.slice(index)).lstrip("\n")
	return {"meta": meta, "body": body}


#* "02_Installing_It" → {"order" = 2, "name" = "Installing_It"}, NO_ORDER without a prefix:
static func split_prefix(file_name: String) -> Dictionary:
	var digits := 0
	while digits < file_name.length() and file_name[digits].is_valid_int():
		digits += 1
	var rest := file_name.substr(digits).lstrip("_-. ")
	if digits == 0 or rest.is_empty():
		return {"order": NO_ORDER, "name": file_name}
	return {"order": int(file_name.substr(0, digits)), "name": rest}


static func prettify(file_name: String) -> String:
	return file_name.replace("_", " ")


#* Page text without BBCode tags, for search:
static func plain_text(body: String) -> String:
	if _tag_regex == null:
		_tag_regex = RegEx.create_from_string("\\[[^\\]]*\\]")
	return _tag_regex.sub(body, "", true)


#* Texture from an image file, read as image data:
#! Never load() it - a resource file can hold a script, which runs when it loads.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":
			error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"webp":
			error = image.load_webp_from_buffer(bytes)
		"svg":
			error = image.load_svg_from_buffer(bytes)
		"bmp":
			error = image.load_bmp_from_buffer(bytes)
		"tga":
			error = image.load_tga_from_buffer(bytes)
		"ktx":
			error = image.load_ktx_from_buffer(bytes)
	if error != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


#* BBCode with the tags that load a file shown as text, except the view's own images:
#! Godot loads the file of any tag starting with "img" or "font", and of a "font=" option - a resource file can hold a script, which runs when it loads.
static func disarm(bbcode: String) -> String:
	if _font_option_regex == null:
		_font_option_regex = RegEx.create_from_string("(^|\\s)font\\s*=")
		_font_size_regex = RegEx.create_from_string("^font_size=\\s*[0-9]+\\s*$")
	var out := ""
	var cursor := 0
	var start := bbcode.find("[")
	while start >= 0:
		var end := bbcode.find("]", start + 1)
		if end < 0:
			break
		var inner := bbcode.substr(start + 1, end - start - 1)
		if _loads_file(inner, bbcode.substr(end + 1, VIEW_IMAGE_PREFIX.length())):
			out += bbcode.substr(cursor, start - cursor) + "[lb]"
			cursor = start + 1
		start = bbcode.find("[", start + 1)
	return out + bbcode.substr(cursor)


#* A tag's inner text (`after` - the text that follows) makes the label load a file:
static func _loads_file(inner: String, after: String) -> bool:
	if inner.begins_with("img"):
		return after != VIEW_IMAGE_PREFIX
	if inner.begins_with("font"):
		return _font_size_regex.search(inner) == null
	return _font_option_regex.search(inner) != null
