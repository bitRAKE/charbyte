
; add sections here as needed:

iterate ANCHOR, const,data,bss
iterate V,1,2,4,8,16,32,64
	calminstruction COFF.V.ANCHOR? line&
		local X
		match ,line
		jyes A		; empty triggers output
		take X,line	; consume
		exit
		; reverse order
	A:	take line,X
		jyes A
		; output
	B:	assemble line	; process
		take , line	; remove TOS
		take line,line	; more?
		jyes B
	end calminstruction
end iterate
end iterate

postpone
align?.count = 1 ; reset assumes

iterate <ANCHOR,HEADER>,\	; output collection macros
	CONST,	<section '.const$t'	data	readable align 64>,\
	DATA,	<section '.data$t'	data	readable writeable align 64>,\
	BSS,	<section '.bss$t'	udata	readable writeable align 64>

	if COFF.ANCHOR.BYTES > 0
		HEADER
	end if
	COFF.ANCHOR:
	iterate V,64,32,16,8,4,2,1
		COFF.V.ANCHOR
		assert ($-COFF.ANCHOR) and (V-1) = 0 ; enforce alignment
	end iterate
	COFF.ANCHOR.BYTES := $ - COFF.ANCHOR

	if definite COFF.OBJECT_METRICS
		repeat 1,B:COFF.ANCHOR.BYTES
			display 10,9,`ANCHOR,' bytes ',`B
		end repeat
	end if
end iterate
end postpone
;------------------------------------------------------- data section gathering
macro BLOCK anchor*
	calminstruction ? line&
		local prefix,any
		initsym prefix, anchor
		match =END =BLOCK, line
		jno pre
		match =COFF=.line=.any,prefix
		jno xa
		arrange line, prefix =align line
		assemble line
	xa:	arrange line, =purge ?
		jump ok
	pre:	arrange line, prefix line
	ok:	assemble line
	end calminstruction
end macro
