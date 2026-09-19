extends Control

@onready var file_dialog = $FileDialog
@onready var dialog_save = $FileDialogGuardar
@onready var item_list = $ItemList
@onready var texture_rect = $Texturas/ScrollContainer/TextureRect
@onready var editor_tablas = $Tablas
@onready var visor_glifos = $Texturas

@onready var BtnExtraerBin = $Tablas/BtnExtraerBin
@onready var BtnInyectarBin = $Tablas/BtnInyectarBin

var parser = DataParser.new()
var archivo_actual_path: String = ""
const CONFIG_PATH = "user://config.cfg"
var dialog_cargar_img = FileDialog.new()
var dialog_exportar_bin = FileDialog.new()
var dialog_importar_bin = FileDialog.new()


func _ready():
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.bin ; Archivos Binarios (*.bin)"])
	file_dialog.file_selected.connect(_on_archivo_seleccionado)
	if has_node("BtnAbrir"): $BtnAbrir.pressed.connect(func(): file_dialog.popup_centered())
	if has_node("BtnGuardar"): $BtnGuardar.pressed.connect(_on_guardar)
	
	# Configuración inicial del FileDialog de Guardar Texturas que ya tenías creado
	if dialog_save:
		dialog_save.access = FileDialog.ACCESS_FILESYSTEM
		dialog_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog_save.filters = PackedStringArray(["*.png ; Imágenes PNG (*.png)"])
		if not dialog_save.file_selected.is_connected(_on_imagen_png_guardar_seleccionada):
			dialog_save.file_selected.connect(_on_imagen_png_guardar_seleccionada)

	$Texturas/BtnCargarImagen.pressed.connect(_on_btn_cargar_imagen_pressed)
	
	# Restaurar la última ruta guardada del ARM9
	var ruta_arm9 = _cargar_ultima_ruta_arm9()
	if ruta_arm9 != "" and DirAccess.dir_exists_absolute(ruta_arm9):
		file_dialog.current_dir = ruta_arm9
		file_dialog.current_path = ruta_arm9 + "/"
	
	# Configurar FileDialog para EXTRAER .bin
	dialog_exportar_bin.access = FileDialog.ACCESS_FILESYSTEM
	dialog_exportar_bin.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog_exportar_bin.filters = PackedStringArray(["*.bin ; Archivos Binarios (*.bin)"])
	dialog_exportar_bin.file_selected.connect(_on_exportar_bin_seleccionado)
	add_child(dialog_exportar_bin)
	
	# Configurar FileDialog para INYECTAR .bin
	dialog_importar_bin.access = FileDialog.ACCESS_FILESYSTEM
	dialog_importar_bin.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog_importar_bin.filters = PackedStringArray(["*.bin ; Archivos Binarios (*.bin)"])
	dialog_importar_bin.file_selected.connect(_on_importar_bin_seleccionado)
	add_child(dialog_importar_bin)

	# Conectar botones de la interfaz (asegúrate de crearlos en el árbol de nodos si usas escenas)
	BtnExtraerBin.pressed.connect(_on_btn_extraer_bin_pressed)
	BtnInyectarBin.pressed.connect(_on_btn_inyectar_bin_pressed)

# --- LÓGICA DE EXTRACCIÓN Y VOLCADO BINARIO ---

func _on_btn_extraer_bin_pressed():
	if archivo_actual_path == "":
		print("Error: Primero debes abrir un archivo ARM9.")
		return
	if not item_list.is_anything_selected():
		print("Error: Selecciona un bloque de la lista para extraer.")
		return
		
	var nombre_bloque = item_list.get_item_text(item_list.get_selected_items()[0])
	
	var ultima_ruta = _cargar_ultima_ruta_arm9()
	if ultima_ruta != "" and DirAccess.dir_exists_absolute(ultima_ruta):
		dialog_exportar_bin.current_dir = ultima_ruta
		dialog_exportar_bin.current_path = ultima_ruta + "/" + nombre_bloque + ".bin"
	else:
		dialog_exportar_bin.current_file = nombre_bloque + ".bin"
		
	dialog_exportar_bin.popup_centered()

