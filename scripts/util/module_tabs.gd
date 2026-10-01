class_name ModuleTabs

const ORDER := ["cargo", "propulsion", "armaments", "crafting", "docking", "hull"]
const LABELS := {
	"cargo": "Cargo & Storage",
	"propulsion": "Propulsion",
	"armaments": "Armaments",
	"crafting": "Crafting",
	"docking": "Docking",
	"hull": "Hull",
}
const CRAFTING := ["Assembler", "ChemicalAssembler", "ColdForge", "FDMPrinter", "Furnace", "HydraulicPress", "PCBMaker", "PhotolithographyScanner", "Polymerizer", "Shaper", "SheetMaker", "Smelter", "TubeWelder", "WaferSlicer", "WireExtruder", "WireWinder"]
const PROPULSION := ["LightThruster", "StandardThruster", "CapitalThruster", "RcsThruster", "SteeringThruster", "FuelCell"]
# A live server may still tag the system map "StarMap" (pre-rename build).
const SYSTEM_MAP_TYPES := ["SystemMap", "StarMap"]
const RADAR_TYPES := ["Radar"]


static func tab_for(type: String) -> String:
	if type == "Cargo":
		return "cargo"
	if type in PROPULSION:
		return "propulsion"
	if type in ["Turret", "Mine"]:
		return "armaments"
	if type in CRAFTING:
		return "crafting"
	if type in ["DockingPort", "DockingController"]:
		return "docking"
	if type in ["LightHull", "StandardHull", "HeavyHull"]:
		return "hull"
	return ""
