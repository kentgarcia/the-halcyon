extends TestCase
## Sound radar (accessibility): bearings are relative to where the camera faces, and everyday sounds are ignored.


func test_bearing_is_relative_to_the_camera() -> void:
	var cam := Transform3D(Basis.IDENTITY, Vector3.ZERO)       # looks down -Z
	assert_near(SoundRadar.bearing(cam, Vector3(0, 0, -5)), 0.0, 0.001, "ahead")
	assert_near(SoundRadar.bearing(cam, Vector3(5, 0, 0)), PI * 0.5, 0.001, "to the right")
	assert_near(SoundRadar.bearing(cam, Vector3(-5, 0, 0)), -PI * 0.5, 0.001, "to the left")
	assert_near(absf(SoundRadar.bearing(cam, Vector3(0, 0, 5))), PI, 0.001, "behind")
	# turn the camera to face +X: a sound at +X is now straight ahead, one at -Z is on the left
	var turned := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	assert_near(SoundRadar.bearing(turned, Vector3(5, 0, 0)), 0.0, 0.001, "ahead after turning right")
	assert_near(SoundRadar.bearing(turned, Vector3(0, 0, -5)), -PI * 0.5, 0.001, "left after turning right")


func test_everyday_sounds_are_not_shown() -> void:
	assert_true(SoundRadar.is_mundane(&"step_carpet"), "footsteps are everyday")
	assert_true(SoundRadar.is_mundane(&"switch_click"), "switches are everyday")
	assert_false(SoundRadar.is_mundane(&"knock_slow"), "a knock is a warning")
	assert_false(SoundRadar.is_mundane(&"whistle_blast"), "a whistle is a warning")
