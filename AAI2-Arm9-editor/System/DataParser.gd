# DataParser.gd
class_name DataParser

const ARM9_LAYOUT = {
	"Main_Font_Glyphs": {"offset": 0x35FCC, "size": 64384, "w": 16, "h": 16, "bpp": 1, "total": 2012, "bytes_per_glyph": 32, "tabla": "Main_Font_Table", "endian": "little"},
	"Main_Font_Table":  {"offset": 0x45B4C, "size": 16096},
	
	# CORRECCIÓN: 849 caracteres reales. Cada uno mide 56 bytes (2 bloques de 28 bytes ensamblados).
	"Sec_2bpp_Glyphs": {"offset": 0x49A2C, "size": 47544, "w": 16, "h": 14, "bpp": 2, "total": 849, "bytes_per_glyph": 56, "tabla": "Sec_2bpp_Table", "endian": "little"},
	"Sec_2bpp_Table":   {"offset": 0x553E4, "size": 6792},
	
	"Sec_1bpp_Glyphs":  {"offset": 0x56E6C, "size": 22960, "w": 16, "h": 14, "bpp": 1, "total": 820, "bytes_per_glyph": 28, "tabla": "Sec_1bpp_Table", "endian": "little"},
	"Sec_1bpp_Table":   {"offset": 0x5C81C, "size": 6560}
}

func cargar_bloque(path: String, nombre: String) -> PackedByteArray:
	if not ARM9_LAYOUT.has(nombre): return PackedByteArray()
	var conf = ARM9_LAYOUT[nombre]
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return PackedByteArray()
	
	file.seek(conf["offset"])
	var data = file.get_buffer(conf["size"])
	file.close()
	return data

func escribir_bloque(path: String, nombre: String, datos_nuevos: PackedByteArray) -> bool:
	if not ARM9_LAYOUT.has(nombre): return false
	var conf = ARM9_LAYOUT[nombre]
	
	# Abrimos el archivo en modo lectura/escritura sin truncar (para no borrar el resto de la ROM)
	var file = FileAccess.open(path, FileAccess.READ_WRITE)
	if not file: 
		print("Error: No se pudo abrir el archivo para escritura.")
		return false
	
	file.seek(conf["offset"])
	
	# Verificamos que no nos pasemos del tamaño definido en el layout para no corromper bloques vecinos
	if datos_nuevos.size() > conf["size"]:
		print("Error: Los datos superan el tamaño reservado para este bloque.")
		file.close()
		return false
		
	file.store_buffer(datos_nuevos)
	file.close()
	print("Bloque %s escrito exitosamente en el ARM9." % nombre)
	return true

func empaquetar_fuente_desde_imagen(img: Image, nombre_bloque: String) -> PackedByteArray:
	var conf = ARM9_LAYOUT[nombre_bloque]
	
	# --- AISLAMIENTO TOTAL: Si es la fuente 2bpp, usamos su empaquetador por mitades de 16x7 ---
	if nombre_bloque == "Sec_2bpp_Glyphs":
		return _empaquetar_fuente_sec_2bpp(img, conf)
	# -----------------------------------------------------------------------------------------
	
	var h = conf["h"]
	var total_glifos = conf["total"]
	var bytes_per_glyph = conf["bytes_per_glyph"]
	var endian_mode = conf.get("endian", "little")
	var cols = 64
	
	var bloque_bytes = PackedByteArray()
	bloque_bytes.resize(conf["size"])
	
	for g_idx in range(total_glifos):
		var grid_x = (g_idx % cols) * 16
		var grid_y = floor(float(g_idx) / cols) * h
		
		var glifo_bytes = PackedByteArray()
		glifo_bytes.resize(bytes_per_glyph)
		
		for y in range(h):
			var fila_u16 = 0
			for x in range(16):
				var px_x = grid_x + x
				var px_y = grid_y + y
				if px_x < img.get_width() and px_y < img.get_height():
					var col = img.get_pixel(px_x, px_y)
					if col.r > 0.5 or col.get_luminance() > 0.5:
						fila_u16 |= (1 << (15 - x))
			
			if endian_mode == "big":
				glifo_bytes[y * 2] = (fila_u16 >> 8) & 0xFF
				glifo_bytes[y * 2 + 1] = fila_u16 & 0xFF
			else:
				glifo_bytes.encode_u16(y * 2, fila_u16)
		
		var dest_idx = g_idx * bytes_per_glyph
		for b in range(bytes_per_glyph):
			bloque_bytes[dest_idx + b] = glifo_bytes[b]
			
	return bloque_bytes