func _on_exportar_bin_seleccionado(path_destino: String):
	if not item_list.is_anything_selected(): return
	var nombre_bloque = item_list.get_item_text(item_list.get_selected_items()[0])
	
	# Leemos los bytes crudos directamente desde el ARM9 actual
	var datos_raw = parser.cargar_bloque(archivo_actual_path, nombre_bloque)
	
	if datos_raw.is_empty():
		print("Error: No se pudieron extraer datos del bloque %s." % nombre_bloque)
		return
		
	var file = FileAccess.open(path_destino, FileAccess.WRITE)
	if file:
		file.store_buffer(datos_raw)
		file.close()
		_guardar_ultima_ruta_arm9(path_destino)
		print("¡Bloque '%s' extraído exitosamente en: %s!" % [nombre_bloque, path_destino])
	else:
		print("Error al escribir el archivo .bin de destino.")

# --- LÓGICA DE INYECCIÓN BINARIA ---

func _on_btn_inyectar_bin_pressed():
	if archivo_actual_path == "":
		print("Error: Primero debes abrir un archivo ARM9.")
		return
	if not item_list.is_anything_selected():
		print("Error: Selecciona el bloque de destino en la lista.")
		return
		
	var ultima_ruta = _cargar_ultima_ruta_arm9()
	if ultima_ruta != "" and DirAccess.dir_exists_absolute(ultima_ruta):
		dialog_importar_bin.current_dir = ultima_ruta
		
	dialog_importar_bin.popup_centered()

func _on_importar_bin_seleccionado(path_origen: String):
	if not item_list.is_anything_selected(): return
	var index_sel = item_list.get_selected_items()[0]
	var nombre_bloque = item_list.get_item_text(index_sel)
	var conf = parser.ARM9_LAYOUT[nombre_bloque]
	
	# 1. Leer el .bin externo
	var file = FileAccess.open(path_origen, FileAccess.READ)
	if not file:
		print("Error: No se pudo abrir el archivo .bin seleccionado.")
		return
		
	var bytes_importados = file.get_buffer(file.get_length())
	file.close()
	
	# 2. Validación de tamaño estricta (Evita corromper el ARM9 si se selecciona un .bin equivocado)
	if bytes_importados.size() != conf["size"]:
		print("Error de Inyección: El archivo mide %d bytes, pero el bloque '%s' requiere exactamente %d bytes." % [
			bytes_importados.size(), nombre_bloque, conf["size"]
		])
		return
		
	# 3. Inyectar datos directamente al offset exacto en el ARM9
	var exito = parser.escribir_bloque(archivo_actual_path, nombre_bloque, bytes_importados)
	if exito:
		print("¡Inyección exitosa! Bloque '%s' actualizado en el ARM9." % nombre_bloque)
		_guardar_ultima_ruta_arm9(path_origen)
		
		# 4. Recargar automáticamente la vista (renderizado de gráficos o lista de tablas)
		_on_item_list_item_selected(index_sel)

# --- RUTAS SEPARADAS EN CONFIG.CFG ---

func _guardar_ultima_ruta_arm9(path_completo: String):
	var carpeta_path = path_completo.get_base_dir()
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("Historial", "ultima_ruta_arm9", carpeta_path)
	config.save(CONFIG_PATH)

func _cargar_ultima_ruta_arm9() -> String:
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return config.get_value("Historial", "ultima_ruta_arm9", "")
	return ""

func _guardar_ultima_ruta_textura(path_completo: String):
	var carpeta_path = path_completo.get_base_dir()
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("Historial", "ultima_ruta_textura", carpeta_path)
	config.save(CONFIG_PATH)

func _cargar_ultima_ruta_textura() -> String:
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return config.get_value("Historial", "ultima_ruta_textura", "")
	return ""

