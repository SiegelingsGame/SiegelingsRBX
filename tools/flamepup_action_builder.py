"""
Create a first-pass FlamePup action set directly in Blender.

How to use:
1. Open FlamePup.blend in Blender.
2. Open the Scripting workspace.
3. Load and run this file.
4. The script creates or overwrites the following actions:
   Idle, Move, Attack, Special, Faint, Income

Notes:
- The script keys the existing armature only.
- Bone names are resolved through aliases so small naming differences are okay.
- Everything is authored in place for export to Roblox.
- This is a hand-authored first pass. Expect to tweak a few angles after previewing.
"""

import bpy
from math import radians


FPS = 24

# Keep the action names aligned with CreatureAnimation.lua in this repo.
ACTION_SPECS = {
    "Idle": {"length": 48, "loop": True},
    "Move": {"length": 24, "loop": True},
    "Attack": {"length": 24, "loop": False},
    "Special": {"length": 48, "loop": False},
    "Faint": {"length": 40, "loop": False},
    "Income": {"length": 64, "loop": True},
}


BONE_ALIASES = {
    "body": ["Body", "Root", "Spine", "Torso"],
    "neck": ["Neck"],
    "head": ["Head"],
    "front_left_base": ["FrontLeftLegBase", "FrontLeftShoulder", "FL_LegBase", "FLBase"],
    "front_left_upper": ["FrontLeftLegUpper", "FrontLeftUpper", "FL_LegUpper", "FLUpper"],
    "front_left_lower": ["FrontLeftLegLower", "FrontLeftLower", "FL_LegLower", "FLLower"],
    "front_right_base": ["FrontRightLegBase", "FrontRightShoulder", "FR_LegBase", "FRBase"],
    "front_right_upper": ["FrontRightLegUpper", "FrontRightUpper", "FR_LegUpper", "FRUpper"],
    "front_right_lower": ["FrontRightLegLower", "FrontRightLower", "FR_LegLower", "FRLower"],
    "back_left_base": ["BackLeftLegBase", "BackLeftHip", "BL_LegBase", "BLBase"],
    "back_left_upper": ["BackLeftLegUpper", "BackLeftUpper", "BL_LegUpper", "BLUpper"],
    "back_left_lower": ["BackLeftLegLower", "BackLeftLower", "BL_LegLower", "BLLower"],
    "back_right_base": ["BackRightLegBase", "BackRightHip", "BR_LegBase", "BRBase"],
    "back_right_upper": ["BackRightLegUpper", "BackRightUpper", "BR_LegUpper", "BRUpper"],
    "back_right_lower": ["BackRightLegLower", "BackRightLower", "BR_LegLower", "BRLower"],
    "tail_base": ["TailBase", "TailRoot"],
    "tail_middle": ["TailMiddle", "TailMid"],
    "tail_flame": ["TailFlame", "TailTip", "TailEnd"],
}


def deg(x=0.0, y=0.0, z=0.0):
    return (radians(x), radians(y), radians(z))


def normalize(name):
    return "".join(ch for ch in name.lower() if ch.isalnum())


def resolve_armature():
    active = bpy.context.object
    if active and active.type == "ARMATURE":
        return active

    for obj in bpy.context.selected_objects:
        if obj.type == "ARMATURE":
            return obj

    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and obj.name == "Armature":
            return obj

    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj

    raise RuntimeError("No armature object found. Open the FlamePup blend and select the rig.")


def resolve_bone_map(armature):
    pose_bones = armature.pose.bones
    actual_by_norm = {normalize(bone.name): bone.name for bone in pose_bones}
    resolved = {}
    missing = []

    for key, aliases in BONE_ALIASES.items():
        match = None
        for alias in aliases:
            alias_norm = normalize(alias)
            if alias_norm in actual_by_norm:
                match = actual_by_norm[alias_norm]
                break

        if not match:
            for alias in aliases:
                alias_norm = normalize(alias)
                for actual_norm, actual_name in actual_by_norm.items():
                    if actual_norm.startswith(alias_norm) or alias_norm.startswith(actual_norm):
                        match = actual_name
                        break
                if match:
                    break

        if match:
            resolved[key] = match
        else:
            missing.append(key)

    if missing:
        print("FlamePup builder: missing optional bones ->", ", ".join(missing))

    return resolved


