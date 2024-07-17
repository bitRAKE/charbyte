
; low-level utility to display a table of byte sized characters
;
;	fasm2 -e 50 charbyte.asm
;	link @charbyte.response charbyte.obj

; Obviously, this tool is not meant to support non-byte code pages or locales.

; Configure ANSI Colors:
BRDR	equ 27,'[90m'	; boarder
KHEX	equ 27,'[32m'	; axis key
KHAR	equ 27,'[m'	; character
KONT	equ 27,'[35m'	;	" control
KERR	equ 27,'[91m'	;	" invalid

FLAG_CODEPAGE	:= 0
FLAG_LOCALE	:= 1


include 'console.g'
include 'winnls.g'
extrn wtoi64_RDI

; just a console output helper (w/ caching)
calminstruction ?? line&
	local C,var,i
	init i

	match =$ line,line
	jyes conout
	assemble line
	exit

cash:	take C,line
	exit

conout:	match =$ line,line ; note '$$' produces an error
	jyes cash
rev:	take line,C
	jyes rev

	arrange var,=var.i
	arrange C,=COFF.2.=CONST var:
	assemble C

dat:	arrange C,=COFF.2.=CONST =du line
	assemble C
	take ,line
	take line,line
	jyes dat

	arrange C,=COFF.2.=CONST var.=chars =:== ( =$ - var ) =shr 1
	assemble C

	arrange C, =WriteConsoleW [.=hOutput], & var, var.=chars, 0, 0
	assemble C
	compute i,i+1

clr:	take ,C
	jyes clr
end calminstruction


:Main.error:

; TODO: show an error string ... fall into usage.

:Main.display_usage:
	.hOutput equ Main.hOutput
$ $	10,27,'[97m'
$ $	'Byte Character Table Utility version 0.1',10,10,27,'[32m'
$ $	'  Usage:',27,'[m',' charbyte [locale|codepage] <value>',10
$ $	'	the default mode is [codepage] (i.e. optional)',10
$ $	'	LOCALE_USER_DEFAULT is the default locale',10
$	'	<value> can be a number, name or string',10

:Main.done:
	ExitProcess [Main.result]
	jmp $

public Main as 'mainCRTStartup' ; linker expects this default entry point name
:Main:
	virtual at rbp - .local
		.lpCmdLine	dq ?
		.argv		dq ?
		.argn		dd ?
			align.assume rbp,16
			align 16
		.local := $-$$
				rq 2
		.hOutput	dq ?
		.result		dd ?
		.wide		rw 4
		.char		db ?
		assert $-.hOutput < 33 ; shadowspace limitation
	end virtual
	enter .frame + .local, 0
	mov [.result], 1

; default settings:
	{data:4} .locale	dd LOCALE_USER_DEFAULT ; LCID
	{data:4} .codepage	dd 437
	{data:4} .flags		dd 0

	GetStdHandle STD_OUTPUT_HANDLE
	mov [.hOutput], rax

	GetCommandLineW
	mov [.lpCmdLine], rax
	test rax, rax
	jz .display_usage
	xchg rcx, rax
	CommandLineToArgvW rcx, & .argn
	test rax, rax
	jz .display_usage
	mov [.argv], rax
	xchg rsi, rax
	lodsq ; skip program name
	test rax, rax
	jz .display_usage
.process_args:
	cmp qword [rsi], 0
	jz .args_processed

	lstrcmpiW [rsi], W "codepage"
	xchg ecx, eax
	jrcxz .mode_codepage
	lstrcmpiW [rsi], W "locale"
	xchg ecx, eax
	jrcxz .mode_locale

	mov rdi, [rsi]
	call wtoi64_RDI
	jnz .arg_number

	lodsq
	jmp .arg_string ; assume value is a string

.bad_arg:
	stc
.skip_arg:
	lodsq
	jc .display_usage ; argument unknown or possible error condition
	jmp .process_args

.mode_codepage:
	bts [.flags], FLAG_CODEPAGE
	jmp .skip_arg

.mode_locale:
	bts [.flags], FLAG_LOCALE
	jmp .skip_arg

.arg_number: ; support 32-bit [un]signed range
	mov ecx, eax
	movsxd rdx, eax
	sub rcx, rax
	jz @F
	sub rdx, rax
	jnz .bad_arg
@@:
	lodsq
	assert FLAG_CODEPAGE=0 & FLAG_LOCALE=1
	mov ecx, [.flags]
	and ecx, 11b
	cmp ecx, 10b
	jc .store_codepage
	jnz .display_usage ; ambiguous mode
.store_locale:
	mov [.locale], eax
	jmp .process_args
.store_codepage:
	mov [.codepage], eax
	jmp .process_args

.arg_string:
	assert FLAG_CODEPAGE=0 & FLAG_LOCALE=1
	mov ecx, [.flags]
	and ecx, 11b
	cmp ecx, 10b
	jc .string_codepage
	jnz .display_usage ; ambiguous mode
.string_locale:
	mov [.lpNameToResolve], rax
	jmp .process_args
.string_codepage:
	mov [.lpCodePage], rax
	jmp .process_args



.args_processed:
	test [.flags], 1 shl FLAG_LOCALE
	jz .basis_codepage
	cmp [.lpNameToResolve], 0
	jz .basis_locale ; use numeric locale

