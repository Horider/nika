extends RefCounted

## Pure story state. Rendering, opening history and loading never commit events.
var catalog: Dictionary
var state: Dictionary
var strings: Dictionary

func _init(data: Dictionary = {}) -> void:
	catalog = data if not data.is_empty() else JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/text.json"))
	new_game()

func new_game(day: int = 1) -> void:
	state = {
		"schema_version": 4, "day": day, "scene": 0, "index": 0,
		"day3_choices": {}, "nika_relation": 0,
		"promise_scene_done": false, "promise_resume_index": 0,
		"results": "", "promise": "", "listen": "", "finished": false,
		"entry_day": day, "events": {}, "history": [], "reports": {},
		"employer_trust": 100,
		"facts": {"results_state": "unselected", "results_promise": "none",
			"results_shown_to_nika": false, "listen_choice": "unselected",
			"audio_listening": "not_started", "hero_saw_bird_disappear": null,
			"hero_confirmed_bird_disappear": false, "bird_reply_in_video": "",
			"bird_video_saved": false, "nika_noticed_behaviour_mismatch": false,
			"heard_water_plan": false}
	}
	if day == 3:
		# Explicit standalone preview starts from a disclosed/witnessed Day2 preset.
		state.facts.merge({"results_state":"shown_now", "results_shown_to_nika":true, "hero_saw_bird_disappear":true, "bird_video_saved":true}, true)

func day3_key() -> String:
	var c: Dictionary = state.day3_choices
	return "|".join([str(state.facts.results_state), "yes" if state.facts.hero_saw_bird_disappear else "no", str(c.get("access","open")), str(c.get("tea","yes")), str(c.get("response","support")), str(c.get("report","work"))])

func variant_for(scene: int) -> String:
	if scene == 5:
		return "refuse" if state.results == "refused" else "promise" if state.results == "promise" else "base"
	if scene == 6:
		return "broken" if state.promise == "broken" else "base"
	if scene in [7, 9]:
		return "declined" if state.listen == "no" else "base"
	if scene == 8:
		return "unseen" if state.listen == "no" else "base"
	return "base"

func sequence() -> Array:
	if int(state.day) == 3:
		return catalog.day3[day3_key()]
	if int(state.day) == 1:
		return catalog.day1
	var scene: Dictionary = catalog.day2[int(state.scene)]
	return scene.variants[variant_for(int(state.scene))]

func current() -> Dictionary:
	var seq := sequence()
	return catalog.pages[seq[clampi(int(state.index), 0, seq.size() - 1)]]

func can_advance() -> bool:
	return not state.finished and current().choices.is_empty()

func _commit_page(page: Dictionary) -> void:
	var words: Dictionary = strings[page.id]
	# History contains what the player actually read; it is not a replay control.
	state.history.append({"page_id": page.id, "day": page.day, "text": words.duplicate(true)})
	for event in page.on_exit:
		if state.events.has(event.id):
			continue
		var applied_facts: Dictionary = event.facts.duplicate(true)
		if applied_facts.has("bird_reply_in_video"): applied_facts.bird_reply_in_video = words.dialogue
		state.events[event.id] = {"id": event.id, "day": page.day, "page_id": page.id, "facts": applied_facts}
		for key in applied_facts:
			if key == "employer_delta":
				state.employer_trust = maxi(0, int(state.employer_trust) + int(applied_facts[key]))
			else:
				state.facts[key] = applied_facts[key]
		if event.id == "d03.video.response": state.nika_relation += int(event.get("delta", 0))
		if event.id == "d03.report.sent": state.reports["3"] = {"document_title":"Отчёт · день 3", "document_line_0":event.text}
	if page.id == "D01-41":
		state.reports["1"] = _document("D01-40")
	if page.id == "D02-S10-07":
		state.reports["2"] = _document(page.id)

func _document(page_id: String) -> Dictionary:
	var document := {}
	for field in strings[page_id]:
		if str(field).begins_with("document_"): document[field] = strings[page_id][field]
	return document