def ensure_pose_context(armature):
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    if bpy.context.object.mode != "POSE":
        bpy.ops.object.mode_set(mode="POSE")

    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"


def clear_pose(armature, bone_map):
    used_actual_names = {actual_name for actual_name in bone_map.values()}
    for bone in armature.pose.bones:
        if bone.name not in used_actual_names:
            continue
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def get_or_reset_action(name):
    action = bpy.data.actions.get(name)
    if action is None:
        action = bpy.data.actions.new(name=name)
    else:
        while action.fcurves:
            action.fcurves.remove(action.fcurves[0])
        while action.groups:
            action.groups.remove(action.groups[0])
        while action.pose_markers:
            action.pose_markers.remove(action.pose_markers[0])

    action.use_fake_user = True
    return action


def insert_pose(armature, bone_map, frame, rotations):
    bpy.context.scene.frame_set(frame)
    clear_pose(armature, bone_map)

    for key, rot in rotations.items():
        actual_name = bone_map.get(key)
        if not actual_name:
            continue
        armature.pose.bones[actual_name].rotation_euler = rot

    keyed_names = {name for name in bone_map.values()}
    for bone in armature.pose.bones:
        if bone.name not in keyed_names:
            continue
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)


def finalize_action(action, loop):
    action.frame_start = 1
    action.frame_end = max((fc.keyframe_points[-1].co.x for fc in action.fcurves if fc.keyframe_points), default=1)

    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "BEZIER"
            key.handle_left_type = "AUTO_CLAMPED"
            key.handle_right_type = "AUTO_CLAMPED"
        if loop:
            modifier = fcurve.modifiers.new(type="CYCLES")
            modifier.mode_before = "REPEAT"
            modifier.mode_after = "REPEAT"


def compose_action(armature, bone_map, name, poses):
    action = get_or_reset_action(name)
    armature.animation_data_create()
    armature.animation_data.action = action

    for frame, rotations in poses:
        insert_pose(armature, bone_map, frame, rotations)

    finalize_action(action, ACTION_SPECS[name]["loop"])
    print(f"FlamePup builder: created action '{name}'")


def idle_poses():
    return [
        (
            1,
            {
                "body": deg(3, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-4, 0, 0),
                "tail_base": deg(8, 0, 3),
                "tail_middle": deg(12, 0, 6),
                "tail_flame": deg(18, 0, 10),
            },
        ),
        (
            13,
            {
                "body": deg(1, 0, 2),
                "neck": deg(-1, 0, 4),
                "head": deg(-3, 0, 10),
                "front_left_base": deg(4, 0, 4),
                "back_right_base": deg(-3, 0, -2),
                "tail_base": deg(10, 0, -8),
                "tail_middle": deg(14, 0, -14),
                "tail_flame": deg(20, 0, -18),
            },
        ),
        (
            25,
            {
                "body": deg(4, 0, -2),
                "neck": deg(-3, 0, -4),
                "head": deg(-6, 0, -10),
                "front_right_base": deg(4, 0, -4),
                "back_left_base": deg(-3, 0, 2),
                "tail_base": deg(9, 0, 9),
                "tail_middle": deg(14, 0, 16),
                "tail_flame": deg(19, 0, 20),
            },
        ),
        (
            37,
            {
                "body": deg(2, 0, 1),
                "neck": deg(-1, 0, 1),
                "head": deg(-2, 0, 4),
                "tail_base": deg(8, 0, -2),
                "tail_middle": deg(11, 0, -4),
                "tail_flame": deg(16, 0, -6),
            },
        ),
        (
            49,
            {
                "body": deg(3, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-4, 0, 0),
                "tail_base": deg(8, 0, 3),
                "tail_middle": deg(12, 0, 6),
                "tail_flame": deg(18, 0, 10),
            },
        ),
    ]


