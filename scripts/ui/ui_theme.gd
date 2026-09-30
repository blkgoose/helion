class_name UiTheme

const ACCENT := Color("66ccff")
const BORDER := Color("333333")
const TEXT := Color("cfcfcf")


static func panel_style(alpha := 0.5, border := BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, alpha)
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func make() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"])
	theme.default_font = font
	theme.default_font_size = 13
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style(0.92))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := panel_style(0.5 if state == "normal" else 0.75, Color("666666") if state == "hover" else BORDER)
		theme.set_stylebox(state, "Button", style)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	var edit := panel_style(0.9)
	theme.set_stylebox("normal", "LineEdit", edit)
	theme.set_stylebox("focus", "LineEdit", panel_style(0.9, ACCENT))
	return theme