func _on_archivo_seleccionado(path: String):
	_guardar_ultima_ruta_arm9(path)
	
	# 1. Leer los bytes del archivo seleccionado
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Error: No se pudo abrir el archivo ARM9 seleccionado.")
		return
		
	var bytes_originales = file.get_buffer(file.get_length())
	file.close()
	
	# 2. Verificar si requiere descompresión BLZ
	if BLZ.esta_comprimido(bytes_originales):
		print("Archivo comprimido detectado. Descomprimiendo ARM9 nativamente...")
		var bytes_descomprimidos = BLZ.descomprimir(bytes_originales)
		
		# Crear la versión descomprimida de trabajo en el mismo directorio
		var ruta_descomprimida = path.get_base_dir() + "/arm9_descomprimido.bin"
		var file_out = FileAccess.open(ruta_descomprimida, FileAccess.WRITE)
		if file_out:
			file_out.store_buffer(bytes_descomprimidos)
			file_out.close()
			archivo_actual_path = ruta_descomprimida
			print("¡ARM9 descomprimido con éxito! Archivo de trabajo: %s" % ruta_descomprimida)
		else:
			print("Error al escribir el archivo ARM9 descomprimido.")
			return
	else:
		print("El archivo ARM9 ya está descomprimido. Cargando directamente...")
		archivo_actual_path = path

	# 3. Cargar la lista de fuentes y tablas
	_cargar_lista_de_archivos()

func _ready_extra_imagen():
	# Configurar un FileDialog específico para buscar imágenes PNG
	dialog_cargar_img.access = FileDialog.ACCESS_FILESYSTEM
	dialog_cargar_img.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog_cargar_img.filters = PackedStringArray(["*.png ; Imágenes PNG (*.png)"])
	dialog_cargar_img.file_selected.connect(_on_imagen_png_seleccionada)
	add_child(dialog_cargar_img)

func _on_btn_cargar_imagen_pressed():
	if archivo_actual_path == "":
		print("Primero debes cargar un archivo ARM9.")
		return
	if not item_list.is_anything_selected():
		print("Selecciona un bloque de fuentes primero en la lista.")
		return
		
	# Si no habías creado el dialog extra, asegúrate de llamarlo o inicializarlo
	if not dialog_cargar_img.get_parent():
		_ready_extra_imagen()
		
	dialog_cargar_img.popup_centered()

func _on_imagen_png_seleccionada(path_png: String):
	var img_externa = Image.load_from_file(path_png)
	if not img_externa:
		print("Error al cargar la imagen PNG.")
		return
		
	# Verificar que la textura actual del atlas exista en pantalla
	if not texture_rect or not texture_rect.texture:
		print("No hay ningún atlas renderizado en pantalla para reemplazar.")
		return
		
	var atlas_img = texture_rect.texture.get_image()
	if not atlas_img: return
	
	# Opcional: Si seleccionas un glifo específico en una lista de índices o quieres pegar toda la imagen
	# Aquí asumiremos que tu PNG externo es un glifo individual de 16x16 y quieres pegarlo 
	# en la posición del glifo que tengas seleccionado, o bien reemplazar el atlas completo si el PNG es el atlas entero.
	
	if img_externa.get_size() == Vector2i(16, 16):
		# CASO A: El usuario seleccionó un PNG de 16x16 para reemplazar UN GLIFO ESPECÍFICO
		var indices_seleccionados = item_list.get_selected_items()
		if indices_seleccionados.size() == 0:
			print("Selecciona un índice de glifo o usa un atlas completo.")
			return
		# Nota: Si manejas sub-selección de glifos, aquí calcularías su posición grid_x / grid_y.
		print("Reemplazando glifo individual con la imagen externa...")
	else:
		# CASO B: El PNG externo es un atlas completo modificado que reemplaza todo el bloque
		if img_externa.get_size() == atlas_img.get_size():
			texture_rect.texture = ImageTexture.create_from_image(img_externa)
			print("¡Atlas completo reemplazado exitosamente con la imagen externa! Ahora haz clic en Guardar.")
		else:
			print("Las dimensiones de la imagen externa (%s) no coinciden con el atlas actual (%s)." % [img_externa.get_size(), atlas_img.get_size()])

