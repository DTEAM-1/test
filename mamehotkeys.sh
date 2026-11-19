#!/usr/bin/env bash
# =============================================================================
# mamehotkeys.sh - RetroPie input configuration script for MAME standalone
#
# Gives MAME standalone the same hotkey combos RetroPie gives RetroArch,
# with Select as the hotkey, for the player 1 gamepad:
#
#   Select + Start  quit          Select + X   MAME menu
#   Select + R1     quick save    Select + B   soft reset
#   Select + L1     quick load    Select + L3  snapshot
#                                 Select + R3  record AVI video
#
# The combos are written to MAME's default.cfg (cfg_directory of mame.ini),
# so they apply to every game that has no input settings of its own.
# Keyboard keys are kept. Single gamepad buttons are removed from these
# functions and from every other in-game shortcut (pause, fast forward,
# show FPS...), so a lone button can't quit, save or pause by accident.
# Menu navigation buttons (UI Select/Back/Up/Down...) are not touched.
#
# How MAME numbers gamepad buttons is computed exactly like MAME does
# (src/osd/modules/input/input_sdl.cpp, MAME 0.264 and later), from the SDL2
# game controller mapping MAME will get through runcommand: SDL2's built-in
# database plus /opt/retropie/configs/all/sdl2_gamecontrollerdb.txt.
#
# Two ways to use it:
#  1. Automatic: copy it to
#       /opt/retropie/supplementary/emulationstation/scripts/configscripts/
#     It then runs each time a gamepad is configured in EmulationStation
#     (only for the gamepad that MAME will see as "Joy 1").
#  2. By hand, for gamepads already configured (player 1 gamepad connected):
#       bash mamehotkeys.sh
#
# Needs: python3, libSDL2 (both are on every RetroPie install).
# =============================================================================

function check_mamehotkeys() {
    [[ -x /opt/retropie/emulators/mame/mame ]] || return 1
    return 0
}

function onstart_mamehotkeys_joystick() {
    :
}

function onend_mamehotkeys_joystick() {
    _run_mamehotkeys "$home/.emulationstation/es_temporaryinput.cfg" "$DEVICE_GUID"
}

function _run_mamehotkeys() {
    local es_file="$1" guid="$2"
    local cfgdir="/opt/retropie/configs"
    local ini="$cfgdir/mame/mame.ini"
    local mamecfg
    mamecfg=$(awk '$1=="cfg_directory"{print $2}' "$ini" 2>/dev/null)
    [[ -z "$mamecfg" ]] && mamecfg="$home/RetroPie/roms/mame/cfg"
    local py="/tmp/mamehotkeys.py"
    _mamehotkeys_python > "$py"
    python3 -I "$py" "$mamecfg/default.cfg" "$es_file" "$cfgdir/all/sdl2_gamecontrollerdb.txt" "$guid"
    rm -f "$py"
}

