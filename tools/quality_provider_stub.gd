extends Node

# Stand-in for a rendering pack, used by the suite. The settings pack finds a
# quality provider by the method it offers rather than by name or by import, so
# the test has to prove that with something that is not the visuals pack.

var got: Dictionary = {}


func set_axis_quality(axis: String, level: int) -> void:
	got[axis] = level
