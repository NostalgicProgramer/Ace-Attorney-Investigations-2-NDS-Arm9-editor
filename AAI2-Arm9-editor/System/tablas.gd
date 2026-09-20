extends Control

@onready var item_list = $ItemList2
@onready var editor = $TextEdit
@onready var texture_rect = $TextureRect
@onready var btn_guardar = $BtnGuardarTabla

var parser = DataParser.new()
var caracteres = []
var archivo_actual_path: String = ""
var nombre_tabla_actual: String = ""
var nombre_glyphs_actual: String = ""
var atlas_completo: Texture2D = null

func _ready():
	if not item_list.item_selected.is_connected(_on_caracter_seleccionado):
		item_list.item_selected.connect(_on_caracter_seleccionado)
	if btn_guardar and not btn_guardar.pressed.is_connected(_on_guardar_presionado):
		btn_guardar.pressed.connect(_on_guardar_presionado)

func cargar_editor(ruta: String, nombre_tabla: String, nom_glyphs: String, textura: Texture2D):
	archivo_actual_path = ruta
	nombre_tabla_actual = nombre_tabla
	nombre_glyphs_actual = nom_glyphs
	atlas_completo = textura
	
	caracteres = parser.obtener_datos_tabla(archivo_actual_path, nombre_tabla_actual)
	
	# Ordenar por el orden físico de la textura (glyph_index)
	caracteres.sort_custom(func(a, b): return a.glyph_index < b.glyph_index)
	
	# Usamos nombre_glyphs_actual en ambos lados
	var conf = parser.ARM9_LAYOUT[nombre_glyphs_actual] if parser.ARM9_LAYOUT.has(nombre_glyphs_actual) else {}
	var h_val = conf.get("h", 16)
	
	item_list.clear()
	for c in caracteres:
		item_list.add_item("Glifo %d | Letra: '%s' (Ancho: %d, Alto: %d)" % [c.glyph_index, c.char, c.width, h_val])
	
	if caracteres.size() > 0:
		item_list.select(0)
		_on_caracter_seleccionado(0)

func _on_caracter_seleccionado(index: int):
	if index < 0 or index >= caracteres.size(): 
		return
	var seleccionado = caracteres[index]
	
	var conf = parser.ARM9_LAYOUT[nombre_glyphs_actual] if parser.ARM9_LAYOUT.has(nombre_glyphs_actual) else {}
	var h_val = conf.get("h", 16)
	
	# Cambié "Glifo" por "Puntero" para que tengas claro que ese valor grande es la dirección RAM.
	editor.text = "Letra: '%s'\nAncho: %d\nAlto: %d\nPuntero: %d" % [seleccionado.char, seleccionado.width, h_val, seleccionado.glyph_index]
	
	if atlas_completo and nombre_glyphs_actual != "":
		var cols = 64
		
		# USAMOS EL ÍNDICE SECUENCIAL DE LA LISTA EN LUGAR DEL PUNTERO DE MEMORIA
		var g_idx = index 
		
		var grid_x = (g_idx % cols) * 16
		var grid_y = floor(float(g_idx) / cols) * h_val
		
		var region = AtlasTexture.new()
		region.atlas = atlas_completo
		region.region = Rect2(grid_x, grid_y, 16, h_val)
		
		texture_rect.texture = region
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.custom_minimum_size = Vector2(32, 28)

func _on_guardar_presionado():
	var items = item_list.get_selected_items()
	if items.size() == 0:
		print("Error: Selecciona un carácter de la lista primero.")
		return
		
	var idx = items[0]
	
	# Extraemos el valor numérico del ancho de forma segura desde el TextEdit
	var regex = RegEx.new()
	regex.compile("Ancho:\\s*(\\d+)")
	var result = regex.search(editor.text)
	var nuevo_ancho = int(result.get_string(1)) if result else int(editor.text)
	
	var conf = parser.ARM9_LAYOUT[nombre_glyphs_actual]
	var h_val = conf.get("h", 16)
	
	if archivo_actual_path != "" and nombre_tabla_actual != "":
		var item_real_index = caracteres[idx].index
		var exito = parser.actualizar_ancho_glifo(archivo_actual_path, nombre_tabla_actual, item_real_index, nuevo_ancho)
		if exito:
			caracteres[idx].width = nuevo_ancho
			item_list.set_item_text(idx, "Glifo %d | Letra: '%s' (Ancho: %d, Alto: %d)" % [caracteres[idx].glyph_index, caracteres[idx].char, nuevo_ancho, h_val])
			
			# Actualizamos el bloque de texto con el nuevo ancho guardado
			editor.text = "Letra: '%s'\nAncho: %d\nAlto: %d\nGlifo: %d" % [caracteres[idx].char, nuevo_ancho, h_val, caracteres[idx].glyph_index]
			print("¡Ancho actualizado con éxito en la tabla!")
	else:
		print("Error: Faltan datos de ruta o tabla.")
