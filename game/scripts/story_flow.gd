extends RefCounted

# Omit repeated explanatory screens without changing legacy save indices.
const OMITTED_SUMMARY_PAGES := ["D02-S09-06", "D02-S10-03", "D02-S10-04", "D02-S10-05"]

const Trust = preload("res://scripts/trust.gd")

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
		"schema_version": 10, "day": day, "scene": 0, "index": 0,
		"day3_choices": {}, "day4_choices": {}, "nika_relation": 0,
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
	Trust.reset(state)
	if day == 3:
		# Explicit standalone preview starts from a disclosed/witnessed Day2 preset.
		state.facts.merge({"results_state":"shown_now", "results_shown_to_nika":true, "hero_saw_bird_disappear":true, "bird_video_saved":true}, true)
		Trust.apply(state, "d02.results.shown")
	if day == 4:
		# Neutral standalone preview: no shared bird observation or third-day video.
		state.facts.merge({"results_state":"refused","hero_saw_bird_disappear":false,"bird_video_saved":true},true)
	if day == 5:
		state.facts.merge({"bird_video_saved":true,"day4_archive_request":"pending","day4_bookmark":"nika"},true)
	if day == 6:
		state.facts.merge({"day5_archive_request":"amended","day6_explanation_first":true,
			"day5_originals":["audio01","audio04","video02","video05"],"day5_shared_comparison":true},true)
	if day == 7:
		state.facts.merge({"day6_sound_verified":true,"day6_view_disclosed":true,
			"day6_view_control_tested":false,"day6_room_request":"pending",
			"day6_nika_copies":["archive_reply","original_sound","playback_log","comparison_marks"],
			"day5_originals":["audio01","audio04","video02","video05"],"day7_previous_tea":false},true)

	if day >= 8:
		state.facts.merge({"day7_window_first":true,"day5_originals":["audio01","audio04","video02","video05"],
			"environment_picture":"playing","environment_sound":"playing","environment_autoplay":true},true)
	if day >= 9:
		state.facts.merge({"environment_picture":"off","environment_sound":"off","environment_autoplay":false,
			"environment_control_owner":"nika","day8_environment_package":true,"day8_source_links":true,
			"day8_control_verified":true,"ordinary_tests_suspended":true},true)
	if day == 10:
		state.facts.merge({"day9_memory_prepared":true,"day9_prior_knowledge_admitted":true,
			"day9_pier_folder":["sound","usage","episode"],"day9_sources_unchanged":true,
			"day10_full_access_requested":true,"day10_archive_preparation":"complete"},true)
		_prepare_final_history()

func _prepare_final_history() -> void:
	var complete := true
	for day in range(1,10):
		if not state.reports.has(str(day)): complete = false
	var third: Dictionary = state.reports.get("3",{})
	state.facts.day10_history_complete = complete
	state.facts.day10_sent_personal = "После проверок состоялся разговор" in str(third.get("document_line_0",""))
	var personal := false
	for event in ["d02.audio.contact_started","d02.bird.confirmed","d03.tea.accepted","d04.tea_shared","d07.tea_shared","d07.music_shared"]:
		if state.events.has(event): personal = true
	state.facts.day10_had_personal_contact = personal

func day4_key() -> String:
	var f: Dictionary = state.facts
	var c: Dictionary = state.day4_choices
	var yesterday := "not_viewed"
	if f.get("bird_video_viewed",false): yesterday = "support" if f.get("video_supported",false) else "careful"
	var witness := "skipped" if f.get("bird_flight_skipped",false) else ("yes" if f.get("hero_saw_bird_disappear",false) else "no")
	return "|".join([yesterday,witness,"broken" if f.results_promise=="broken" else "none",c.get("response","support"),c.get("bookmark","help"),c.get("tea","stay")])

func can_continue_day4() -> bool:
	return state.day == 3 and can_continue_visit()

func continue_day4() -> bool:
	return can_continue_day4() and continue_visit()

func can_continue_visit() -> bool:
	return state.day >= 3 and state.finished and catalog.has("day%d" % (int(state.day)+1)) and not state.facts.get("employer_dismissed",false) and state.employer_trust > Trust.config.employer_floor

