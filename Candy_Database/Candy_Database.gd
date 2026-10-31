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
extends EditorPlugin


const DatabaseView = preload("Scripts/Database_View.gd")
const DBSettings = preload("Scripts/Database_Settings.gd")

var view: Control = null


func _enter_tree() -> void:
	DBSettings.ensure_defaults()
	view = DatabaseView.new()
	EditorInterface.get_editor_main_screen().add_child(view)
	_make_visible(false)


func _exit_tree() -> void:
	if view != null:
		view.queue_free()
		view = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if view != null:
		view.visible = visible


#* What the tab's mods haven't saved, asked when the editor closes:
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and view != null:
		return view.unsaved_status()
	return ""


func _save_external_data() -> void:
	if view != null:
		view.save_external_data()


func _get_plugin_name() -> String:
	return DBSettings.tab_name()


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Help", "EditorIcons")
