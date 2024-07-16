
; The macro order is important to insure everythings work correctly, and
; it also limits was is possible as ?? macros nest and are not reentrant.


; the fasm2 model:
;	include 'dd.inc'
;	include 'align.inc'
;	include 'format.inc'
;	include 'x86-2.inc'
;	use everything
;
;	include '@@.inc'
;	include 'times.inc'
;	include 'fix.inc'

include 'encoding\utf8.inc'
format MS64 COFF
section ".text$t" code executable readable align 64

; https://devblogs.microsoft.com/oldnewthing/20041025-00/?p=37483
extrn __ImageBase ; the linker knows

include 'anchor.g'	; aligned data groups

;------------------------------------------------------------------------------

; remove some features of the fasm2 packaged distribution:
;	- no TCHAR support, use explicit API/struct names
;
; additional features:
;	- shortcut library names to fastcall invocation (invoke not needed)

; don't coerse api names to A/W - must explicitly use API desired
calminstruction api names&
	; TODO : create error macros to notify on use
end calminstruction

; TODO: error if TCHARs are used
struc? TCHAR args:?&
	. du args
end struc
macro TCHAR args:?&
	du args
end macro
sizeof.TCHAR = 2

include 'macro/struct.inc'
include 'fastcall.g'
;include 'macro/com64.inc'	; custom COM macros
;include 'macro/import64.inc'	; managed by linker in COFF objects
;include 'macro/export.inc'	; managed by linker in COFF objects
;include 'macro/resource.inc'	; managed by linker in COFF objects

Struct.CheckAlignment = 1

include 'equates/kernel64.inc'
;include 'equates/user64.inc'
;include 'equates/gdi64.inc'
;include 'equates/comctl64.inc'	; TODO: replace with corrections
;include 'equates/comdlg64.inc'
;include 'equates/shell64.inc'
;include 'equates/wsock32.inc'

;include 'winmore.g'

include 'light-fast.g'

calminstruction ?? line& ; part of anchor, but needs to be here
	match {section:grain} line, line
	jyes datas
	assemble line
	exit
datas:
	arrange line,=COFF=.grain=.section line
	assemble line
	stringify line
end calminstruction