def move_poses():
    return [
        (
            1,
            {
                "body": deg(6, 0, 2),
                "neck": deg(-5, 0, -2),
                "head": deg(-8, 0, 1),
                "front_left_base": deg(8, 0, 12),
                "front_left_upper": deg(-14, 0, 0),
                "front_left_lower": deg(24, 0, 0),
                "front_right_base": deg(-6, 0, -12),
                "front_right_upper": deg(10, 0, 0),
                "front_right_lower": deg(-16, 0, 0),
                "back_left_base": deg(-8, 0, -10),
                "back_left_upper": deg(12, 0, 0),
                "back_left_lower": deg(-18, 0, 0),
                "back_right_base": deg(8, 0, 10),
                "back_right_upper": deg(-12, 0, 0),
                "back_right_lower": deg(22, 0, 0),
                "tail_base": deg(12, 0, -10),
                "tail_middle": deg(18, 0, -16),
                "tail_flame": deg(22, 0, -20),
            },
        ),
        (
            7,
            {
                "body": deg(3, 0, -1),
                "neck": deg(-2, 0, 0),
                "head": deg(-3, 0, -1),
                "front_left_base": deg(-2, 0, 2),
                "front_left_upper": deg(4, 0, 0),
                "front_left_lower": deg(-6, 0, 0),
                "front_right_base": deg(4, 0, 6),
                "front_right_upper": deg(-8, 0, 0),
                "front_right_lower": deg(14, 0, 0),
                "back_left_base": deg(5, 0, 7),
                "back_left_upper": deg(-8, 0, 0),
                "back_left_lower": deg(12, 0, 0),
                "back_right_base": deg(-2, 0, -2),
                "back_right_upper": deg(4, 0, 0),
                "back_right_lower": deg(-6, 0, 0),
                "tail_base": deg(10, 0, -2),
                "tail_middle": deg(14, 0, -4),
                "tail_flame": deg(18, 0, -6),
            },
        ),
        (
            13,
            {
                "body": deg(6, 0, -2),
                "neck": deg(-5, 0, 2),
                "head": deg(-8, 0, -1),
                "front_left_base": deg(-6, 0, -12),
                "front_left_upper": deg(10, 0, 0),
                "front_left_lower": deg(-16, 0, 0),
                "front_right_base": deg(8, 0, 12),
                "front_right_upper": deg(-14, 0, 0),
                "front_right_lower": deg(24, 0, 0),
                "back_left_base": deg(8, 0, 10),
                "back_left_upper": deg(-12, 0, 0),
                "back_left_lower": deg(22, 0, 0),
                "back_right_base": deg(-8, 0, -10),
                "back_right_upper": deg(12, 0, 0),
                "back_right_lower": deg(-18, 0, 0),
                "tail_base": deg(12, 0, 10),
                "tail_middle": deg(18, 0, 16),
                "tail_flame": deg(22, 0, 20),
            },
        ),
        (
            19,
            {
                "body": deg(3, 0, 1),
                "neck": deg(-2, 0, 0),
                "head": deg(-3, 0, 1),
                "front_left_base": deg(4, 0, 6),
                "front_left_upper": deg(-8, 0, 0),
                "front_left_lower": deg(14, 0, 0),
                "front_right_base": deg(-2, 0, 2),
                "front_right_upper": deg(4, 0, 0),
                "front_right_lower": deg(-6, 0, 0),
                "back_left_base": deg(-2, 0, -2),
                "back_left_upper": deg(4, 0, 0),
                "back_left_lower": deg(-6, 0, 0),
                "back_right_base": deg(5, 0, 7),
                "back_right_upper": deg(-8, 0, 0),
                "back_right_lower": deg(12, 0, 0),
                "tail_base": deg(10, 0, 2),
                "tail_middle": deg(14, 0, 4),
                "tail_flame": deg(18, 0, 6),
            },
        ),
        (
            25,
            {
                "body": deg(6, 0, 2),
                "neck": deg(-5, 0, -2),
                "head": deg(-8, 0, 1),
                "front_left_base": deg(8, 0, 12),
                "front_left_upper": deg(-14, 0, 0),
                "front_left_lower": deg(24, 0, 0),
                "front_right_base": deg(-6, 0, -12),
                "front_right_upper": deg(10, 0, 0),
                "front_right_lower": deg(-16, 0, 0),
                "back_left_base": deg(-8, 0, -10),
                "back_left_upper": deg(12, 0, 0),
                "back_left_lower": deg(-18, 0, 0),
                "back_right_base": deg(8, 0, 10),
                "back_right_upper": deg(-12, 0, 0),
                "back_right_lower": deg(22, 0, 0),
                "tail_base": deg(12, 0, -10),
                "tail_middle": deg(18, 0, -16),
                "tail_flame": deg(22, 0, -20),
            },
        ),
    ]


