extends GutTest
## Proves the test runner itself works in CI.


func test_project_name_is_set() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Saikoro Bay")