{bss:8} .lpCodePage		dq ?
{bss:8} .lpNameToResolve	dq ?
{bss:2} .LocaleName		rw LOCALE_NAME_MAX_LENGTH

	ResolveLocaleName [.lpNameToResolve], & .LocaleName, LOCALE_NAME_MAX_LENGTH
	test eax, eax
	jz .unable_to_resolve_locale
	LocaleNameToLCID & .LocaleName, LOCALE_ALLOW_NEUTRAL_NAMES
	test eax, eax
	jz .locale_not_LCID
	mov [.locale], eax
	jmp .basis_locale

.basis_codepage:
	cmp [.lpCodePage], 0
	jz .have_codepage ; use numeric codepage

	; TODO: resolve code page string

	; TODO: find suitable locale for codepage selection:

.basis_locale:

	; TODO: warn if the code page is not a single byte code page

	{const:64} .lpSrcStr:
	repeat 256
		{const:64} db %-1
	end repeat
	{bss:64} .lpCharType rw 256

	GetStringTypeExA [.locale], CT_CTYPE1, & .lpSrcStr, 256, & .lpCharType
	test eax, eax ; BOOL
	jz .error

	; TODO: find suitable codepage for locale:

; LCIDToLocaleName
;	char buf[19];
;	int ccBuf = GetLocaleInfo(LOCALE_SYSTEM_DEFAULT, LOCALE_SISO639LANGNAME, buf, 9);
;	buf[ccBuf++] = '-';
;	ccBuf += GetLocaleInfo(LOCALE_SYSTEM_DEFAULT, LOCALE_SISO3166CTRYNAME, buf+ccBuf, 9);

.have_codepage:

$	10,KHEX,\
	"     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F     ",10,BRDR,\
	"   ╔═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╗   ",10

	xor ebx, ebx
.table_outer:
	{const:16} hextab db '0123456789ABCDEF'
	mov eax, ebx
	shr eax, 4
	mov al, [hextab + rax]
	mov [.lead_in.index], ax
	mov [.lead_out.index], ax
	{data:2} .lead_in du ' ',KHEX
	{data:2} .lead_in.index du 'X',BRDR,' ║ ',KHAR
	{data:2} .lead_in.end:
	.lead_in.chars := (.lead_in.end - .lead_in) shr 1
	WriteConsoleW [.hOutput], & .lead_in, .lead_in.chars, 0, 0

.table_inner:
;	test [.lpCharType + rbx*2], C1_CNTRL
;	jnz .char_control

.char_output:
	mov [.char], bl

; codepage	ranges, FIXME: don't care if encoding not single byte
; 37		04 06 ?+ -3F FF
; 437		FF
; 1250		83 ?+ 98
; 1361		80-8F
; 20424		20-3F FF
; 28591		80-9F

; partial support for multibyte code pages?

	xor eax, eax ; the following code pages only support dwFlags of zero:
	iterate cp, 42,<50220,50222>,50225,50227,50229,<57002,57011>,65000
		match low_cp =, high_cp,cp
			cmp ecx, low_cp
			jc .%
			cmp ecx, high_cp+1
			cmovc edx, eax
		.%:
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

	MultiByteToWideChar [.codepage], MB_ERR_INVALID_CHARS or MB_USEGLYPHCHARS,\
		& .char, 1, & .wide, 4
	cmp eax, 1
	jnz .char_unknown

; still need to filter out control:
	cmp word [.wide], ' '
	jc .char_control
;	cmp word [.wide], ?
;	jz .char_control

	WriteConsoleW [.hOutput], & .wide, 1, 0, 0
	jmp .tween

.char_control: ; TODO: control lookup?
	$	KONT,'�'
	jmp .tween

.char_unknown:
	$	KERR,'�'

.tween:
	$	BRDR,' │ ',KHAR
	inc ebx
	test ebx, 0x0F
	jnz .table_inner

	{data:2} .lead_out du 8,8,8,BRDR,' ║ ',KHEX
	{data:2} .lead_out.index du 'X ',10
	{data:2} .lead_out.end:
	.lead_out.chars := (.lead_out.end - .lead_out) shr 1
	WriteConsoleW [.hOutput], & .lead_out, .lead_out.chars, 0, 0

	test bl, bl
	jz .table_footer
	cmp bl, 0x80
	jz .table_split
$	BRDR,\
	"   ╟───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───╢   ",10
	jmp .table_outer

.table_split:
$	BRDR,\
	"   ╠═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╪═══╣   ",10
	jmp .table_outer

.table_footer:

$	BRDR,\
	"   ╚═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╧═══╝   ",10,KHEX,\
	"     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F     ",10,27,'[m'

	mov [.result], 0
	jmp .done

.unable_to_resolve_locale:
	jmp .error

.locale_not_LCID: ; is this possible?
	jmp .error


; REFERENCES:
;	https://learn.microsoft.com/en-us/windows/win32/Intl/code-page-identifiers
;	https://learn.microsoft.com/en-us/windows/win32/intl/locale-information-constants#locale-name-constants
;	https://wutils.com/encodings/


virtual as "response" ; configure linker from here:
	db '/NOLOGO',10
;	db '/VERBOSE',10 ; use to debug process
	db '/NODEFAULTLIB',10
	db '/BASE:0x10000',10
	db '/DYNAMICBASE:NO',10
	db '/IGNORE:4281',10 ; bogus warning to scare people away
	db '/SUBSYSTEM:CONSOLE,6.02',10
	db 'kernel32.lib',10
	db 'shell32.lib',10
	db 'shlwapi.lib',10
end virtual
