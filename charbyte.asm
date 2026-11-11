; charbyte: display a table of the byte-sized characters of a code page.
; From https://github.com/bitRAKE/charbyte, on the PSDK projection.
;
;	charbyte [help|list] [legend] [locale|codepage] <value>
;
; Obviously, this tool is not meant to support non-byte code pages or locales.

include 'lowbase.inc'
include 'psdk\um\processenv.inc'	; GetStdHandle, GetCommandLineW
include 'psdk\um\shellapi.inc'		; CommandLineToArgvW
include 'psdk\um\WinBase.inc'		; lstrcmpiW, lstrlenW, STD_OUTPUT_HANDLE
include 'psdk\um\winnt.inc'		; LOCALE_USER_DEFAULT, LOCALE_NAME_MAX_LENGTH
include 'psdk\um\WinNls.inc'		; locales, code pages, CPINFOEXW, C1_*, C3_*
include 'psdk\um\stringapiset.inc'	; MultiByteToWideChar, GetStringTypeW
include 'psdk\um\consoleapi.inc'	; WriteConsoleW
include 'psdk\um\processthreadsapi.inc'	; ExitProcess
include 'psdk\um\combaseapi.inc'	; CoInitializeEx, CoCreateInstance
include 'psdk\um\objbase.inc'		; COINIT_APARTMENTTHREADED
include 'psdk\shared\WTypesbase.inc'	; CLSCTX_INPROC_SERVER
include 'psdk\um\oleauto.inc'		; SysAllocString, SysFreeString
include 'psdk\um\MLang.inc'		; IMultiLanguage2: code pages by name
include 'psdk\shared\minwindef.inc'	; TRUE
include 'wtoi64.asm'			; the other object's interface
include 'hex_tables.inc'

program CONSOLE,Main
response 'kernel32.lib','shell32.lib','ole32.lib','oleaut32.lib','wtoi64.obj'

; Configure ANSI Colors:
BRDR	equ 27,'[90m'	; border
KHEX	equ 27,'[32m'	; axis key
KHAR	equ 27,'[m'	; character: letter
KDIG	equ 27,'[96m'	;	" digit
KPUN	equ 27,'[93m'	;	" punctuation
KSYM	equ 27,'[94m'	;	" other symbol
KSPC	equ 27,'[44m'	;	" space (on a background, so it shows)
KMRK	equ 27,'[92m'	;	" combining mark
KONT	equ 27,'[35m'	;	" control
KLEAD	equ 27,'[36m'	;	" lead byte of a double-byte code page
KERR	equ 27,'[91m'	;	" invalid

FLAG_CODEPAGE	:= 0
FLAG_LOCALE	:= 1
FLAG_LIST	:= 2
FLAG_LEGEND	:= 3

; `$ text`: one WriteConsoleW of the text (anything du accepts, continued
; with \ across lines), pooled by GLOBWSTR
calminstruction ?? line&
	match =$ text, line
	jno pass
	arrange line, =conout text
pass:	assemble line
end calminstruction

macro conout text&
	local string
	string GLOBWSTR text
	WriteConsoleW [hOutput], & string, sizeof string, 0, 0
end macro

BSS.8 hOutput dq ?	; for `$` in every routine

macro jcc_error JCC*,text* ; reduce interference from error checking
	local message
	message GLOBWSTR KERR,text
	mov edx, message		; flags survive: MOV only
	mov r8d, sizeof message
	JCC error
end macro