func _on_guardar():
	if archivo_actual_path == "": 
		print("No hay ningún archivo ARM9 cargado.")
		return
		
	if not item_list.is_anything_selected():
		print("Selecciona un bloque de la lista primero.")
		return
		
	var nombre_bloque = item_list.get_item_text(item_list.get_selected_items()[0])
	
	# Desviar el guardado si estamos en la vista de tablas
	if "Table" in nombre_bloque:
		if editor_tablas.visible:
			editor_tablas._on_guardar_presionado()
		else:
			print("Error: La interfaz de tablas no está activa.")
		return
		
	# Lógica para inyección de texturas
	if not texture_rect or not texture_rect.texture:
		print("No hay ninguna textura cargada para guardar.")
		return
		
	var img = texture_rect.texture.get_image()
	if not img:
		print("Error al obtener la imagen de la textura.")
		return
		
	print("Empaquetando imagen dinámica para %s..." % nombre_bloque)
	
	# Empaquetamos los datos según el tipo de bloque (1bpp o 2bpp)
	var datos_empaquetados = parser.empaquetar_fuente_desde_imagen(img, nombre_bloque)
	
	if datos_empaquetados.size() > 0:
		# Escribimos directamente en las direcciones (offsets) del ARM9 descomprimido
		var exito = parser.escribir_bloque(archivo_actual_path, nombre_bloque, datos_empaquetados)
		if exito:
			print("¡Inserción de %s completada con éxito en el ARM9 descomprimido!" % nombre_bloque)


func _cargar_lista_de_archivos():
	item_list.clear()
	for nombre in parser.ARM9_LAYOUT.keys():
		item_list.add_item(nombre)

func _on_item_list_item_selected(index: int):
	var nombre_bloque = item_list.get_item_text(index)
	var datos = parser.cargar_bloque(archivo_actual_path, nombre_bloque)
	
	if "Glyphs" in nombre_bloque:
		editor_tablas.hide() # Ocultamos editor si estamos en glifos
		visor_glifos.show()
		_renderizar_atlas(nombre_bloque, datos)
	# En MainUI.gd, dentro de _on_item_list_item_selected
	elif "Table" in nombre_bloque:
		visor_glifos.hide()
		editor_tablas.show()
		
		# Forzamos la carga y renderizado del atlas de glifos correspondiente en segundo plano
		var nombre_glyphs = nombre_bloque.replace("Table", "Glyphs")
		var datos_glyphs = parser.cargar_bloque(archivo_actual_path, nombre_glyphs)
		_renderizar_atlas(nombre_glyphs, datos_glyphs)
		
		# Ahora obtenemos con seguridad la textura ya generada
		var atlas_actual = texture_rect.texture if texture_rect else null
		editor_tablas.cargar_editor(archivo_actual_path, nombre_bloque, nombre_glyphs, atlas_actual)

func _renderizar_atlas(nombre: String, datos: PackedByteArray):
	var conf = parser.ARM9_LAYOUT[nombre]
	var h = conf["h"]
	var total_glifos = conf["total"]
	var bytes_por_glifo = conf["bytes_per_glyph"]
	
	# --- AISLAMIENTO TOTAL: Si es la fuente 2bpp problemática, usamos su propia función dedicada ---
	if nombre == "Sec_2bpp_Glyphs":
		_renderizar_atlas_sec_2bpp(datos, conf)
		return
	# ------------------------------------------------------------------------------------------
	
	# Código original intacto y funcional para Main y Sec_1bpp
	var endian_mode = conf.get("endian", "little")
	var cols = 64
	var rows = ceil(float(total_glifos) / cols)
	var atlas_img = Image.create(cols * 16, rows * h, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0.1, 0.1, 0.12, 1.0))
	
	for g_idx in range(total_glifos):
		var grid_x = (g_idx % cols) * 16
		var grid_y = floor(float(g_idx) / cols) * h
		
		var byte_idx = g_idx * bytes_por_glifo
		if byte_idx + bytes_por_glifo > datos.size(): continue
		var glifo_bytes = datos.slice(byte_idx, byte_idx + bytes_por_glifo)
		
		for y in range(h):
			var offset_fila = y * 2
			if offset_fila + 1 >= glifo_bytes.size(): break
			
			var fila_u16 = 0
			if endian_mode == "big":
				var b1 = glifo_bytes[offset_fila]
				var b2 = glifo_bytes[offset_fila + 1]
				fila_u16 = (b1 << 8) | b2
			else:
				fila_u16 = glifo_bytes.decode_u16(offset_fila)
			
			for x in range(16):
				var bit_on = (fila_u16 & (1 << (15 - x))) != 0
				if bit_on:
					atlas_img.set_pixel(grid_x + x, grid_y + y, Color(1, 1, 1, 1))

	_mostrar_textura(atlas_img, "Atlas renderizado correctamente para: %s" % nombre)

