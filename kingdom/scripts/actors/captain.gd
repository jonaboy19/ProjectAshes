class_name Captain
extends Node3D
## Recruitment officer. Talk to him to join the militia, then to hire more men
## up to the limit of your rank.

const Nameplates := preload("res://scripts/core/nameplates.gd")
signal recruit_requested(count: int)

var title := "Captain of the Guard"


func _ready() -> void:
	add_to_group("interactable")
	var model := Assets.character("Guard", 1.85, ["Knight_Helmet", "2H_Sword"])
	add_child(model)
	var anim := Assets.animation_player(model)
	if anim:
		anim.play("2H_Melee_Idle" if anim.has_animation("2H_Melee_Idle") else "Idle")
	var tag := Label3D.new()
	tag.text = title
	Nameplates.style(tag, Color("f0c060"))
	tag.position.y = 2.3
	add_child(tag)


func prompt() -> String:
	return "Talk"


## The interact key: the recruiter's menu (main.gd's VillageServices).
func use() -> void:
	var hud := Interaction.hud(self)
	var sv := Interaction.services(self)
	if hud != null and sv != null:
		hud.call("show_menu", Callable(sv, "captain_menu"))


## Direct enlist used by the scripted demo; players normally use the Captain's menu.
func interact(player: Player, current_soldiers: int) -> void:
	if not Life.careers.is_employed():
		var why := Life.careers.apply("guard", "Guard", Game.merit, WorldSim.day)
		if why != "":
			Game.say(why)
			return
	if Game.rank == 0:
		Game.promote()
		Game.say("\"Welcome to the militia. Here are twelve men. Raiders camp in the eastern woods.\"")
		recruit_requested.emit(Game.max_soldiers())
		return
	var room := Game.max_soldiers() - current_soldiers
	if room <= 0:
		Game.say("\"A %s can't lead more men. Earn a higher rank.\"" % Game.rank_name())
		return
	var affordable := Game.gold / Game.RECRUIT_COST
	var count := mini(room, mini(6, affordable))
	if count <= 0:
		Game.say("\"Soldiers cost %d gold each. Come back with coin.\"" % Game.RECRUIT_COST)
		return
	Game.add_gold(-count * Game.RECRUIT_COST)
	Game.say("%d recruits join your company." % count)
	recruit_requested.emit(count)