# --- NUEVA FUNCIÓN PARA EMPAQUETAR CORRECTAMENTE SEC_2BPP ---
# --- NUEVA FUNCIÓN PARA EMPAQUETAR CORRECTAMENTE SEC_2BPP ---
func _empaquetar_fuente_sec_2bpp(img: Image, conf: Dictionary) -> PackedByteArray:
	var h_final = 14
	var total_letras = conf["total"] # Ahora es 849
	var bytes_per_glyph = conf["bytes_per_glyph"] # Ahora es 56
	var bytes_per_block = 28 # Medio carácter
	var endian_mode = conf.get("endian", "little")
	var cols = 64
	
	var bloque_bytes = PackedByteArray()
	bloque_bytes.resize(conf["size"])
	
	for char_idx in range(total_letras):
		var grid_x = (char_idx % cols) * 16
		var grid_y = floor(float(char_idx) / cols) * h_final
		
		# Cada letra se divide en 2 partes verticales (superior e inferior de 7 filas)
		for parte in range(2):
			var block_idx = (char_idx * 2) + parte
			var byte_idx = block_idx * bytes_per_block
			
			var bloque_glifo_bytes = PackedByteArray()
			bloque_glifo_bytes.resize(bytes_per_block)
			
			var offset_y_base = parte * 7
			
			for y in range(7):
				var px_y_global = grid_y + offset_y_base + y
				var fila_u32 = 0
				
				for x in range(16):
					var px_x = grid_x + x
					if px_x < img.get_width() and px_y_global < img.get_height():
						var col = img.get_pixel(px_x, px_y_global)
						
						# Mapeamos los niveles de grises a los 4 índices de 2bpp (0 a 3)
						var color_idx = 0
						if col.r > 0.85: color_idx = 3       # Blanco
						elif col.r > 0.5: color_idx = 2     # Gris medio
						elif col.r > 0.2: color_idx = 1     # Gris oscuro
						else: color_idx = 0                 # Transparente / Fondo
						
						fila_u32 |= (color_idx & 3) << ((15 - x) * 2)
				
				var offset_fila = y * 4
				if endian_mode == "big":
					bloque_glifo_bytes[offset_fila]     = (fila_u32 >> 24) & 0xFF
					bloque_glifo_bytes[offset_fila + 1] = (fila_u32 >> 16) & 0xFF
					bloque_glifo_bytes[offset_fila + 2] = (fila_u32 >> 8) & 0xFF
					bloque_glifo_bytes[offset_fila + 3] = fila_u32 & 0xFF
				else:
					bloque_glifo_bytes.encode_u32(offset_fila, fila_u32)
			
			for b in range(bytes_per_block):
				bloque_bytes[byte_idx + b] = bloque_glifo_bytes[b]
				
	return bloque_bytes

# Devuelve una lista de diccionarios: [{char: "A", index: 0, width: 16}, ...]
func obtener_datos_tabla(path: String, nombre_tabla: String) -> Array:
	var conf = ARM9_LAYOUT[nombre_tabla]
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return []
	
	file.seek(conf["offset"])
	var lista_caracteres = []
	var total_entradas = conf["size"] / 8
	
	for i in range(total_entradas):
		var cp = file.get_16()  # Código UTF-16
		var w = file.get_16()   # Ancho
		var ptr = file.get_32() # Índice físico del glifo en la textura
		
		var char_repr = char(cp) if cp > 32 else "???"
		lista_caracteres.append({
			"char": char_repr, 
			"index": i, 
			"width": w, 
			"glyph_index": ptr
		})
		
	file.close()
	return lista_caracteres

func actualizar_ancho_glifo(path: String, tabla_nombre: String, indice: int, nuevo_ancho: int) -> bool:
	var conf_tabla = ARM9_LAYOUT[tabla_nombre]
	var file = FileAccess.open(path, FileAccess.READ_WRITE)
	if not file: return false
	
	# Cada estructura en la tabla mide 8 bytes
	var offset_estructura = conf_tabla["offset"] + (indice * 8)
	
	# El ancho se encuentra en el offset + 2 de cada estructura (2 bytes)
	file.seek(offset_estructura + 2)
	file.store_16(nuevo_ancho)
	
	file.close()
	print("Ancho del glifo en el índice %d actualizado a %d píxeles." % [indice, nuevo_ancho])
	return true
