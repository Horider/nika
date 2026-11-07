extends RefCounted

static var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/trust.json"))

static func reset(state: Dictionary) -> void:
	state.nika_trust = 0
	state.insight = 0
	state.trust_log = []
	state.employer_trust = int(config.employer_start)

static func apply(state: Dictionary, event_id: String, historical := false) -> void:
	for rule in config.rules:
		if rule.id != event_id: continue
		var cost := int(rule.employer)
		for previous in state.trust_log:
			if previous.id == event_id: return
			if rule.has("group") and previous.get("group", "") == rule.group: cost = 0
		state.nika_trust = clampi(int(state.nika_trust) + int(rule.nika), 0, int(config.nika_max))
		state.insight += int(rule.insight)
		# Older saves already paid the original penalties. Preserve their actual balance.
		if not historical:
			state.employer_trust = maxi(int(config.employer_floor), int(state.employer_trust) + cost)
		state.trust_log.append({"id":event_id, "group":rule.get("group","")})
		return

static func warning_due(state: Dictionary) -> bool:
	for rule in config.rules:
		if not rule.has("warning"): continue
		for item in state.trust_log:
			if item.id == rule.id: return true
	return false

static func migrate(state: Dictionary, pages: Dictionary) -> void:
	var old_balance: int = state.employer_trust
	reset(state)
	state.employer_trust = old_balance
	# History retains visit order even when JSON keys were sorted when saving.
	for step in state.history:
		var page: Dictionary = pages.get(step.get("page_id",""), {})
		for event in page.get("on_exit",[]):
			if state.events.has(event.id): apply(state, event.id, true)
	for key in state.events: apply(state, key, true)
	# Older standalone previews carry yesterday's facts without a day-two ledger.
	if state.facts.get("results_shown_to_nika",false): apply(state,"d02.results.shown",true)
	if state.facts.get("listen_choice","") == "accepted": apply(state,"d02.audio.contact_started",true)
	if state.facts.get("hero_confirmed_bird_disappear",false): apply(state,"d02.bird.confirmed",true)