func advance() -> bool:
	if not can_advance():
		return false
	var page := current()
	_commit_page(page)
	if int(state.day) == 3:
		if int(state.index) + 1 < sequence().size(): state.index += 1
		else: state.finished = true
		return true
	# The promise is recalled after the bird recording is saved, before departure.
	# Keep stable S06 IDs for history/events, despite its later narrative position.
	if int(state.day) == 2 and int(state.scene) == 9 and state.results == "promise" and not state.promise_scene_done:
		if page.id in ["D02-S09-06", "D02-S09-declined-05"]:
			state.scene = 6
			state.index = state.promise_resume_index
			return true
	if int(state.index) + 1 < sequence().size():
		state.index = int(state.index) + 1
	elif int(state.day) == 1:
		state.day = 2
		state.scene = 0
		state.index = 0
	elif int(state.scene) == 6:
		state.promise_scene_done = true
		state.promise_resume_index = 0
		state.scene = 9
		state.index = 5 if state.listen == "no" else 6
	elif int(state.scene) < 10:
		state.scene = int(state.scene) + 1
		if int(state.scene) == 6:
			state.scene = 7
		state.index = 0
	else:
		if catalog.has("day3"):
			state.day = 3
			state.scene = 0
			state.index = 0
		else: state.finished = true
		state.facts["employer_dismissed"] = int(state.employer_trust) <= 0
	return true

