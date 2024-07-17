
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

{const:16} hextab db '0123456789ABCDEF'

:Main.error:

; TODO: show an error string ... fall into usage.

:Main.display_usage:
	.hOutput equ Main.hOutput
$ $	10,27,'[97m'
$ $	'Byte Character Table Utility version 0.1',10,10,27,'[32m'
$ $	'  Usage:',27,'[m',' charbyte [locale|codepage] <value>',10
$ $	'	the default mode is [codepage] (i.e. optional)',10
$ $	'	the default codepage is IBM437 OEM United States',10
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

	lstrcmpiW [rsi], W "help"
	test eax, eax
	jz .display_usage
	lstrcmpiW [rsi], W "codepage"
	test eax, eax
	jz .mode_codepage
	lstrcmpiW [rsi], W "locale"
	test eax, eax
	jz .mode_locale

	mov rdi, [rsi]
	call wtoi64_RDI
	jnz .arg_number
	test rax, rax
	jnz .display_usage ; too many digits
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
	cmp word [rdi], 0
	jnz .display_usage ; invalid form, numbers need to be complete arg
	mov ecx, eax
	movsxd rdx, eax
	sub rcx, rax
	jz @F
	sub rdx, rax
	jnz .bad_arg
@@:
	assert FLAG_CODEPAGE=0 & FLAG_LOCALE=1
	mov ecx, [.flags]
	and ecx, 11b
	cmp ecx, 10b
	jc .store_codepage
	jnz .display_usage ; ambiguous mode
.store_locale:
	mov [.locale], eax
	lodsq
	jmp .process_args
.store_codepage:
	mov [.codepage], eax
	lodsq
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
;	CP_ACP		system default Windows ANSI code page
;	CP_MACCP	system default Macintosh code page
;	CP_OEMCP	system default OEM code page
;	CP_THREAD_ACP	current thread's ANSI code page
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
	{bss:4} .cpiw CPINFOEXW
	GetCPInfoExW [.codepage], 0, & .cpiw ; translate identifiers to code page number
	test eax, eax ; BOOL
	jz .invalid_code_page
	cmp [.cpiw.MaxCharSize], 1
	jz .SBCS ; single-byte character set

$	10,27,'[93m',\
	'Warning: this tool is designed for use with single-byte character sets.',10

.SBCS:
; partial support for multibyte code pages?
	mov ecx, [.cpiw.CodePage]
	mov edx, MB_ERR_INVALID_CHARS or MB_USEGLYPHCHARS ; desired flags

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
	{bss:4} .dwFlags dd ?
	mov [.dwFlags], edx

; TODO: codepage/locale info header
; & .cpiw.CodePageName

$	10,KHEX,\
	"     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F     ",10,BRDR,\
	"   ╔═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╤═══╗   ",10

	xor ebx, ebx
.table_outer:
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
	MultiByteToWideChar [.cpiw.CodePage], [.dwFlags], & .char, 1, & .wide, 4
	cmp eax, 1
	jnz .char_unknown

; still need to filter out control:
	cmp word [.wide], ' '
	jc .char_control
; skip 0x007F-0x009F, C1 control block, ISO/IEC 8859, private use controls
	cmp word [.wide], 0x007F
	jc @F
	cmp word [.wide], 0x009F+1
	jc .char_control
@@:
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
	if 0 ; debugging
		{data:2} .debug5 du ' ????',10
		xor ebx, ebx
		mov rsi, qword [.debug5 + 2]
	@5:	mov [.char], bl
		MultiByteToWideChar [.cpiw.CodePage], [.dwFlags], & .char, 1, & .wide, 4
		mov qword [.debug5 + 2], rsi ; unknown
		cmp eax, 1
		jnz @F

		movzx eax, byte [.wide+1]
		mov ecx, eax
		shr eax, 4
		and ecx, 0xF
		movzx eax, byte [hextab + rax]
		movzx ecx, byte [hextab + rcx]
		mov [.debug5 + 2], ax
		mov [.debug5 + 4], cx

		movzx eax, byte [.wide]
		mov ecx, eax
		shr eax, 4
		and ecx, 0xF
		movzx eax, byte [hextab + rax]
		movzx ecx, byte [hextab + rcx]
		mov [.debug5 + 6], ax
		mov [.debug5 + 8], cx
	@@:
		add bl, 1
		xor r8, r8
		test bl, 0xF
		setz r8b
		add r8b, 5
		WriteConsoleW [.hOutput], & .debug5, r8, 0, 0
		test ebx, ebx
		jnz @5B
	end if
	jmp .done

.unable_to_resolve_locale:
	jmp .error

.locale_not_LCID: ; is this possible?
	jmp .error

.invalid_code_page:
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