def attack_poses():
    return [
        (
            1,
            {
                "body": deg(4, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-3, 0, 0),
                "tail_base": deg(10, 0, 2),
                "tail_middle": deg(14, 0, 5),
                "tail_flame": deg(18, 0, 8),
            },
        ),
        (
            5,
            {
                "body": deg(14, 0, -2),
                "neck": deg(-12, 0, 0),
                "head": deg(-18, 0, 0),
                "front_left_base": deg(10, 0, 6),
                "front_left_upper": deg(-14, 0, 0),
                "front_left_lower": deg(20, 0, 0),
                "front_right_base": deg(14, 0, -2),
                "front_right_upper": deg(-18, 0, 0),
                "front_right_lower": deg(28, 0, 0),
                "back_left_base": deg(-10, 0, -6),
                "back_left_upper": deg(14, 0, 0),
                "back_left_lower": deg(-18, 0, 0),
                "back_right_base": deg(-10, 0, 6),
                "back_right_upper": deg(14, 0, 0),
                "back_right_lower": deg(-18, 0, 0),
                "tail_base": deg(18, 0, -10),
                "tail_middle": deg(26, 0, -18),
                "tail_flame": deg(32, 0, -24),
            },
        ),
        (
            9,
            {
                "body": deg(-4, 0, 8),
                "neck": deg(6, 0, 10),
                "head": deg(18, 0, 18),
                "front_left_base": deg(-6, 0, 4),
                "front_left_upper": deg(8, 0, 0),
                "front_left_lower": deg(-10, 0, 0),
                "front_right_base": deg(-18, 0, 26),
                "front_right_upper": deg(12, 0, 0),
                "front_right_lower": deg(-12, 0, 0),
                "back_left_base": deg(4, 0, -6),
                "back_left_upper": deg(-6, 0, 0),
                "back_left_lower": deg(10, 0, 0),
                "back_right_base": deg(8, 0, 10),
                "back_right_upper": deg(-10, 0, 0),
                "back_right_lower": deg(14, 0, 0),
                "tail_base": deg(8, 0, 16),
                "tail_middle": deg(12, 0, 26),
                "tail_flame": deg(18, 0, 34),
            },
        ),
        (
            15,
            {
                "body": deg(2, 0, -4),
                "neck": deg(-2, 0, -4),
                "head": deg(-4, 0, -6),
                "front_right_base": deg(4, 0, -8),
                "front_right_upper": deg(-8, 0, 0),
                "front_right_lower": deg(12, 0, 0),
                "tail_base": deg(10, 0, -6),
                "tail_middle": deg(14, 0, -10),
                "tail_flame": deg(18, 0, -14),
            },
        ),
        (
            24,
            {
                "body": deg(4, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-3, 0, 0),
                "tail_base": deg(10, 0, 2),
                "tail_middle": deg(14, 0, 5),
                "tail_flame": deg(18, 0, 8),
            },
        ),
    ]