func choose(value: String) -> bool:
	if state.finished:
		return false
	var page := current()
	var chosen: Dictionary = {}
	for choice in page.choices:
		if choice.value == value:
			chosen = choice
			break
	if chosen.is_empty():
		return false
	if int(state.day) == 3:
		_commit_page(page)
		state.day3_choices[str(chosen.kind).trim_prefix("day3-")] = value
		var changed_sequence := sequence()
		for i in changed_sequence.size():
			if catalog.pages[changed_sequence[i]].source_id == page.source_id:
				state.index = i + 1
				return true
		return false
	_commit_page(page)
	match str(chosen.kind):
		"choice-results": state.results = value
		"choice-promise": state.promise = value
		"choice-listen": state.listen = value
		_: return false
	# Selecting is an intention; its action/penalty is committed after its narrative page.
	var seq := sequence()
	for i in seq.size():
		if int(catalog.pages[seq[i]].beat) == int(page.beat):
			state.index = i + 1
			return true
	return false

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(raw: Dictionary) -> bool:
	var candidate := raw.duplicate(true)
	var version := int(candidate.get("schema_version", candidate.get("version", 0)))
	if version == 1:
		# Legacy first-day cursor; no Day 2 decisions or achievements are invented.
		if int(candidate.get("day", 1)) != 1:
			return false
		var old_index := int(candidate.get("index", 0))
		new_game(1)
		state.index = clampi(old_index, 0, catalog.day1.size() - 1)
		state["migrated_from"] = 1
		return true
	if version not in [2, 3, 4]:
		return false
	for key in ["day", "entry_day", "scene", "index", "results", "promise", "listen", "events", "facts", "history", "reports", "employer_trust", "finished"]:
		if not candidate.has(key): return false
	if not candidate.events is Dictionary or not candidate.facts is Dictionary or not candidate.reports is Dictionary or not candidate.history is Array:
		return false
	if not candidate.finished is bool: return false
	for key in ["schema_version", "day", "entry_day", "scene", "index", "employer_trust"]:
		if not (candidate[key] is int or candidate[key] is float): return false
		if float(candidate[key]) != floorf(float(candidate[key])): return false
		candidate[key] = int(candidate[key])
	if candidate.has("migrated_from"): candidate.migrated_from = int(candidate.migrated_from)
	if candidate.entry_day not in [1, 2, 3]: return false
	if candidate.results not in ["", "now", "refused", "promise"] or candidate.promise not in ["", "kept", "broken"] or candidate.listen not in ["", "yes", "no"]:
		return false
	if candidate.promise != "" and candidate.results != "promise": return false
	if int(candidate.day) not in [1, 2, 3] or int(candidate.index) < 0 or int(candidate.scene) < 0 or int(candidate.scene) > 10:
		return false
	if int(candidate.employer_trust) < 0 or int(candidate.employer_trust) > 100: return false
	if version == 2:
		# Preserve old completed outcomes; unfinished early S06 resumes only after birds.
		candidate.schema_version = 3
		candidate.promise_scene_done = candidate.day == 2 and candidate.scene >= 7 and candidate.results == "promise"
		candidate.promise_resume_index = 0
		if candidate.day == 2 and candidate.scene == 6:
			if candidate.results != "promise": return false
			var old_variant := "broken" if candidate.promise == "broken" else "base"
			var old_seq: Array = catalog.day2[6].variants[old_variant]
			if candidate.index >= old_seq.size(): return false
			if candidate.index > 2 and candidate.promise == "": return false
			candidate.promise_resume_index = candidate.index
			candidate.scene = 7
			candidate.index = 0
	if not candidate.get("promise_scene_done") is bool: return false
	var resume: Variant = candidate.get("promise_resume_index")
	if not (resume is int or resume is float): return false
	if float(resume) != floorf(float(resume)): return false
	candidate.promise_resume_index = int(resume)
	var promise_variant := "broken" if candidate.promise == "broken" else "base"
	if candidate.promise_resume_index < 0 or candidate.promise_resume_index >= catalog.day2[6].variants[promise_variant].size(): return false
	var previous := state
	if version < 4:
		candidate.schema_version = 4
		candidate.day3_choices = {}
		candidate.nika_relation = 0
	if not candidate.get("day3_choices") is Dictionary: return false
	if not (candidate.get("nika_relation") is int or candidate.get("nika_relation") is float): return false
	if float(candidate.nika_relation) != floorf(float(candidate.nika_relation)): return false
	candidate.nika_relation = int(candidate.nika_relation)
	if candidate.nika_relation not in [0,1]: return false
	for key in candidate.day3_choices:
		var allowed := {"access":["open","closed"],"tea":["yes","no"],"response":["support","cautious"],"report":["work","personal"]}
		if not allowed.has(key) or candidate.day3_choices[key] not in allowed[key]: return false
	state = candidate
	if int(state.day) == 3 and (not catalog.has("day3") or not catalog.day3.has(day3_key())):
		state = previous
		return false
	var valid := int(state.index) < sequence().size()
	if int(state.day) == 1 and (int(state.scene) != 0 or state.finished): valid = false
	if state.finished and (int(state.day) not in [2,3] or int(state.index) != sequence().size() - 1): valid = false
	if state.finished and int(state.day) == 2 and int(state.scene) != 10: valid = false
	if int(state.day) == 3:
		for i in int(state.index):
			var earlier: Dictionary = catalog.pages[sequence()[i]]
			if not earlier.choices.is_empty() and not state.day3_choices.has(str(earlier.choices[0].kind).trim_prefix("day3-")): valid = false
	if int(state.day) == 2:
		var page := current()
		if int(state.scene) >= 6 and state.results == "": valid = false
		if int(state.scene) == 6 and state.results != "promise": valid = false
		if int(state.scene) == 5 and int(page.beat) > 2 and state.results == "": valid = false
		if int(state.scene) == 6 and int(page.beat) > 3 and state.promise == "": valid = false
		if int(state.scene) == 6 and (state.listen == "" or state.promise_scene_done or not state.facts.get("bird_video_saved", false)): valid = false
		if state.results == "promise" and state.promise_scene_done and state.promise == "": valid = false
		if int(state.scene) >= 9 and state.results == "promise" and not state.promise_scene_done:
			if int(state.scene) == 10 or int(state.index) >= (5 if state.listen == "no" else 6): valid = false
		if int(state.scene) > 7 and state.listen == "": valid = false
		if int(state.scene) == 7 and int(page.beat) > 5 and state.listen == "": valid = false
	if not valid:
		state = previous
	elif version < 4 and state.finished and state.day == 2 and catalog.has("day3"):
		state.day = 3
		state.scene = 0
		state.index = 0
		state.finished = false
	return valid
