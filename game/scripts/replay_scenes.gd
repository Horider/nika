extends RefCounted
## Prepared scene entries use the real flow, including prior choices and events.
## No rendered playback or player's save file is touched while building this list.
const Flow = preload("res://scripts/story_flow.gd")
var catalog: Dictionary
var cache: Dictionary = {}

func _init(data: Dictionary) -> void:
	catalog = data

func entries(day: int) -> Array:
	if cache.has(day): return cache[day]
	var found := {}
	for promised in ([false, true] if day == 2 else [false]):
		var model := Flow.new(catalog)
		model.new_game(day)
		for step in 250:
			if model.state.finished or int(model.state.day) != day: break
			var page: Dictionary = model.current()
			var key: int = int(page.beat) if day == 1 else int(page.scene)
			if not found.has(key) and page.id not in Flow.OMITTED_SUMMARY_PAGES:
				var checkpoint: Dictionary = model.snapshot()
				checkpoint.history = []
				found[key] = {"day":day, "scene":key, "page_id":page.id,
					"title":str(model.strings[page.id].get("title", "Сцена")), "state":checkpoint}
			if page.choices.is_empty():
				if not model.advance(): break
			else:
				var choice: String = str(page.choices[0].value)
				if promised and page.choices[0].kind == "choice-results": choice = "promise"
				if not model.choose(choice): break
	var keys := found.keys()
	keys.sort()
	if day == 2:
		# The promised handoff occurs after the recording, before the report.
		keys = [0,1,2,3,4,5,7,8,9,6,10]
	var result := []
	for key in keys:
		if found.has(key): result.append(found[key])
	cache[day] = result
	return result