proc Main ; one constant frame: locals and the largest call, sized by endp
	locals
		lpCmdLine	dq ?
		argv		dq ?
		argn		dd ?
		result		dd ?
		ctype		dw ?
		wide		rw 4
		char		db ?
	endl
	mov [result], 1

	BLOCK DATA.4 ; default settings:
		locale		dd LOCALE_USER_DEFAULT ; LCID
		codepage	dd ?
		defaultcp	dd ?
		flags		dd 0
	END BLOCK

	GetStdHandle STD_OUTPUT_HANDLE
	mov [hOutput], rax

	; the default: the user locale's OEM code page (437 for en-US), which a
	; UTF-8 system code page (CP_OEMCP = 65001) leaves as it is
	GetLocaleInfoEx LOCALE_NAME_USER_DEFAULT, LOCALE_IDEFAULTCODEPAGE or LOCALE_RETURN_NUMBER, & defaultcp, 2
	mov eax, [defaultcp]
	mov [codepage], eax

	GetCommandLineW
	mov [lpCmdLine], rax
	test rax, rax
	jz display_usage
	xchg rcx, rax
	CommandLineToArgvW rcx, & argn
	test rax, rax
	jz display_usage
	mov [argv], rax
	xchg rsi, rax
	lodsq ; skip program name
	test rax, rax
	jz display_usage
process_args:
	cmp qword [rsi], 0
	jz args_processed

	iterate <command,route>,\
		list,		mode_list,\
		legend,		mode_legend,\
		locale,		mode_locale,\
		help,		display_usage,\
		codepage,	mode_codepage

		lstrcmpiW [rsi], <W,`command>
		test eax, eax
		jz route
	end iterate

	mov rdi, [rsi]
	call wtoi64_RDI
	jnz arg_number
	test rax, rax
	jnz display_usage ; too many digits
	jmp arg_string ; assume value is a string

bad_arg:
	stc
skip_arg:
	lodsq
	jc display_usage ; argument unknown or possible error condition
	jmp process_args

mode_list:
	bts [flags], FLAG_LIST
	jmp skip_arg
mode_legend:
	bts [flags], FLAG_LEGEND
	jmp skip_arg
mode_codepage:
	bts [flags], FLAG_CODEPAGE
	jmp skip_arg
mode_locale:
	bts [flags], FLAG_LOCALE
	jmp skip_arg

arg_number: ; support 32-bit [un]signed range
	cmp word [rdi], 0
	jnz display_usage ; invalid form, numbers need to be complete arg
	movsxd rdx, eax
	mov ecx, eax
	cmp rdx, rax
	jz @F
	cmp rcx, rax
	jnz bad_arg
@@:
	assert FLAG_CODEPAGE=0 ; needed for default routing
	mov ecx, [flags]
	and ecx, 1 shl FLAG_CODEPAGE or 1 shl FLAG_LOCALE ; flags are bit numbers
	cmp ecx, 1 shl FLAG_LOCALE
	jc store_codepage
	jnz display_usage ; ambiguous mode
store_locale:
	mov [locale], eax
	lodsq
	jmp process_args
store_codepage:
	mov [codepage], eax
	lodsq
	jmp process_args

arg_string:
	assert FLAG_CODEPAGE=0 ; needed for default routing
	mov ecx, [flags]
	and ecx, 1 shl FLAG_CODEPAGE or 1 shl FLAG_LOCALE ; flags are bit numbers
	cmp ecx, 1 shl FLAG_LOCALE
	jc string_codepage
	jnz display_usage ; ambiguous mode
string_locale:
	push qword [rsi]
	pop [lpNameToResolve]
	jmp skip_arg

string_codepage:
	iterate abstract, CP_ACP,CP_OEMCP,CP_MACCP,CP_THREAD_ACP,\
	\; these don't really make sense (as they aren't byte encodings):
		CP_UTF7,CP_UTF8

		lstrcmpiW [rsi], <W,`abstract>
		test eax, eax
		jnz CP_.%
		mov [codepage], abstract
		jmp skip_arg
	CP_.%:
	end iterate
	; a name for MLang to resolve
	push qword [rsi]
	pop [lpCodePage]
	jmp skip_arg



