class_name ElementColors
extends RefCounted

const colours := {
	"Marker": Color.BLACK,
	"Drift": Color(Color.DARK_GRAY, 0.3),
	"DriftSlice": Color(Color.DARK_GRAY, 0.3),
	"Bend": Color(Color.BLUE, 0.3),
	"RBend": Color(Color.BLUE, 0.3),
	"SimpleThinBend": Color(Color.REBECCA_PURPLE, 0.3),
	"DipoleEdge": Color(Color.DODGER_BLUE, 0.3),
	"DipoleFringe": Color(Color.DODGER_BLUE, 0.3),
	"Wedge": Color(0.9, 0.7, 0.3, 0.3),
	"Quadrupole": Color(Color.RED, 0.3),
	"SimpleThinQuadrupole": Color(Color.REBECCA_PURPLE, 0.3),
	"Sextupole": Color(Color.ORANGE, 0.3),
	"Octupole": Color(Color.GREEN, 0.3),
	"Multipole": Color(Color.REBECCA_PURPLE, 0.3),
	"CombinedFunctionMagnet": Color(Color.BLUE, 0.3),
	"Solenoid": Color(0.9, 0.2, 0.5, 0.3),
	"RFMultipole": Color(Color.REBECCA_PURPLE, 0.3),
	"Exciter": Color(0.8, 0.8, 0.2, 0.3),
	"Cavity": Color(1.0, 0.7, 0.2, 0.3),
	"ReferenceEnergyIncrease": Color(1.0, 0.9, 0.3, 0.3),
	"Elens": Color(0.2, 1.0, 0.7, 0.3),
	"NonLinearLens": Color(0.3, 0.9, 0.8, 0.3),
	"ElectronCooler": Color(0.3, 1.0, 0.9, 0.3),
	"Wire": Color(0.9, 0.9, 0.9, 0.3),
	"LimitEllipse": Color(Color.SLATE_GRAY, 0.3),
	"LimitRect": Color(Color.SLATE_GRAY, 0.3),
	"LimitRectEllipse": Color(Color.SLATE_GRAY, 0.3),
	"LimitRacetrack": Color(Color.SLATE_GRAY, 0.3),
	"LimitPolygon": Color(Color.SLATE_GRAY, 0.3),
	"LongitudinalLimitRect": Color(Color.SLATE_GRAY, 0.3),
	"UniformSolenoid": Color(Color.CADET_BLUE, 0.3)
}
	
static func get_element_color(type: String) -> Color:
	return colours.get(type, Color(1, 1, 1, 0.3))
