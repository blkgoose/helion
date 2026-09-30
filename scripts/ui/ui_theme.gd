class_name UiTheme

const ACCENT := Color("66ccff")
const BORDER := Color(0.4, 0.8, 1.0, 0.22)
const TEXT := Color("d6e2ee")
const MUTED := Color("8aa0b4")
const BG := Color(0.02, 0.04, 0.07)


static func panel_style(alpha := 0.62, border := BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BG, alpha)
	style.border_color = border
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.border_color = Color(ACCENT, 0.55) if border == BORDER else border
	style.set_corner_radius_all(1)
	style.corner_detail = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(ACCENT, 0.08)
	style.shadow_size = 10
	return style


static func button_style(bg_alpha: float, border: Color) -> StyleBoxFlat:
	var style := panel_style(bg_alpha, border)
	style.border_width_left = 1
	style.border_width_bottom = 2
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.shadow_size = 0
	return style


static func make() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	theme.default_font = font
	theme.default_font_size = 13
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style(0.94))
	theme.set_stylebox("normal", "Button", button_style(0.55, BORDER))
	theme.set_stylebox("hover", "Button", button_style(0.8, Color(ACCENT, 0.7)))
	theme.set_stylebox("pressed", "Button", button_style(0.95, ACCENT))
	theme.set_stylebox("focus", "Button", button_style(0.55, Color(ACCENT, 0.5)))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_stylebox("normal", "LineEdit", button_style(0.9, BORDER))
	theme.set_stylebox("focus", "LineEdit", button_style(0.9, ACCENT))
	theme.set_color("font_color", "LineEdit", TEXT)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(ACCENT, 0.22)
	selected.set_corner_radius_all(4)
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", selected)
	theme.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_constant("v_separation", "ItemList", 6)
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	theme.set_stylebox("separator", "HSeparator", sep)
	return theme