args_processed:
	bt [flags], FLAG_LIST
	jc list_codepages
	test [flags], 1 shl FLAG_LOCALE
	jz basis_codepage
	cmp [lpNameToResolve], 0
	jz basis_locale ; use numeric locale

	BLOCK BSS.8
		lpCodePage	dq ?
		lpNameToResolve	dq ?
	END BLOCK
	BSS.2 LocaleName rw LOCALE_NAME_MAX_LENGTH

	ResolveLocaleName [lpNameToResolve], & LocaleName, LOCALE_NAME_MAX_LENGTH
	cmp eax, 1 ; characters, the terminator included: an empty name is no match
	jcc_error jbe, "Unable to resolve locale."
	LocaleNameToLCID & LocaleName, LOCALE_ALLOW_NEUTRAL_NAMES
	test eax, eax
	jcc_error jz, "LCID does not exist for locale."
	mov [locale], eax

basis_locale: ; the locale names its ANSI code page
	LCIDToLocaleName [locale], & LocaleName, LOCALE_NAME_MAX_LENGTH, 0
	test eax, eax
	jcc_error jz, "Invalid locale."
	; LOCALE_RETURN_NUMBER: a DWORD, in a buffer counted in WCHARs
	GetLocaleInfoEx & LocaleName, LOCALE_IDEFAULTANSICODEPAGE or LOCALE_RETURN_NUMBER, & codepage, 2
	test eax, eax
	jcc_error jz, "No code page for locale."
	cmp [codepage], CP_ACP
	jcc_error jz, "Locale is Unicode-only: no byte code page."

$	10,27,'[93m',\
	'   Locale:',9
	lstrlenW & LocaleName
	xchg r8d, eax
	WriteConsoleW [hOutput], & LocaleName, r8d, 0, 0
	jmp have_codepage

basis_codepage:
	cmp [lpCodePage], 0
	jz have_codepage ; use numeric codepage

	; a code page by name: MLang knows the charset names (windows-1252,
	; koi8-r, ibm437, ...) and the encoding each one is
	BSS.8 mlang.slot dq ?
	virtual at mlang.slot ; a typed pointer over anchored storage
		mlang IMultiLanguage2
	end virtual
	BSS.4 charset MIMECSETINFO

	CoInitializeEx 0, COINIT_APARTMENTTHREADED
	CoCreateInstance & CLSID_CMultiLanguage, 0, CLSCTX_INPROC_SERVER, & IID_IMultiLanguage2, & mlang
	test eax, eax
	jcc_error js, "MLang is not available."
	SysAllocString [lpCodePage] ; GetCharsetInfo takes a BSTR
	xchg rdi, rax
	mlang->GetCharsetInfo rdi, & charset
	xchg ebx, eax
	SysFreeString rdi
	mlang->Release
	test ebx, ebx
	jcc_error js, "Unknown code page name."
	mov eax, [charset.uiInternetEncoding]
	mov [codepage], eax

have_codepage:
	BSS.4 cpiw CPINFOEXW
	GetCPInfoExW [codepage], 0, & cpiw ; translate identifiers to code page number
	test eax, eax ; BOOL
	jcc_error jz, "Invalid code page."
	cmp [cpiw.MaxCharSize], 1
	jz SBCS ; single-byte character set

$	10,27,'[93m',\
	'Warning: this tool is designed for use with single-byte character sets.',10

	; a double-byte code page: its lead bytes come in [first,last] pairs,
	; ended by 0,0
	BSS.64 leadMap rb 256
	mov esi, cpiw.LeadByte
lead_ranges:
	movzx eax, byte [rsi]
	movzx ecx, byte [rsi+1]
	mov edx, eax
	or edx, ecx
	jz SBCS
lead_fill:
	mov byte [leadMap+rax], 1
	inc eax
	cmp eax, ecx
	jbe lead_fill
	add esi, 2
	cmp esi, cpiw.LeadByte + MAX_LEADBYTES
	jb lead_ranges