def special_poses():
    return [
        (
            1,
            {
                "body": deg(4, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-4, 0, 0),
                "tail_base": deg(8, 0, 0),
                "tail_middle": deg(12, 0, 2),
                "tail_flame": deg(18, 0, 4),
            },
        ),
        (
            8,
            {
                "body": deg(16, 0, 0),
                "neck": deg(-12, 0, 0),
                "head": deg(-20, 0, 0),
                "front_left_base": deg(14, 0, 4),
                "front_left_upper": deg(-16, 0, 0),
                "front_left_lower": deg(24, 0, 0),
                "front_right_base": deg(14, 0, -4),
                "front_right_upper": deg(-16, 0, 0),
                "front_right_lower": deg(24, 0, 0),
                "back_left_base": deg(-14, 0, -6),
                "back_left_upper": deg(16, 0, 0),
                "back_left_lower": deg(-20, 0, 0),
                "back_right_base": deg(-14, 0, 6),
                "back_right_upper": deg(16, 0, 0),
                "back_right_lower": deg(-20, 0, 0),
                "tail_base": deg(22, 0, -8),
                "tail_middle": deg(34, 0, -16),
                "tail_flame": deg(46, 0, -20),
            },
        ),
        (
            16,
            {
                "body": deg(-10, 0, 0),
                "neck": deg(12, 0, 0),
                "head": deg(28, 0, 0),
                "front_left_base": deg(-20, 0, 12),
                "front_left_upper": deg(18, 0, 0),
                "front_left_lower": deg(-18, 0, 0),
                "front_right_base": deg(-20, 0, -12),
                "front_right_upper": deg(18, 0, 0),
                "front_right_lower": deg(-18, 0, 0),
                "back_left_base": deg(18, 0, -10),
                "back_left_upper": deg(-16, 0, 0),
                "back_left_lower": deg(24, 0, 0),
                "back_right_base": deg(18, 0, 10),
                "back_right_upper": deg(-16, 0, 0),
                "back_right_lower": deg(24, 0, 0),
                "tail_base": deg(10, 0, 0),
                "tail_middle": deg(18, 0, 0),
                "tail_flame": deg(28, 0, 0),
            },
        ),
        (
            24,
            {
                "body": deg(18, 0, 0),
                "neck": deg(-14, 0, 0),
                "head": deg(-20, 0, 0),
                "front_left_base": deg(18, 0, 8),
                "front_left_upper": deg(-20, 0, 0),
                "front_left_lower": deg(28, 0, 0),
                "front_right_base": deg(18, 0, -8),
                "front_right_upper": deg(-20, 0, 0),
                "front_right_lower": deg(28, 0, 0),
                "back_left_base": deg(-16, 0, -8),
                "back_left_upper": deg(18, 0, 0),
                "back_left_lower": deg(-22, 0, 0),
                "back_right_base": deg(-16, 0, 8),
                "back_right_upper": deg(18, 0, 0),
                "back_right_lower": deg(-22, 0, 0),
                "tail_base": deg(30, 0, -18),
                "tail_middle": deg(42, 0, -26),
                "tail_flame": deg(56, 0, -32),
            },
        ),
        (
            32,
            {
                "body": deg(-14, 0, 0),
                "neck": deg(10, 0, 0),
                "head": deg(16, 0, 0),
                "front_left_base": deg(-10, 0, 3),
                "front_left_upper": deg(8, 0, 0),
                "front_left_lower": deg(-8, 0, 0),
                "front_right_base": deg(-10, 0, -3),
                "front_right_upper": deg(8, 0, 0),
                "front_right_lower": deg(-8, 0, 0),
                "tail_base": deg(16, 0, 14),
                "tail_middle": deg(24, 0, 20),
                "tail_flame": deg(32, 0, 26),
            },
        ),
        (
            40,
            {
                "body": deg(6, 0, 0),
                "neck": deg(-4, 0, 0),
                "head": deg(-6, 0, 0),
                "tail_base": deg(10, 0, -4),
                "tail_middle": deg(16, 0, -8),
                "tail_flame": deg(22, 0, -10),
            },
        ),
        (
            48,
            {
                "body": deg(4, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-4, 0, 0),
                "tail_base": deg(8, 0, 0),
                "tail_middle": deg(12, 0, 2),
                "tail_flame": deg(18, 0, 4),
            },
        ),
    ]


