; Shared scalar nibble tables. Include at top level after lowbase.inc.
; Emit after source code so inclusion does not change the active section.
; Identical public definitions in separate objects fold through EXACT_MATCH.
if ~ definite HEX_TABLES_INC
HEX_TABLES_INC := 1
postpone
	if used hex_upper_digits
		section '.rdata$hex_upper_digits' data readable comdat exactmatch align 16
		public hex_upper_digits
		hex_upper_digits db '0123456789ABCDEF'
	end if
	if used hex_lower_digits
		section '.rdata$hex_lower_digits' data readable comdat exactmatch align 16
		public hex_lower_digits
		hex_lower_digits db '0123456789abcdef'
	end if
end postpone
end if
