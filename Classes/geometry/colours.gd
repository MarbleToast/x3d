class_name ElementColors
extends RefCounted

const colours := {
	"Marker": Color.BLACK,
	"Drift": Color(Color.DARK_GRAY, 0.3),
	"DriftSlice": Color(Color.DARK_GRAY, 0.3),
	"Bend": Color(Color.BLUE, 0.5),
	"RBend": Color(Color.BLUE, 0.5),
	"SimpleThinBend": Color(Color.REBECCA_PURPLE, 0.5),
	"DipoleEdge": Color(Color.DODGER_BLUE, 0.5),
	"DipoleFringe": Color(Color.DODGER_BLUE, 0.5),
	"Wedge": Color(0.9, 0.7, 0.5, 0.5),
	"Quadrupole": Color(Color.RED, 0.5),
	"SimpleThinQuadrupole": Color(Color.REBECCA_PURPLE, 0.5),
	"Sextupole": Color(Color.ORANGE, 0.5),
	"Octupole": Color(Color.GREEN, 0.5),
	"MultipoleKick": Color(Color.REBECCA_PURPLE, 0.5),
	"Multipole": Color(Color.REBECCA_PURPLE, 0.05),
	"CombinedFunctionMagnet": Color(Color.BLUE, 0.5),
	"Solenoid": Color(0.9, 0.2, 0.5, 0.5),
	"RFMultipole": Color(Color.REBECCA_PURPLE, 0.5),
	"Exciter": Color(0.8, 0.8, 0.2, 0.5),
	"Cavity": Color(1.0, 0.7, 0.2, 0.5),
	"ReferenceEnergyIncrease": Color(1.0, 0.9, 0.5, 0.5),
	"Elens": Color(0.2, 1.0, 0.7, 0.5),
	"NonLinearLens": Color(0.5, 0.9, 0.8, 0.5),
	"ElectronCooler": Color(0.5, 1.0, 0.9, 0.5),
	"Wire": Color(0.9, 0.9, 0.9, 0.5),
	"LimitEllipse": Color(Color.SLATE_GRAY, 0.5),
	"LimitRect": Color(Color.SLATE_GRAY, 0.5),
	"LimitRectEllipse": Color(Color.SLATE_GRAY, 0.5),
	"LimitRacetrack": Color(Color.SLATE_GRAY, 0.5),
	"LimitPolygon": Color(Color.SLATE_GRAY, 0.5),
	"LongitudinalLimitRect": Color(Color.SLATE_GRAY, 0.5),
	"UniformSolenoid": Color(Color.DARK_BLUE, 0.5)
}
	
static func get_element_color(type: String) -> Color:
	return colours.get(type, Color(1, 1, 1, 0.5))