func continue_visit() -> bool:
	if not can_continue_visit(): return false
	state.day += 1
	if state.day == 7:
		state.facts.day7_previous_tea = state.events.has("d03.tea.accepted") or state.events.has("d04.tea_shared")
	if state.day == 8:
		state.facts.merge({"environment_picture":"playing","environment_sound":"playing","environment_autoplay":true},true)
	if state.day == 10: _prepare_final_history()
	state.scene = 0
	state.index = 0
	state.finished = false
	return true

func day3_key() -> String:
	var c: Dictionary = state.day3_choices
	return "|".join([str(state.facts.results_state), "yes" if state.facts.hero_saw_bird_disappear else "no", str(c.get("access","open")), str(c.get("tea","yes")), str(c.get("response","support")), str(c.get("report","work"))])

func variant_for(scene: int) -> String:
	if scene == 5:
		return "refuse" if state.results == "refused" else "promise" if state.results == "promise" else "base"
	if scene == 6:
		return "broken" if state.promise == "broken" else "base"
	if scene == 7 and state.facts.get("window_only",false): return "window"
	if scene in [7, 9]:
		return "declined" if state.listen == "no" else "base"
	if scene == 8:
		return "unseen" if state.listen == "no" and not state.facts.get("window_only",false) else "skipped" if state.facts.get("bird_flight_skipped", false) else "base"
	return "base"

func sequence() -> Array:
	if int(state.day) >= 5: return catalog["day%d" % int(state.day)]
	if int(state.day) == 4: return catalog.day4[day4_key()]
	if int(state.day) == 3:
		return catalog.day3[day3_key()]
	if int(state.day) == 1:
		return catalog.day1
	var scene: Dictionary = catalog.day2[int(state.scene)]
	return scene.variants[variant_for(int(state.scene))]

func current() -> Dictionary:
	var seq := sequence()
	var page: Dictionary = catalog.pages[seq[clampi(int(state.index), 0, seq.size() - 1)]]
	for variant in page.get("alternatives", []):
		if variant.has("when"):
			var matches := true
			for fact in variant.when:
				if state.facts.get(fact) != variant.when[fact]: matches = false
			if matches: return catalog.pages[variant.id]
		elif state.facts.get(variant.fact) == variant.value: return catalog.pages[variant.id]
	if state.day == 3 and state.index == 0 and not state.finished and Trust.warning_due(state):
		for id in ["D03-door-rules","D03-door-sanctions"]:
			if not state.events.has(id): return catalog.pages[id]
	if page.id == "D02-S08-04" and state.facts.get("hero_saw_bird_disappear",false):
		return catalog.pages["D02-bird-question"]
	if page.id == "D02-S08-05" and state.facts.get("bird_answer","") == "brief":
		return catalog.pages["D02-bird-brief"]
	if page.id == "D02-S08-08" and state.facts.get("window_only",false):
		return catalog.pages["D02-window-return"]
	if page.id == "D02-S09-04" and state.facts.has("sound_answer"):
		return catalog.pages["D02-sound-" + str(state.facts.sound_answer)]
	if page.get("source_id","") == "D03-S01-03-L2" and state.nika_trust >= Trust.config.warm_greeting:
		return catalog.pages["D03-book-warm"]
	if page.get("source_id","") == "D03-S06-02" and state.insight >= Trust.config.insight_callback:
		return catalog.pages["D03-video-insight"]
	return page

func can_advance() -> bool:
	return not state.finished and current().choices.is_empty()

func skip_bird_flight() -> bool:
	# Legacy save fixture only: the runtime no longer exposes an early exit.
	# Old observations remain truthful; listening is a separate fact.
	if state.finished or current().id not in ["D02-S08-01", "D02-S08-02"]: return false
	var page := current().duplicate(true)
	page.on_exit = [] # Leaving the disappearance page early is not witnessing it.
	_commit_page(page)
	state.facts.merge({"bird_flight_skipped":true, "hero_saw_bird_disappear":false, "hero_confirmed_bird_disappear":false}, true)
	state.events["d02.bird.flight_skipped"] = {"id":"d02.bird.flight_skipped", "day":2, "page_id":page.id, "facts":{"bird_flight_skipped":true, "hero_saw_bird_disappear":false}}
	state.index = 3 # Rejoin at Nika's question, with the truthful unseen reply.
	return true

