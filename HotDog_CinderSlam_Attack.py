"""
HotDog — Cinder-Slam Lunge (45 frames, non-looping)
Run in Blender: Scripting workspace → Open → Run Script (Armature named 'Armature' selected or only armature in file).

Requires: Blender 4.x / 5.x layered actions (keyframe_insert auto-builds slots/strips).

Bone name fallbacks: uses LeftFlameMane / RightFlameMane / TailFlame if TallFlame / LeftFlam / RightFla are absent.
"""

from __future__ import annotations

import math
import bpy
from mathutils import Euler, Vector

ARMATURE_NAME = "Armature"
ACTION_NAME = "HotDog_CinderSlam"
FPS = 30  # informational; scene fps unchanged

# --- Resolve bones (HotDog hierarchy variants) ---
FLAME_ALIASES = [
    ["TailFlame", "TallFlame", "Tail_Flame"],
    ["LeftFlameMane", "LeftFlam", "LeftFlame"],
    ["RightFlameMane", "RightFla", "RightFlame"],
]


def _pb(arm: bpy.types.Object, name: str):
    return arm.pose.bones.get(name)


def resolve_flame_bones(arm: bpy.types.Object) -> list[str]:
    found: list[str] = []
    for group in FLAME_ALIASES:
        for n in group:
            if _pb(arm, n):
                found.append(n)
                break
    return found


def E(rx: float, ry: float, rz: float):
    """Degrees → local quaternion (XYZ Euler order)."""
    return Euler(
        (math.radians(rx), math.radians(ry), math.radians(rz)),
        "XYZ",
    ).to_quaternion()


def ensure_action(arm: bpy.types.Object, name: str) -> bpy.types.Action:
    if name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[name])
    act = bpy.data.actions.new(name)
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = act
    return act


def channelbag_from_action(act: bpy.types.Action):
    if not act.slots or not act.layers or not act.layers[0].strips:
        return None, None
    slot = act.slots[0]
    strip = act.layers[0].strips[0]
    return strip.channelbag(slot), slot


def set_key_interpolation(act: bpy.types.Action, frame: int, mode: str):
    """Blender interpolation enum: CONSTANT, LINEAR, BEZIER, etc."""
    cb, _ = channelbag_from_action(act)
    if not cb:
        return
    for fc in cb.fcurves:
        for kp in fc.keyframe_points:
            if int(kp.co[0]) == frame:
                kp.interpolation = mode


