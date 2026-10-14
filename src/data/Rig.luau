--!nonstrict
-- data/Rig: the body layout costumes and accessories are authored against, and the bone names they attach to.
-- Character models are authored around the HumanoidRootPart (origin), facing -Z, +X = the character's right, feet at y = -3.
-- Every part of a costume belongs to ONE bone (a body part of your Roblox character: Head, UpperTorso, LeftUpperArm, ...); when the
-- costume is put on, each piece is welded to that body part with an offset computed from the rig's own Motor6D rest pose, so it
-- follows the animation of that limb instead of staying fixed to the root. `rest` below are the default-proportion centres used to
-- decide which bone a part belongs to (nearest centre) and to pose the preview mannequin; the in-game offsets come from the real rig.
-- Depends on: nothing.

local Rig = {}

-- id, R15 part name, R6 part name, rest centre (x, y, z), joint pivot the part swings about (x, y, z), swing role for the preview walk
Rig.BONES = {
	{ id = "Head", r15 = "Head", r6 = "Head", rest = { 0, 1.9, 0 }, pivot = { 0, 1.35, 0 }, swing = "head" },
	{ id = "UpperTorso", r15 = "UpperTorso", r6 = "Torso", rest = { 0, 0.75, 0 }, pivot = { 0, 0.75, 0 }, swing = "torso" },
	{ id = "LowerTorso", r15 = "LowerTorso", r6 = "Torso", rest = { 0, -0.35, 0 }, pivot = { 0, -0.35, 0 }, swing = "torso" },
	{ id = "RightUpperArm", r15 = "RightUpperArm", r6 = "Right Arm", rest = { 1.5, 0.9, 0 }, pivot = { 1.4, 1.2, 0 }, swing = "armR" },
	{ id = "RightLowerArm", r15 = "RightLowerArm", r6 = "Right Arm", rest = { 1.5, 0.1, 0 }, pivot = { 1.4, 1.2, 0 }, swing = "armR" },
	{ id = "RightHand", r15 = "RightHand", r6 = "Right Arm", rest = { 1.5, -0.55, 0 }, pivot = { 1.4, 1.2, 0 }, swing = "armR" },
	{ id = "LeftUpperArm", r15 = "LeftUpperArm", r6 = "Left Arm", rest = { -1.5, 0.9, 0 }, pivot = { -1.4, 1.2, 0 }, swing = "armL" },
	{ id = "LeftLowerArm", r15 = "LeftLowerArm", r6 = "Left Arm", rest = { -1.5, 0.1, 0 }, pivot = { -1.4, 1.2, 0 }, swing = "armL" },
	{ id = "LeftHand", r15 = "LeftHand", r6 = "Left Arm", rest = { -1.5, -0.55, 0 }, pivot = { -1.4, 1.2, 0 }, swing = "armL" },
	{ id = "RightUpperLeg", r15 = "RightUpperLeg", r6 = "Right Leg", rest = { 0.5, -1.15, 0 }, pivot = { 0.5, -0.75, 0 }, swing = "legR" },
	{ id = "RightLowerLeg", r15 = "RightLowerLeg", r6 = "Right Leg", rest = { 0.5, -2.0, 0 }, pivot = { 0.5, -0.75, 0 }, swing = "legR" },
	{ id = "RightFoot", r15 = "RightFoot", r6 = "Right Leg", rest = { 0.5, -2.75, 0 }, pivot = { 0.5, -0.75, 0 }, swing = "legR" },
	{ id = "LeftUpperLeg", r15 = "LeftUpperLeg", r6 = "Left Leg", rest = { -0.5, -1.15, 0 }, pivot = { -0.5, -0.75, 0 }, swing = "legL" },
	{ id = "LeftLowerLeg", r15 = "LeftLowerLeg", r6 = "Left Leg", rest = { -0.5, -2.0, 0 }, pivot = { -0.5, -0.75, 0 }, swing = "legL" },
	{ id = "LeftFoot", r15 = "LeftFoot", r6 = "Left Leg", rest = { -0.5, -2.75, 0 }, pivot = { -0.5, -0.75, 0 }, swing = "legL" },
}
Rig.ROOT = { id = "Root", r15 = "HumanoidRootPart", r6 = "HumanoidRootPart" }

local byId = {}
for _, b in ipairs(Rig.BONES) do
	byId[b.id] = b
end

function Rig.bone(id)
	return byId[id]
end

-- accessory slot -> bone
Rig.SLOT_BONE = { head = "Head", back = "UpperTorso", aura = "Root", costume = nil }

-- assign(pos) -> the id of the bone whose rest centre is nearest to pos ({x,y,z} in root space). Horizontal distance counts a little
-- less than vertical so a wide torso part does not jump to an arm.
function Rig.assign(pos)
	local best, bd = "UpperTorso", 1e9
	for _, b in ipairs(Rig.BONES) do
		local dx, dy, dz = pos[1] - b.rest[1], pos[2] - b.rest[2], pos[3] - b.rest[3]
		local d = dx * dx * 0.8 + dy * dy + dz * dz * 0.8
		if d < bd then
			best, bd = b.id, d
		end
	end
	return best
end

-- partName(boneId, rigType) -> the name of the character part for "R15" or "R6" ("HumanoidRootPart" for Root)
function Rig.partName(boneId, rigType)
	if boneId == "Root" then
		return "HumanoidRootPart"
	end
	local b = byId[boneId]
	if not b then
		return nil
	end
	return rigType == "R6" and b.r6 or b.r15
end

-- swingAngle(swingRole, t) -> radians: the preview walk cycle (arms and legs in opposite phase)
function Rig.swingAngle(role, t)
	local s = math.sin(t * 4.2)
	if role == "armR" or role == "legL" then
		return s * (role == "armR" and 0.55 or 0.6)
	elseif role == "armL" or role == "legR" then
		return -s * (role == "armL" and 0.55 or 0.6)
	elseif role == "head" then
		return math.sin(t * 2.1) * 0.08
	end
	return 0
end

return Rig