func _commit_page(page: Dictionary) -> void:
	var words: Dictionary = strings[page.id]
	# History contains what the player actually read; it is not a replay control.
	if page.id not in OMITTED_SUMMARY_PAGES:
		state.history.append({"page_id": page.id, "day": page.day, "text": words.duplicate(true)})
	for event in page.on_exit:
		if state.events.has(event.id):
			continue
		var applied_facts: Dictionary = event.facts.duplicate(true)
		if applied_facts.has("bird_reply_in_video"): applied_facts.bird_reply_in_video = words.dialogue
		var previous_balance: int = state.employer_trust
		Trust.apply(state,event.id)
		if applied_facts.has("employer_delta") or state.employer_trust != previous_balance:
			applied_facts.employer_delta = float(state.employer_trust - previous_balance)
		state.events[event.id] = {"id": event.id, "day": page.day, "page_id": page.id, "facts": applied_facts}
		for key in applied_facts:
			if key != "employer_delta": state.facts[key] = applied_facts[key]
		if event.id == "d03.video.response": state.nika_relation += int(event.get("delta", 0))
		if event.id == "d03.report.sent": state.reports["3"] = {"document_title":"Отчёт · день 3", "document_line_0":event.text}
		if event.id in ["d05.report_sent","d06.report_sent","d07.report_sent","d08.report_sent","d09.report_sent"]: state.reports[str(int(page.day))] = _document(page.id)
		if event.id == "d10.archive_given": state.facts.day10_archive_reports = state.reports.duplicate(true)
		if event.id == "d10.report_sent": state.reports["10"] = _document("D10-S10-05")
		if event.id == "d04.report_sent":
			state.reports["4"] = {
				"document_title":"Отчёт · день 4",
				"document_line_0":words.report_work, "document_line_1":words.report_observation,
				"document_line_2":words.report_request, "document_line_3":words["report_"+str(state.facts.day4_bookmark)]
			}
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
	if page.id in ["D03-door-rules","D03-door-sanctions"]: return true
	if int(state.day) >= 3:
		if int(state.index) + 1 < sequence().size(): state.index += 1
		else:
			state.finished = true
			state.facts.employer_dismissed = state.employer_trust <= Trust.config.employer_floor
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
		if catalog.has("day3") and state.employer_trust > Trust.config.employer_floor:
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
	if chosen.kind in ["day5-align","day6-order","day7-tea","day7-music"]:
		_commit_page(page)
		var fact: String = {"day5-align":"day5_alignment","day6-order":"day6_listen_order","day7-tea":"day7_tea","day7-music":"day7_music_choice"}[chosen.kind]
		state.facts[fact] = value
		state.index += 1
		return true
	if int(state.day) in [3,4]:
		_commit_page(page)
		var visit: int = state.day
		state["day%d_choices" % visit][str(chosen.kind).trim_prefix("day%d-" % visit)] = value
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
		"choice-listen":
			state.listen = "no" if value == "window" else value
			state.facts.window_only = value == "window"
		"choice-bird":
			state.facts.bird_answer = value
			state.index += 1
			return true
		"choice-sound":
			state.facts.sound_answer = value
			state.index += 1
			return true
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
	if version not in [2, 3, 4, 5, 6, 7, 8, 9, 10]:
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
	if candidate.entry_day not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] or candidate.entry_day>candidate.day: return false
	if candidate.results not in ["", "now", "refused", "promise"] or candidate.promise not in ["", "kept", "broken"] or candidate.listen not in ["", "yes", "no"]:
		return false
	if candidate.promise != "" and candidate.results != "promise": return false
	if int(candidate.day) not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] or int(candidate.index) < 0 or int(candidate.scene) < 0 or int(candidate.scene) > 10:
		return false
	if candidate.day >= 8:
		if version < 10 or not catalog.has("day%d" % candidate.day): return false
		if candidate.facts.get("environment_picture","") not in ["playing","paused","off"]: return false
		if candidate.facts.get("environment_sound","") not in ["playing","off"]: return false
		if not candidate.facts.get("environment_autoplay") is bool: return false
		if candidate.day >= 9 and (candidate.facts.environment_picture != "off" or candidate.facts.environment_sound != "off" or candidate.facts.environment_autoplay): return false
		if candidate.day == 10 and candidate.index > catalog.day10.find("D10-S02-04") and not candidate.facts.get("day10_archive_reports") is Dictionary: return false
	if candidate.day == 5:
		if version < 7 or not catalog.has("day5"): return false
		var alignment: Variant = candidate.facts.get("day5_alignment", "")
		if alignment not in ["","together","nika"]: return false
		var decision: int = catalog.day5.find("D05-S06-01")
		if (candidate.index > decision) != (alignment != ""): return false
	if candidate.day == 6:
		if version < 8 or not catalog.has("day6"): return false
		var order: Variant = candidate.facts.get("day6_listen_order","")
		if order not in ["","archive","nika"]: return false
		if (candidate.index > catalog.day6.find("D06-S03-03")) != (order!=""): return false
	if candidate.day == 7:
		if version < 9 or not catalog.has("day7"): return false
		for fact in ["day7_tea","day7_music_choice"]:
			var choice: Variant = candidate.facts.get(fact,"")
			if choice not in ["","yes","no"]: return false
			var pivot: String = "D07-S04-02" if fact=="day7_tea" else "D07-S05-03"
			if (candidate.index > catalog.day7.find(pivot)) != (choice!=""): return false
	if version < 6:
		if candidate.day==4 or candidate.entry_day==4: return false
		candidate.day4_choices = {}
	if not candidate.get("day4_choices") is Dictionary: return false
	for key in candidate.day4_choices:
		var options := {"response":["support","careful"],"bookmark":["help","nika"],"tea":["stay","leave"]}
		if not options.has(key) or candidate.day4_choices[key] not in options[key]: return false
	if candidate.day < 4 and not candidate.day4_choices.is_empty(): return false
	if int(candidate.employer_trust) < 0 or int(candidate.employer_trust) > Trust.config.employer_start: return false
	if version < 5:
		Trust.migrate(candidate,catalog.pages)
	else:
		for field in ["nika_trust","insight"]:
			if typeof(candidate.get(field)) not in [TYPE_INT,TYPE_FLOAT]: return false
			if candidate[field] != floorf(candidate[field]) or candidate[field] < 0: return false
			candidate[field] = int(candidate[field])
		if candidate.nika_trust > Trust.config.nika_max or not candidate.get("trust_log") is Array: return false
		for item in candidate.trust_log:
			if not item is Dictionary or not item.get("id") is String: return false
	if candidate.facts.get("sound_answer","") not in ["","ordinary","strange"] or candidate.facts.get("bird_answer","") not in ["","discuss","brief"]: return false
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
	if state.day==4 and (not catalog.has("day4") or not catalog.day4.has(day4_key())):
		state = previous
		return false
	if int(state.day) == 3 and (not catalog.has("day3") or not catalog.day3.has(day3_key())):
		state = previous
		return false
	var valid := int(state.index) < sequence().size()
	if int(state.day) == 1 and (int(state.scene) != 0 or state.finished): valid = false
	if state.finished and (int(state.day) < 2 or int(state.index) != sequence().size() - 1): valid = false
	if state.finished and int(state.day) == 2 and int(state.scene) != 10: valid = false
	if int(state.day) in [3,4]:
		var recorded: Dictionary = state["day%d_choices" % int(state.day)]
		for i in int(state.index):
			var earlier: Dictionary = catalog.pages[sequence()[i]]
			if not earlier.choices.is_empty() and not recorded.has(str(earlier.choices[0].kind).trim_prefix("day%d-" % int(state.day))): valid = false
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
	elif version < 4 and state.finished and state.day == 2 and catalog.has("day3") and state.employer_trust > Trust.config.employer_floor:
		state.day = 3
		state.scene = 0
		state.index = 0
		state.finished = false
	if valid:
		state.schema_version = 10
		if state.finished and state.employer_trust <= Trust.config.employer_floor: state.facts.employer_dismissed = true
	return valid