SBCS:
; partial support for multibyte code pages?
	mov ecx, [cpiw.CodePage]
	mov edx, MB_ERR_INVALID_CHARS or MB_USEGLYPHCHARS ; desired flags

	xor eax, eax ; the following code pages only support dwFlags of zero:
	iterate cp, 42,<50220,50222>,50225,50227,50229,<57002,57011>,65000
		match low_cp =, high_cp,cp
			cmp ecx, low_cp
			jc range.%
			cmp ecx, high_cp+1
			cmovc edx, eax
		range.%:
		else
			cmp ecx, cp
			cmovz edx, eax
		end match
	end iterate

	mov eax, MB_ERR_INVALID_CHARS ; only supported dwFlags
	iterate cp, 54936,65001
		cmp ecx, cp
		cmovz edx, eax
	end iterate
	BSS.4 dwFlags dd ?
	mov [dwFlags], edx

$	10,27,'[93m',\
	'Code Page:',9
	lstrlenW & cpiw.CodePageName
	xchg r8d, eax
	WriteConsoleW [hOutput], & cpiw.CodePageName, r8d, 0, 0

$	10,10,KHEX,\
	"     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F     ",10,BRDR,\
	"   ╔═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╗   ",10

	xor ebx, ebx
table_outer:
	mov eax, ebx
	shr eax, 4
	mov al, [hex_upper_digits + rax]
	mov [lead_in.index], ax
	mov [lead_out.index], ax
	BLOCK DATA.2 ; row lead-in, its index patched above
		lead_in		du ' ',KHEX
		lead_in.index	du 'X',BRDR,' ║ ',KHAR
		lead_in.end:
	END BLOCK
	lead_in.chars := (lead_in.end - lead_in) shr 1
	WriteConsoleW [hOutput], & lead_in, lead_in.chars, 0, 0

table_inner:
	cmp byte [leadMap + rbx], 0
	jnz char_lead
char_output:
	mov [char], bl
	MultiByteToWideChar [cpiw.CodePage], [dwFlags], & char, 1, & wide, 4
	cmp eax, 1
	jnz char_unknown

; controls have no glyph of their own:
	movzx eax, word [wide]
	cmp eax, ' '
	jc char_c0
	cmp eax, 0x7F
	jz char_del
	sub eax, 0x80
	cmp eax, 0x9F+1 - 0x80 ; 0x0080-0x009F, C1 control block
	jc char_c1

; colored by class
	GetStringTypeW CT_CTYPE1, & wide, 1, & ctype
	movzx eax, [ctype]
	test eax, C1_CNTRL ; beyond C0/C1: format characters (LRM, soft hyphen)
	jnz char_format
	test eax, C1_DIGIT
	jnz kind_digit
	test eax, C1_ALPHA
	jnz kind_letter
	test eax, C1_PUNCT
	jnz kind_punct
	test eax, C1_SPACE or C1_BLANK
	jnz kind_space

	; neither: a symbol, or a combining mark (shown on a dotted circle,
	; keeping its cell)
	GetStringTypeW CT_CTYPE3, & wide, 1, & ctype
	test [ctype], C3_NONSPACING
	jnz kind_mark
	$	KSYM
	jmp glyph
kind_mark:
	$	KMRK,'◌'
	jmp glyph
kind_digit:
	$	KDIG
	jmp glyph
kind_punct:
	$	KPUN
	jmp glyph
kind_space:
	$	KSPC
	jmp glyph
kind_letter:
	$	KHAR
glyph:
	WriteConsoleW [hOutput], & wide, 1, 0, 0
	jmp tween

char_c0: ; U+0000-001F, U+007F: their Control Pictures, U+2400-2421
	add eax, 0x2400
	jmp control_picture
char_del:
	mov eax, 0x2421
control_picture:
	mov [wide], ax
	$	KONT
	WriteConsoleW [hOutput], & wide, 1, 0, 0
	jmp tween

char_c1: ; U+0080-009F have no pictures; the grid is the number
	$	KONT,'▫'
	jmp tween

char_format: ; zero width: written, it would take no cell
	$	KONT,'▪'
	jmp tween

char_lead:
	$	KLEAD,'◇'
	jmp tween

