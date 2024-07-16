
;------------------------------------------------------------------------------
; ! ALL undefined instructions are ASSUMED to be external fastcall functions !
;------------------------------------------------------------------------------

namespace COFF
	define FUNCTIONS FUNCTIONS
end namespace
calminstruction ?? line&
	local var, function, parameters
	arrange parameters,
	; this catch all can easily masks errors
	match function parameters?, line
	jno more ; never happens?
	transform function, COFF.FUNCTIONS
	jyes present
	arrange var, =COFF.=FUNCTIONS.function
	publish var, function
	publish var, function

;	stringify line ; debug
;	display line
;	display 10

	transform var
	take COFF..functions, var
present:
	arrange line, =fastcall function,parameters
	match , parameters
	jno more
	arrange line, =fastcall function
more:	assemble line
end calminstruction

;-------------------------------------------------------------- light proc-like

calminstruction ?? &line&
	local arguments
	arrange arguments,
	match :named: arguments?,line
	jyes fn
	assemble line
	exit

fn:	local cache,var
	take .frame,.frame ; has a value?
	jyes skip

	take cache,cache
	jno skip

	arrange var,cache.=frame :== =fastcall?=.=frame
	assemble var

	take ,cache
	take cache,cache
	jno skip
	err 'cache is only allowed a depth of one'
skip:
	arrange var,named:
	assemble var
	; cache name for future use
	take cache,named
	; reset stack depth counter
	compute fastcall?.frame, 0

	match ,arguments
	jyes done

; TODO: add function features? Presently MUST be complete line
; just a terse shadow-space labeling w/ size checking?
; a half-way solution breaks in many ways - loosing flexiblity
	err 'not implemented'
done:
end calminstruction
;--------------------------------------------------------------------- finalize
postpone
	macro onetime
		local dummy
		:dummy: ; light proc-like closure
		purge onetime
	end macro
	onetime

	irpv fun, COFF..functions ; catch-all API's done
		; TODO: skip already defined EXTRN?
		extrn `fun as fun: QWORD
	end irpv
end postpone
