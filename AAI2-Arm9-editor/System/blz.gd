class_name BLZ

const BLZ_THRESHOLD = 2
const BLZ_N = 0x1002
const BLZ_F = 0x12

# === COMPROBACIÓN ===
static func esta_comprimido(buffer: PackedByteArray) -> bool:
	var pak_len = buffer.size()
	if pak_len < 4: return false
	var inc_len = buffer.decode_u32(pak_len - 4)
	return inc_len != 0

# === DESCOMPRESIÓN (Decode) ===
static func descomprimir(pak_buffer: PackedByteArray) -> PackedByteArray:
	var pak_len = pak_buffer.size()
	var inc_len = pak_buffer.decode_u32(pak_len - 4)
	
	if inc_len == 0:
		return pak_buffer # No está comprimido
		
	var hdr_len = pak_buffer[pak_len - 5]
	var enc_len = pak_buffer.decode_u32(pak_len - 8) & 0x00FFFFFF
	var dec_len = pak_len - enc_len
	pak_len = enc_len - hdr_len
	var raw_len = dec_len + enc_len + inc_len
	
	var raw_buffer = PackedByteArray()
	raw_buffer.resize(raw_len)
	
	# Copiar parte no comprimida
	for i in range(dec_len):
		raw_buffer[i] = pak_buffer[i]
		
	# Invertir el bloque codificado
	var comp_part = pak_buffer.slice(dec_len, dec_len + pak_len)
	comp_part.reverse()
	
	var pak_idx = 0
	var raw_idx = dec_len
	var mask = 0
	var flags = 0
	
	while raw_idx < raw_len:
		if mask == 0:
			if pak_idx >= comp_part.size(): break
			flags = comp_part[pak_idx]
			pak_idx += 1
			mask = 0x80
		
		if (flags & mask) == 0:
			if pak_idx >= comp_part.size(): break
			raw_buffer[raw_idx] = comp_part[pak_idx]
			raw_idx += 1
			pak_idx += 1
		else:
			if pak_idx + 1 >= comp_part.size(): break
			var pos = (comp_part[pak_idx] << 8) | comp_part[pak_idx + 1]
			pak_idx += 2
			var length = (pos >> 12) + BLZ_THRESHOLD + 1
			pos = (pos & 0xFFF) + 3
			
			for i in range(length):
				if raw_idx >= raw_len: break
				raw_buffer[raw_idx] = raw_buffer[raw_idx - pos]
				raw_idx += 1
				
		mask >>= 1
		
	# Invertir bloque decodificado
	var decoded_part = raw_buffer.slice(dec_len, raw_idx)
	decoded_part.reverse()
	for i in range(decoded_part.size()):
		raw_buffer[dec_len + i] = decoded_part[i]
		
	raw_buffer.resize(raw_idx)
	return raw_buffer

# === CÁLCULO CRC16 PARA EL ARM9 ===
static func _blz_crc16(buffer: PackedByteArray, offset: int, length: int) -> int:
	var crc = 0xFFFF
	for i in range(length):
		crc ^= buffer[offset + i]
		for j in range(8):
			if (crc & 1) != 0:
				crc = (crc >> 1) ^ 0xA001
			else:
				crc >>= 1
	return crc

# === COMPRESIÓN (Encode) ===
static func comprimir_arm9(raw_buffer: PackedByteArray) -> PackedByteArray:
	var raw_len = raw_buffer.size()
	var raw_new = raw_len
	
	# Verificación e inyección de firma ARM9 (Secure Area ID y CRC)
	if raw_len >= 0x4000:
		if raw_buffer.decode_u32(0x0) == 0xE7FFDEFF and raw_buffer.decode_u32(0x4) == 0xE7FFDEFF:
			var crc = _blz_crc16(raw_buffer, 0x10, 0x07F0)
			if raw_buffer.decode_u16(0x0E) != crc:
				raw_buffer.encode_u16(0x0E, crc)
			raw_new -= 0x4000
			
	raw_buffer.reverse()
	
	var pak_buffer = PackedByteArray()
	# Pre-asignar tamaño máximo teórico para evitar redimensiones constantes
	pak_buffer.resize(raw_len + (raw_len / 8) + 11) 
	
	var pak_idx = 0
	var raw_idx = 0
	var flg_idx = -1
	var mask = 0
	
	var pak_tmp = 0
	var raw_tmp = raw_len
	
	while raw_idx < raw_new:
		if mask == 0:
			flg_idx = pak_idx
			pak_buffer[pak_idx] = 0
			pak_idx += 1
			mask = 0x80
			
		var len_best = BLZ_THRESHOLD
		var pos_best = 0
		var max_pos = mini(0x400, raw_idx)
		
		# Función SEARCH emulada
		for pos in range(3, max_pos + 1):
			var current_len = 0
			while current_len < BLZ_F:
				if raw_idx + current_len >= raw_new: break
				if current_len >= pos: break
				if raw_buffer[raw_idx + current_len] != raw_buffer[raw_idx + current_len - pos]: break
				current_len += 1
				
			if current_len > len_best:
				pos_best = pos
				len_best = current_len
				if len_best == BLZ_F: break
				
		pak_buffer[flg_idx] <<= 1
		
		if len_best > BLZ_THRESHOLD:
			pak_buffer[flg_idx] |= 1
			pak_buffer[pak_idx] = ((len_best - (BLZ_THRESHOLD + 1)) << 4) | ((pos_best - 3) >> 8)
			pak_buffer[pak_idx + 1] = (pos_best - 3) & 0xFF
			pak_idx += 2
			raw_idx += len_best
		else:
			pak_buffer[pak_idx] = raw_buffer[raw_idx]
			pak_idx += 1
			raw_idx += 1
			
		if ((pak_idx + raw_len - raw_idx) + 3 & -4) < (pak_tmp + raw_tmp):
			pak_tmp = pak_idx
			raw_tmp = raw_len - raw_idx
			
	while mask != 0 and mask != 1:
		mask >>= 1
		pak_buffer[flg_idx] <<= 1
		
	var pak_len = pak_idx
	raw_buffer.reverse() # Restaurar raw original
	
	var comp_slice = pak_buffer.slice(0, pak_len)
	comp_slice.reverse()
	
	var final_pak = PackedByteArray()
	var enc_len = pak_tmp
	var inc_len = raw_len - pak_tmp - raw_tmp
	var hdr_len = 8
	
	# Empaquetar todo (bloque crudo + bloque comprimido + cabecera BLZ)
	final_pak.append_array(raw_buffer.slice(0, raw_tmp))
	final_pak.append_array(comp_slice.slice(pak_len - pak_tmp, pak_len))
	
	while final_pak.size() % 4 != 0:
		final_pak.append(0xFF)
		hdr_len += 1
		
	var enc_hdr = enc_len + hdr_len
	final_pak.append(enc_hdr & 0xFF)
	final_pak.append((enc_hdr >> 8) & 0xFF)
	final_pak.append((enc_hdr >> 16) & 0xFF)
	final_pak.append(hdr_len)
	
	var inc_hdr = inc_len - hdr_len
	final_pak.append(inc_hdr & 0xFF)
	final_pak.append((inc_hdr >> 8) & 0xFF)
	final_pak.append((inc_hdr >> 16) & 0xFF)
	final_pak.append((inc_hdr >> 24) & 0xFF)
	
	return final_pak
