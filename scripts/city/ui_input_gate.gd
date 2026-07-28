## The question every gameplay input handler has to ask before it acts on a key: is a panel in
## front of the world right now? The answer belongs to the walker — it is the one node that
## knows about its own character editor as well as the root's modals — but the handlers that
## must ask are scattered across the build bar, the arcade cabinet and whatever comes next, and
## each one used to spell the condition out again. A surface that forgets is silent: the key
## simply works through the open panel, which is how F1–F6 kept placing buildings behind the
## inventory. Same idea as UiLayers: one place to get it right.
class_name UiInputGate
extends RefCounted


## True while a panel owns the screen, so the caller must drop the event. A handler that was
## never handed a walker cannot answer honestly, and guessing "nothing is open" is the leak
## itself, so it reports and stays shut.
static func gameplay_blocked(walker: CityWalker) -> bool:
	if walker == null or not is_instance_valid(walker):
		push_error("UiInputGate.gameplay_blocked: no walker to ask, gameplay input stays off")
		return true
	return walker.is_blocking_ui_open()