func _renderizar_atlas_sec_2bpp(datos: PackedByteArray, conf: Dictionary):
	var h_final = 14 # Alto real del carácter ensamblado (16x14)
	var total_letras = conf["total"] # Ahora es 849
	var bytes_per_block = 28 # 28 bytes por mitad de bloque
	var endian_mode = conf.get("endian", "little")
	
	var cols = 64
	var rows = ceil(float(total_letras) / cols)
	var max_w = 16 # Ancho de 16 píxeles
	
	var atlas_img = Image.create(cols * max_w, rows * h_final, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0.1, 0.1, 0.12, 1.0))
	
	for char_idx in range(total_letras):
		var grid_x = (char_idx % cols) * max_w
		var grid_y = floor(float(char_idx) / cols) * h_final
		
		# Unimos las dos mitades verticales (Superior e Inferior de 7x16 cada una)
		for parte in range(2):
			var block_idx = (char_idx * 2) + parte 
			var byte_idx = block_idx * bytes_per_block
			
			if byte_idx + bytes_per_block > datos.size(): break
			var bloque_bytes = datos.slice(byte_idx, byte_idx + bytes_per_block)
			
			var offset_y_base = parte * 7 # 0 para la mitad superior, 7 para la inferior
			
			# Cada bloque tiene 7 filas de alto por 4 bytes de ancho
			for y in range(7):
				var offset_fila = y * 4 
				if offset_fila + 3 >= bloque_bytes.size(): break
				
				# Leemos los 4 bytes de la fila como un único entero de 32 bits (16 píxeles * 2 bits)
				var fila_u32 = 0
				if endian_mode == "big":
					fila_u32 = (bloque_bytes[offset_fila] << 24) | \
							   (bloque_bytes[offset_fila + 1] << 16) | \
							   (bloque_bytes[offset_fila + 2] << 8) | \
							   bloque_bytes[offset_fila + 3]
				else:
					fila_u32 = bloque_bytes.decode_u32(offset_fila)
				
				# Recorremos los 16 píxeles de forma continua
				for x in range(16):
					var shift_val = (15 - x) * 2
					var color_idx = (fila_u32 >> shift_val) & 3
					
					if color_idx > 0:
						var c = Color.WHITE if color_idx == 3 else Color(float(color_idx) / 3.0, float(color_idx) / 3.0, float(color_idx) / 3.0, 1.0)
						atlas_img.set_pixel(grid_x + x, grid_y + offset_y_base + y, c)

	_mostrar_textura(atlas_img, "Atlas Sec_2bpp alineado: Sin desfases de píxeles.")


func _mostrar_textura(atlas_img: Image, mensaje: String):
	if texture_rect:
		var tex = ImageTexture.create_from_image(atlas_img)
		texture_rect.texture = tex
		texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP
		texture_rect.position = Vector2.ZERO
		texture_rect.custom_minimum_size = atlas_img.get_size()
		texture_rect.size = atlas_img.get_size()
		print(mensaje)

func exportar_atlas_png(ruta_destino: String = ""):
	if not texture_rect or not texture_rect.texture: 
		print("No hay ninguna textura cargada para exportar.")
		return
		
	var nombre_archivo = "atlas_actual"
	if item_list and item_list.is_anything_selected():
		nombre_archivo = item_list.get_item_text(item_list.get_selected_items()[0])
	
	if dialog_save:
		# Recuperar la última ruta específica de texturas
		var ultima_ruta_tex = _cargar_ultima_ruta_textura()
		if ultima_ruta_tex != "" and DirAccess.dir_exists_absolute(ultima_ruta_tex):
			dialog_save.current_dir = ultima_ruta_tex
			dialog_save.current_path = ultima_ruta_tex + "/" + nombre_archivo + ".png"
		else:
			dialog_save.current_file = nombre_archivo + ".png"
			
		dialog_save.popup_centered()
	else:
		# Resguardo por si el nodo no estuviera enlazado
		print("Error: El nodo FileDialogGuardar no está asignado.")

func _on_imagen_png_guardar_seleccionada(path_path: String):
	if not texture_rect or not texture_rect.texture: return
	var img = texture_rect.texture.get_image()
	if img:
		img.save_png(path_path)
		# Guardamos la carpeta de esta textura por separado
		_guardar_ultima_ruta_textura(path_path)
		print("¡Atlas exportado exitosamente en: %s!" % path_path)