def build_cinder_slam():
    arm = bpy.data.objects.get(ARMATURE_NAME)
    if not arm or arm.type != "ARMATURE":
        raise RuntimeError(f"Object '{ARMATURE_NAME}' not found or not an armature.")

    flame_bones = resolve_flame_bones(arm)
    if len(flame_bones) < 3:
        print(
            "[HotDog_CinderSlam] Warning: expected 3 flame bones, found:",
            flame_bones,
        )

    act = ensure_action(arm, ACTION_NAME)

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- Neutral (frame 1): identity poses used by this rig's rest ---
    def neutral_pose():
        for pb in arm.pose.bones:
            pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)

    neutral_pose()

    def key_rot(pb_name: str, f: int, quat):
        pb = _pb(arm, pb_name)
        if not pb:
            return
        pb.rotation_quaternion = quat
        pb.keyframe_insert(data_path="rotation_quaternion", frame=f)

    def key_loc(pb_name: str, f: int, loc: tuple[float, float, float]):
        pb = _pb(arm, pb_name)
        if not pb:
            return
        pb.location = Vector(loc)
        pb.keyframe_insert(data_path="location", frame=f)

    def key_scale(pb_name: str, f: int, sc: tuple[float, float, float]):
        pb = _pb(arm, pb_name)
        if not pb:
            return
        pb.scale = Vector(sc)
        pb.keyframe_insert(data_path="scale", frame=f)

    def key_all_bones_generic(f: int):
        """Keyframe every pose bone at current pose (dense neutral handoff)."""
        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=f)
            pb.keyframe_insert(data_path="location", frame=f)
            pb.keyframe_insert(data_path="scale", frame=f)

    # Frame 1 — full neutral snapshot (prevents stray channels)
    bpy.context.scene.frame_set(1)
    neutral_pose()
    key_all_bones_generic(1)

    # --- Anticipation 1–12 (crouch, hind load, tuck head, coil tail) ---
    for f in (6, 12):
        t = (f - 1) / 11.0  # 0..1 across anticipation
        # Base / Body drop and slight rearward prep
        key_loc("Base", f, (0.0, -0.04 * t, -0.12 * t))
        key_rot("Body", f, E(-8.0 * t, 0.0, 2.0 * t))
        key_rot("Chest", f, E(-5.0 * t, 0.0, 0.0))
        key_rot("Neck", f, E(12.0 * t, 0.0, 0.0))  # tuck head (look down)
        key_rot("Head", f, E(8.0 * t, 0.0, 0.0))
        key_rot("Face", f, E(0.0, 0.0, 0.0))
        # Weight on hind bases (compress into ground)
        key_loc("BackLeftLegBase", f, (0.0, 0.0, -0.02 * t))
        key_loc("BackRightLegBase", f, (0.0, 0.0, -0.02 * t))
        key_rot("BackLeftLegBase", f, E(0.0, 0.0, 0.0))
        key_rot("BackRightLegBase", f, E(0.0, 0.0, 0.0))
        # Coil hind thighs back, bend hocks
        key_rot("BackLeftLegTop", f, E(-22.0 * t, 0.0, 10.0 * t))
        key_rot("BackRightLegTop", f, E(-22.0 * t, 0.0, -10.0 * t))
        key_rot("BackLeftLegLow", f, E(18.0 * t, 0.0, 0.0))
        key_rot("BackRightLegLow", f, E(18.0 * t, 0.0, 0.0))
        # Front legs gathered
        key_rot("FrontLeftLegTop", f, E(-12.0 * t, 0.0, 4.0 * t))
        key_rot("FrontRightLegTop", f, E(-12.0 * t, 0.0, -4.0 * t))
        key_rot("FrontLeftLegLow", f, E(35.0 * t, 0.0, 0.0))
        key_rot("FrontRightLegLow", f, E(35.0 * t, 0.0, 0.0))
        key_rot("TailBase", f, E(28.0 * t, 0.0, 6.0 * t))
        key_rot("Tail", f, E(-6.0 * t, 0.0, 0.0))
        for nm in flame_bones:
            key_scale(nm, f, (1.0, 1.0, 1.0))

    # --- Launch 12–20 (explosive leap, front reach ~60°, ignite @18) ---
    # u=0 at frame 12 matches anticipation Base (0,-0.04,-0.12)
    for f in range(12, 21):
        u = max(0.0, min(1.0, (f - 12) / 8.0))
        key_loc(
            "Base",
            f,
            (0.0, -0.04 + 0.39 * u, -0.12 + 0.55 * u),
        )  # forward Y, rise Z from crouch
        key_rot("Body", f, E(-8.0 + 26.0 * u, 0.0, 2.0 - 1.0 * u))
        key_rot("Chest", f, E(-5.0 + 12.0 * u, 0.0, 0.0))
        key_rot("Neck", f, E(12.0 - 14.0 * u, 0.0, 0.0))
        key_rot("Head", f, E(8.0 - 10.0 * u, 0.0, 0.0))
        # ~60° forward reach on front leg tops (tuned on local X from prior rig tests)
        reach = 58.0 * u
        key_rot("FrontLeftLegTop", f, E(-12.0 + (reach + 12.0) * u, 0.0, 4.0 - 6.0 * u))
        key_rot("FrontRightLegTop", f, E(-12.0 + (reach + 12.0) * u, 0.0, -4.0 + 6.0 * u))
        key_rot("FrontLeftLegLow", f, E(35.0 - 32.0 * u, 0.0, 0.0))
        key_rot("FrontRightLegLow", f, E(35.0 - 32.0 * u, 0.0, 0.0))
        # Hind extends behind during push-off then tucks slightly mid-air
        key_rot("BackLeftLegTop", f, E(-22.0 + 40.0 * u, 0.0, 10.0 - 14.0 * u))
        key_rot("BackRightLegTop", f, E(-22.0 + 40.0 * u, 0.0, -10.0 + 14.0 * u))
        key_rot("BackLeftLegLow", f, E(18.0 - 8.0 * u, 0.0, 0.0))
        key_rot("BackRightLegLow", f, E(18.0 - 8.0 * u, 0.0, 0.0))
        key_loc("BackLeftLegBase", f, (0.0, 0.0, -0.02 + 0.02 * u))
        key_loc("BackRightLegBase", f, (0.0, 0.0, -0.02 + 0.02 * u))
        key_rot("TailBase", f, E(28.0 - 18.0 * u, 0.0, 6.0 - 4.0 * u))
        key_rot("Tail", f, E(-6.0 + 10.0 * u, 0.0, 0.0))
        if f >= 18:
            sc = 1.4
        elif f <= 14:
            sc = 1.0
        else:
            sc = 1.0 + 0.4 * ((f - 14) / 4.0)  # 15–17 ramp, 18+ hold 1.4
        for nm in flame_bones:
            key_scale(nm, f, (sc, sc, sc))

    # --- Slam 20–28 (impact, chest low, face bite snap) ---
    for f in range(20, 29):
        v = (f - 20) / 8.0
        key_loc("Base", f, (0.0, 0.35 + 0.25 * v, 0.43 - 0.52 * v))  # carry momentum Y, slam Z down
        key_rot("Body", f, E(18.0 - 6.0 * v, 0.0, 1.0))
        key_rot("Chest", f, E(7.0 - 18.0 * v, 0.0, 0.0))  # drops low
        key_rot("Neck", f, E(-2.0 + 4.0 * v, 0.0, 0.0))
        key_rot("Head", f, E(-2.0 + 6.0 * v, 0.0, 0.0))
        key_rot("Face", f, E(22.0 * v, 0.0, 0.0))  # bite snap +X
        key_rot("FrontLeftLegTop", f, E(58.0 - 25.0 * v, 0.0, -2.0))
        key_rot("FrontRightLegTop", f, E(58.0 - 25.0 * v, 0.0, 2.0))
        key_rot("FrontLeftLegLow", f, E(3.0 + 38.0 * v, 0.0, 0.0))
        key_rot("FrontRightLegLow", f, E(3.0 + 38.0 * v, 0.0, 0.0))
        key_rot("BackLeftLegTop", f, E(18.0 - 10.0 * v, 0.0, -4.0 * v))
        key_rot("BackRightLegTop", f, E(18.0 - 10.0 * v, 0.0, 4.0 * v))
        key_rot("BackLeftLegLow", f, E(10.0 + 12.0 * v, 0.0, 0.0))
        key_rot("BackRightLegLow", f, E(10.0 + 12.0 * v, 0.0, 0.0))
        key_rot("TailBase", f, E(10.0 + 8.0 * v, 0.0, 2.0))
        sc = 1.4 - 0.25 * v
        for nm in flame_bones:
            key_scale(nm, f, (sc, sc, sc))

    # --- Recovery 28–45: settle + neck Z jiggle 30–38 ---
    for f in range(29, 46):
        w = (f - 28) / 17.0  # 0..1 recovery
        # Ease-out toward neutral
        ease = 1.0 - (1.0 - w) ** 2
        # Slam end (~frame 28): Base Y≈0.6, Z≈-0.09 → ease to 0
        key_loc(
            "Base",
            f,
            (0.0, 0.6 * (1.0 - ease), -0.09 * (1.0 - ease)),
        )
        key_rot("Body", f, E(12.0 * (1.0 - ease), 0.0, 1.0 * (1.0 - ease)))
        key_rot("Chest", f, E(-11.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("Head", f, E(4.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("Face", f, E(22.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("FrontLeftLegTop", f, E(33.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("FrontRightLegTop", f, E(33.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("FrontLeftLegLow", f, E(41.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("FrontRightLegLow", f, E(41.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("BackLeftLegTop", f, E(8.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("BackRightLegTop", f, E(8.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("BackLeftLegLow", f, E(22.0 * (1.0 - ease), 0.0, 0.0))
        key_rot("BackRightLegLow", f, E(22.0 * (1.0 - ease), 0.0, 0.0))
        key_loc("BackLeftLegBase", f, (0.0, 0.0, 0.0))
        key_loc("BackRightLegBase", f, (0.0, 0.0, 0.0))
        key_rot("TailBase", f, E(18.0 * (1.0 - ease), 0.0, 2.0 * (1.0 - ease)))
        key_rot("Tail", f, E(4.0 * (1.0 - ease), 0.0, 0.0))
        # Flame scale from post-slam (~1.15) back to 1.0
        sc_fl = 1.15 + (1.0 - 1.15) * ease
        for nm in flame_bones:
            key_scale(nm, f, (sc_fl, sc_fl, sc_fl))

        nz = 0.0
        if 30 <= f <= 38:
            nz = 12.0 if (f % 2 == 0) else -12.0
        key_rot("Neck", f, E(2.0 * (1.0 - ease), 0.0, nz))

    # Frame 45 hard neutral
    neutral_pose()
    bpy.context.scene.frame_set(45)
    key_all_bones_generic(45)

    act.frame_range = (1, 45)
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 45

    bpy.ops.object.mode_set(mode="OBJECT")

    # Interpolation hints (Blender 5 channelbag)
    try:
        set_key_interpolation(act, 12, "BEZIER")
        set_key_interpolation(act, 20, "BEZIER")
        set_key_interpolation(act, 28, "BEZIER")
    except Exception as ex:
        print("[HotDog_CinderSlam] interpolation pass skipped:", ex)

    print(f"[HotDog_CinderSlam] Created action '{ACTION_NAME}' on '{ARMATURE_NAME}', frames 1–45.")
    print("Flame bones keyed:", flame_bones)


if __name__ == "__main__":
    build_cinder_slam()