def faint_poses():
    return [
        (
            1,
            {
                "body": deg(4, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(-4, 0, 0),
                "tail_base": deg(8, 0, 2),
                "tail_middle": deg(12, 0, 4),
                "tail_flame": deg(18, 0, 6),
            },
        ),
        (
            10,
            {
                "body": deg(8, 0, 6),
                "neck": deg(-8, 0, -6),
                "head": deg(-14, 0, -12),
                "front_left_base": deg(6, 0, 6),
                "front_right_base": deg(6, 0, -8),
                "tail_base": deg(2, 0, -6),
                "tail_middle": deg(2, 0, -10),
                "tail_flame": deg(0, 0, -14),
            },
        ),
        (
            20,
            {
                "body": deg(18, 0, 16),
                "neck": deg(-18, 0, -12),
                "head": deg(-26, 0, -18),
                "front_left_base": deg(12, 0, 12),
                "front_left_upper": deg(-16, 0, 0),
                "front_left_lower": deg(24, 0, 0),
                "front_right_base": deg(12, 0, -16),
                "front_right_upper": deg(-18, 0, 0),
                "front_right_lower": deg(26, 0, 0),
                "back_left_base": deg(-8, 0, -6),
                "back_left_upper": deg(14, 0, 0),
                "back_left_lower": deg(-18, 0, 0),
                "back_right_base": deg(-8, 0, 10),
                "back_right_upper": deg(14, 0, 0),
                "back_right_lower": deg(-18, 0, 0),
                "tail_base": deg(-8, 0, -18),
                "tail_middle": deg(-16, 0, -28),
                "tail_flame": deg(-24, 0, -36),
            },
        ),
        (
            30,
            {
                "body": deg(26, 0, 28),
                "neck": deg(-26, 0, -16),
                "head": deg(-34, 0, -22),
                "front_left_base": deg(14, 0, 20),
                "front_left_upper": deg(-18, 0, 0),
                "front_left_lower": deg(28, 0, 0),
                "front_right_base": deg(6, 0, -24),
                "front_right_upper": deg(-10, 0, 0),
                "front_right_lower": deg(18, 0, 0),
                "back_left_base": deg(-12, 0, -14),
                "back_left_upper": deg(18, 0, 0),
                "back_left_lower": deg(-20, 0, 0),
                "back_right_base": deg(-6, 0, 18),
                "back_right_upper": deg(10, 0, 0),
                "back_right_lower": deg(-12, 0, 0),
                "tail_base": deg(-20, 0, -22),
                "tail_middle": deg(-28, 0, -34),
                "tail_flame": deg(-38, 0, -46),
            },
        ),
        (
            40,
            {
                "body": deg(24, 0, 30),
                "neck": deg(-30, 0, -16),
                "head": deg(-38, 0, -22),
                "front_left_base": deg(16, 0, 24),
                "front_left_upper": deg(-18, 0, 0),
                "front_left_lower": deg(30, 0, 0),
                "front_right_base": deg(6, 0, -24),
                "front_right_upper": deg(-10, 0, 0),
                "front_right_lower": deg(18, 0, 0),
                "back_left_base": deg(-14, 0, -16),
                "back_left_upper": deg(20, 0, 0),
                "back_left_lower": deg(-24, 0, 0),
                "tail_base": deg(-24, 0, -26),
                "tail_middle": deg(-36, 0, -40),
                "tail_flame": deg(-48, 0, -54),
            },
        ),
    ]


def income_poses():
    return [
        (
            1,
            {
                "body": deg(6, 0, 0),
                "neck": deg(-4, 0, 0),
                "head": deg(-6, 0, 0),
                "tail_base": deg(10, 0, 6),
                "tail_middle": deg(16, 0, 10),
                "tail_flame": deg(22, 0, 14),
            },
        ),
        (
            17,
            {
                "body": deg(10, 0, 8),
                "neck": deg(-6, 0, 8),
                "head": deg(-4, 0, 14),
                "front_left_base": deg(-16, 0, 22),
                "front_left_upper": deg(16, 0, 0),
                "front_left_lower": deg(-20, 0, 0),
                "front_right_base": deg(8, 0, -4),
                "front_right_upper": deg(-10, 0, 0),
                "front_right_lower": deg(12, 0, 0),
                "back_left_base": deg(-4, 0, -8),
                "back_right_base": deg(8, 0, 10),
                "tail_base": deg(16, 0, -18),
                "tail_middle": deg(24, 0, -26),
                "tail_flame": deg(30, 0, -34),
            },
        ),
        (
            33,
            {
                "body": deg(10, 0, -8),
                "neck": deg(-6, 0, -8),
                "head": deg(-4, 0, -14),
                "front_left_base": deg(8, 0, 4),
                "front_left_upper": deg(-10, 0, 0),
                "front_left_lower": deg(12, 0, 0),
                "front_right_base": deg(-16, 0, -22),
                "front_right_upper": deg(16, 0, 0),
                "front_right_lower": deg(-20, 0, 0),
                "back_left_base": deg(8, 0, -10),
                "back_right_base": deg(-4, 0, 8),
                "tail_base": deg(16, 0, 18),
                "tail_middle": deg(24, 0, 26),
                "tail_flame": deg(30, 0, 34),
            },
        ),
        (
            49,
            {
                "body": deg(12, 0, 0),
                "neck": deg(-2, 0, 0),
                "head": deg(2, 0, 0),
                "front_left_base": deg(-10, 0, 14),
                "front_left_upper": deg(10, 0, 0),
                "front_left_lower": deg(-14, 0, 0),
                "front_right_base": deg(-10, 0, -14),
                "front_right_upper": deg(10, 0, 0),
                "front_right_lower": deg(-14, 0, 0),
                "tail_base": deg(22, 0, 0),
                "tail_middle": deg(30, 0, 0),
                "tail_flame": deg(38, 0, 0),
            },
        ),
        (
            65,
            {
                "body": deg(6, 0, 0),
                "neck": deg(-4, 0, 0),
                "head": deg(-6, 0, 0),
                "tail_base": deg(10, 0, 6),
                "tail_middle": deg(16, 0, 10),
                "tail_flame": deg(22, 0, 14),
            },
        ),
    ]


def build_actions():
    armature = resolve_armature()
    ensure_pose_context(armature)
    bone_map = resolve_bone_map(armature)

    bpy.context.scene.render.fps = FPS

    compose_action(armature, bone_map, "Idle", idle_poses())
    compose_action(armature, bone_map, "Move", move_poses())
    compose_action(armature, bone_map, "Attack", attack_poses())
    compose_action(armature, bone_map, "Special", special_poses())
    compose_action(armature, bone_map, "Faint", faint_poses())
    compose_action(armature, bone_map, "Income", income_poses())

    bpy.context.scene.frame_set(1)
    print("FlamePup builder: finished.")


if __name__ == "__main__":
    build_actions()
