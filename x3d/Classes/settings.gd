extends Node

# =================== Survey Elements
enum RendererType {
	DEFAULT,
	WIREFRAME
}
var RENDERER_TYPE := RendererType.DEFAULT

## Defines the mesh generation options for each ElementType.
var ELEMENT_DIMENSIONS := {
	Drift = { width = 0.2, height = 0.2, type = "box" },
	DriftSlice = { width = 0.2, height = 0.2, type = "box" },
	Quadrupole = { 
		type = "quadrupole",
		width = 0.3, 
		height = 0.3,
		aperture_radius = 0.05, 
		pole_width = 0.08, 
		pole_tip_width = 0.06, 
		yoke_inner_radius = 0.2, 
		yoke_outer_radius = 0.25, 
		custom = true
	},
	Bend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	RBend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	SimpleThinBend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	LimitEllipse = { radius = 0.3, type = "circle" },
	UniformSolenoid = { radius = 0.3, type = "circle" },
	Solenoid = { radius = 0.3, type = "circle" },
	Sextupole = { num_poles = 6, pole_width = 0.12, pole_height = 0.07, pole_radius = 0.3, type = "multipole" },
	Octupole = { num_poles = 8, pole_width = 0.08, pole_height = 0.05, pole_radius = 0.3, type = "multipole" },
	Multipole = { num_poles = 10, pole_width = 0.07, pole_height = 0.04, pole_radius = 0.3, type = "multipole" },
	MultipoleKick = { num_poles = 10, pole_width = 0.07, pole_height = 0.04, pole_radius = 0.3, type = "multipole" },
	_default = { width = 0.3, height = 0.3, type = "box" }
}

var ELEMENT_BLACKLIST: PackedStringArray = PackedStringArray([])


# ===================== Apertures and Twiss
var SWEEP_CHUNK_VERTEX_LIMIT := 65000
var BEAM_ELLIPSE_RESOLUTION := 20

## How much should we modify the thickness of the aperture? 1.0 = 100% actual size.
var APERTURE_THICKNESS_MODIFIER := 1.0

var BEAM_NUM_SIGMAS := 3