function _mamehotkeys_python() {
cat << 'EOF'
import sys, os, ctypes, xml.etree.ElementTree as ET

CFG, ES, SDLDB, GUID = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# ---------------------------------------------------------------- SDL2 mapping
# Same environment as runcommand: our database first (SDL_GAMECONTROLLERCONFIG)
if os.path.isfile(SDLDB) and not os.environ.get("SDL_GAMECONTROLLERCONFIG"):
    os.environ["SDL_GAMECONTROLLERCONFIG"] = open(SDLDB, errors="ignore").read()

class Guid(ctypes.Structure):
    _fields_ = [("data", ctypes.c_uint8 * 16)]

def sdl_query(guid):
    """Return (mapping string or None, GUID of joystick #0 or None)."""
    try:
        sdl = ctypes.CDLL("libSDL2-2.0.so.0")
    except OSError:
        return None, None
    sdl.SDL_JoystickGetGUIDFromString.restype = Guid
    sdl.SDL_JoystickGetGUIDFromString.argtypes = [ctypes.c_char_p]
    sdl.SDL_JoystickGetDeviceGUID.restype = Guid
    sdl.SDL_JoystickGetDeviceGUID.argtypes = [ctypes.c_int]
    sdl.SDL_JoystickGetGUIDString.argtypes = [Guid, ctypes.c_char_p, ctypes.c_int]
    sdl.SDL_GameControllerMappingForGUID.restype = ctypes.c_void_p
    sdl.SDL_GameControllerMappingForGUID.argtypes = [Guid]
    sdl.SDL_free.argtypes = [ctypes.c_void_p]
    if sdl.SDL_Init(0x2000) != 0:            # SDL_INIT_GAMECONTROLLER
        return None, None
    first = None
    if sdl.SDL_NumJoysticks() > 0:
        buf = ctypes.create_string_buffer(64)
        sdl.SDL_JoystickGetGUIDString(sdl.SDL_JoystickGetDeviceGUID(0), buf, 64)
        first = buf.value.decode()
    if not guid:
        guid = first
    mapping = None
    if guid:
        p = sdl.SDL_GameControllerMappingForGUID(sdl.SDL_JoystickGetGUIDFromString(guid.encode()))
        if p:
            mapping = ctypes.string_at(p).decode(errors="ignore")
            sdl.SDL_free(p)
    sdl.SDL_Quit()
    return mapping, first

mapping, first = sdl_query(GUID)
guid = GUID or first
if not guid:
    sys.exit("mamehotkeys: no gamepad connected, nothing done")
if GUID and first and GUID != first:
    print(f"mamehotkeys: this gamepad is not MAME's Joy 1 (player 1), hotkeys left unchanged")
    sys.exit(0)

# ------------------------------------------------- EmulationStation inputs
es_inputs = {}
try:
    root = ET.parse(ES).getroot()
    for dev in root.iter("inputConfig"):
        if dev.get("deviceGUID") == guid:
            es_inputs = {i.get("name"): (i.get("type"), i.get("id"), i.get("value"))
                         for i in dev.findall("input")}
except (OSError, ET.ParseError):
    pass

# role -> binding ("b3", "a2", "h0.1"...)
roles = {}
if mapping:
    for field in mapping.split(",")[2:]:
        if ":" in field:
            k, v = field.split(":", 1)
            if k not in ("platform", "crc", "hint", "type"):
                roles[k] = v.strip()
else:
    # SDL does not know this gamepad yet: build the mapping the way RetroPie's
    # sdl2.sh configscript does (same names, same leftshoulder/rightshoulder rule)
    es2sdl = {"a": "a", "b": "b", "x": "x", "y": "y", "start": "start", "select": "back",
              "leftshoulder": "leftshoulder", "rightshoulder": "rightshoulder",
              "pageup": "rightshoulder", "pagedown": "leftshoulder",
              "lefttrigger": "lefttrigger", "righttrigger": "righttrigger",
              "leftthumb": "leftstick", "rightthumb": "rightstick",
              "up": "dpup", "down": "dpdown", "left": "dpleft", "right": "dpright"}
    pre = {"button": "b", "axis": "a", "hat": "h"}
    for name, (typ, iid, val) in es_inputs.items():
        if name in es2sdl and typ in pre:
            roles[es2sdl[name]] = pre[typ] + iid + (f".{val}" if typ == "hat" else "")

# ------------------------------------- MAME 0.264+ item names for this gamepad
tok = {}
if roles:
    # numbered buttons, in MAME's order; triggers only when bound to a button
    n = 1
    for r in ("a", "b", "x", "y", "leftshoulder", "rightshoulder", "lefttrigger",
              "righttrigger", "leftstick", "rightstick", "paddle1", "paddle2",
              "paddle3", "paddle4", "guide", "misc1", "touchpad"):
        v = roles.get(r)
        if not v:
            continue
        if r in ("lefttrigger", "righttrigger") and not v.lstrip("+-").startswith("b"):
            continue
        tok[r] = f"JOYCODE_1_BUTTON{n}"
        n += 1
    if "back" in roles:
        tok["back"] = "JOYCODE_1_SELECT"
    if "start" in roles:
        tok["start"] = "JOYCODE_1_START"
else:
    # plain joystick (no game controller mapping): MAME numbers raw buttons
    es2role = {"a": "a", "b": "b", "x": "x", "y": "y", "start": "start", "select": "back",
               "leftshoulder": "leftshoulder", "rightshoulder": "rightshoulder",
               "pageup": "leftshoulder", "pagedown": "rightshoulder",
               "leftthumb": "leftstick", "rightthumb": "rightstick"}
    for name, (typ, iid, val) in es_inputs.items():
        if name in es2role and typ == "button":
            tok[es2role[name]] = f"JOYCODE_1_BUTTON{int(iid) + 1}"

# Follow the PHYSICAL buttons the user configured in EmulationStation.
# RetroPie's sdl2.sh maps the old ES names pageup/pagedown to the opposite
# shoulders, so role names alone could swap L1 and R1: look up which SDL role
# each configured button is bound to, and use that role's MAME name.
ES_NAMES = {"back": ("select",), "start": ("start",), "x": ("x",), "b": ("b",),
            "leftshoulder": ("leftshoulder", "pageup"),
            "rightshoulder": ("rightshoulder", "pagedown"),
            "leftstick": ("leftthumb",), "rightstick": ("rightthumb",)}
def binding(entry):
    typ, iid, val = entry
    if typ == "button": return "b" + iid
    if typ == "hat": return f"h{iid}.{val}"
    if typ == "axis": return "a" + iid
    return None
if roles:
    phys = {}
    for want, names in ES_NAMES.items():
        entry = next((es_inputs[n] for n in names if n in es_inputs), None)
        if not entry: continue
        b = binding(entry)
        role = next((r for r, v in roles.items()
                     if v.lstrip("+-").rstrip("~") == b and r in tok), None)
        if role: phys[want] = tok[role]
    for want, t in phys.items():
        tok[want] = t

hot = tok.get("back")
if not hot:
    sys.exit("mamehotkeys: no Select button found for this gamepad, nothing done")

# ------------------------------------------------------------- combos to write
COMBOS = {"UI_CANCEL": "start", "UI_SAVE_STATE_QUICK": "rightshoulder",
          "UI_LOAD_STATE_QUICK": "leftshoulder", "UI_MENU": "x",
          "UI_SOFT_RESET": "b", "UI_SNAPSHOT": "leftstick", "UI_RECORD_AVI": "rightstick"}
# MAME 0.289 keyboard defaults (src/emu/inpttype.ipp), kept or restored
KEYS = {"UI_CANCEL": "KEYCODE_ESC", "UI_MENU": "KEYCODE_TAB",
        "UI_SAVE_STATE_QUICK": "KEYCODE_F6 KEYCODE_LSHIFT OR KEYCODE_F6 KEYCODE_RSHIFT",
        "UI_LOAD_STATE_QUICK": "KEYCODE_F7 KEYCODE_LSHIFT OR KEYCODE_F7 KEYCODE_RSHIFT",
        "UI_SOFT_RESET": "KEYCODE_F3 NOT KEYCODE_LSHIFT NOT KEYCODE_RSHIFT",
        "UI_SNAPSHOT": "KEYCODE_F12 NOT KEYCODE_LSHIFT",
        "UI_RECORD_AVI": "KEYCODE_F12 KEYCODE_LSHIFT KEYCODE_LCONTROL"}

# ------------------------------------------------------------ edit default.cfg
os.makedirs(os.path.dirname(CFG), exist_ok=True)
if os.path.isfile(CFG):
    tree = ET.parse(CFG)
    if not os.path.isfile(CFG + ".before-hotkeys"):
        open(CFG + ".before-hotkeys", "wb").write(open(CFG, "rb").read())
else:
    tree = ET.ElementTree(ET.fromstring(
        '<mameconfig version="10"><system name="default"><input/></system></mameconfig>'))
root = tree.getroot()
sysd = next((s for s in root.findall("system") if s.get("name") == "default"), None)
if sysd is None:
    sysd = ET.SubElement(root, "system", {"name": "default"})
inp = sysd.find("input")
if inp is None:
    inp = ET.Element("input"); sysd.insert(0, inp)
ports = {p.get("type"): p for p in inp.findall("port")}

print(f"mamehotkeys: gamepad {guid}, hotkey = Select")
for port, role in COMBOS.items():
    p = ports.get(port)
    if p is None:
        p = ET.SubElement(inp, "port", {"type": port})
        ET.SubElement(p, "newseq", {"type": "standard"}).text = KEYS[port]
    s = p.find("newseq")
    if s is None:
        s = ET.SubElement(p, "newseq", {"type": "standard"}); s.text = KEYS[port]
    alts = [" ".join(a.split()) for a in " ".join((s.text or "").split()).split(" OR ") if a.strip()]
    keep = [a for a in alts if "JOYCODE_1_" not in a]     # keyboard, mouse, other gamepads
    if not any("KEYCODE_" in a for a in keep):
        keep = KEYS[port].split(" OR ") + keep
    if role in tok:
        keep.append(f"{hot} {tok[role]}")
        state = f"Select + {role}"
    else:
        state = f"no {role} on this gamepad, keyboard only"
    s.text = " OR ".join(keep)
    print(f"  {port:20s} {state}")
# Other in-game shortcuts: remove any single gamepad button left on them
# (menu navigation inputs such as UI Select/Back/Up/Down are not touched).
SHORTCUTS = ("UI_ON_SCREEN_DISPLAY", "UI_TOGGLE_UI", "UI_DEBUG_BREAK", "UI_PAUSE",
             "UI_PAUSE_SINGLE", "UI_REWIND_SINGLE", "UI_SAVE_STATE", "UI_LOAD_STATE",
             "UI_RESET_MACHINE", "UI_SHOW_GFX", "UI_FRAMESKIP_DEC", "UI_FRAMESKIP_INC",
             "UI_THROTTLE", "UI_FAST_FORWARD", "UI_SHOW_FPS", "UI_RECORD_MNG",
             "UI_TOGGLE_CHEAT", "UI_DISPLAY_COMMENT", "UI_ROTATE", "UI_SHOW_PROFILER",
             "UI_RELEASE_POINTER", "UI_PASTE", "UI_TAPE_START", "UI_TAPE_STOP")
for port in SHORTCUTS:
    p = ports.get(port)
    s = p.find("newseq") if p is not None else None
    if s is None or not s.text:
        continue
    alts = [" ".join(a.split()) for a in " ".join(s.text.split()).split(" OR ") if a.strip()]
    keep = [a for a in alts if not (a.startswith("JOYCODE_") and " " not in a)]
    if keep == alts:
        continue
    gone = ", ".join(a for a in alts if a not in keep)
    if keep:
        s.text = " OR ".join(keep)
    else:
        inp.remove(p)                       # back to MAME's default keys
    print(f"  {port:20s} single gamepad button removed ({gone})")
ET.indent(tree, space="    ")
tree.write(CFG, encoding="UTF-8", xml_declaration=True)
print(f"mamehotkeys: written to {CFG}")
EOF
}

# run by hand: bash mamehotkeys.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    home="$(eval echo ~"$(id -un)")"
    if pgrep -x mame > /dev/null; then
        echo "mamehotkeys: quit MAME first (it rewrites default.cfg when it exits)"
        exit 1
    fi
    _run_mamehotkeys "/opt/retropie/configs/all/emulationstation/es_input.cfg" ""
fi