char_unknown:
	$	KERR,'�'

tween:
	$	KHAR,BRDR,' │ ',KHAR
	inc ebx
	test ebx, 0x0F
	jnz table_inner

	BLOCK DATA.2 ; row lead-out
		lead_out	du 8,8,8,BRDR,' ║ ',KHEX
		lead_out.index	du 'X ',10
		lead_out.end:
	END BLOCK
	lead_out.chars := (lead_out.end - lead_out) shr 1
	WriteConsoleW [hOutput], & lead_out, lead_out.chars, 0, 0

	test bl, bl
	jz table_footer
	cmp bl, 0x80
	jz table_split
$	BRDR,\
	"   ╟───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───╢   ",10
	jmp table_outer

table_split:
$	BRDR,\
	"   ╠═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╣   ",10
	jmp table_outer

table_footer:
$	BRDR,\
	"   ╚═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╝   ",10,KHEX,\
	"     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F     ",10,KHAR

	bt [flags], FLAG_LEGEND
	jnc legend_done
$	10,\
	'   ',KHAR,'A letter     ',KPUN,'!',KHAR,' punctuation  ',\
	KDIG,'0',KHAR,' digit    ',KSYM,'☺',KHAR,' symbol    ',KSPC,' ',KHAR,' space',10,\
	'   ',KONT,'␀',KHAR,' control    ',KONT,'▫',KHAR,' C1 control   ',\
	KONT,'▪',KHAR,' format (zero width)',10,\
	'   ',KLEAD,'◇',KHAR,' lead byte  ',KERR,'�',KHAR,' not mapped   ',\
	KMRK,'◌',KHAR,' combining mark',10
legend_done:
	mov [result], 0
	jmp done

list_codepages:
$	10,27,'[93m','Installed single-byte code pages:',KHAR
	EnumSystemCodePagesW & ListCodePage, CP_INSTALLED
	mov [result], 0
	jmp done

error:	; rdx: the message, r8d: its characters
	WriteConsoleW [hOutput], rdx, r8d, 0, 0

display_usage:
$	10,27,'[97m',\
	'Byte Character Table Utility version 0.2',10,10,27,'[32m',\
	'    Usage:',27,'[m',' charbyte [help|list] [legend] [locale|codepage] <value>',10,\
	'	list: the installed single-byte code pages.',10,\
	'	legend: follow table with what the cell colors and marks mean.',10,\
	'	the default mode is [codepage] (i.e. optional)',10,\
	'	the default codepage is the user locale''s OEM code page,',10,9,9
	GetCPInfoExW [defaultcp], 0, & cpiw
	lstrlenW & cpiw.CodePageName
	xchg r8d, eax
	WriteConsoleW [hOutput], & cpiw.CodePageName, r8d, 0, 0
$	10,\
	'	a locale selects its ANSI code page',10,\
	'	<value> can be a number, name or string',10

done:
	ExitProcess [result]
	jmp $
endp

; CODEPAGE_ENUMPROCW: called with each installed code page, as a decimal
; string; lists the single-byte ones, by name
proc ListCodePage uses rdi, lpCodePageString
	locals
		info CPINFOEXW
	endl
	mov rdi, rcx
	call wtoi64_RDI
	jz next
	GetCPInfoExW eax, 0, & info
	xchg ecx, eax ; BOOL
	jrcxz next
	cmp [info.MaxCharSize], 1
	jnz next
$	10,9
	lstrlenW & info.CodePageName
	xchg r8d, eax
	WriteConsoleW [hOutput], & info.CodePageName, r8d, 0, 0
next:	mov eax, TRUE ; continue the enumeration
	ret
endp

; REFERENCES:
;	https://learn.microsoft.com/en-us/windows/win32/Intl/code-page-identifiers
;	https://learn.microsoft.com/en-us/windows/win32/intl/locale-information-constants#locale-name-constants
;	https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa741022(v=vs.85)
;	https://wutils.com/encodings/
