if __FILE__ = __SOURCE__ ; ------------------------------- building object file

format MS64 COFF
section '.text$t' code executable readable align 64

public wtoi64_RDI
wtoi64_RDI:
	mov ecx, 1
	xor eax, eax
	cmp word [rdi], '-'
	jnz .not_negative
	mov cl, 3
	add rdi, 2
.not_negative:
	ror rcx, 1 ; set high bit
	push rdi
.read_digits:
	movzx edx, word [rdi]
	sub edx, '0'
	cmp edx, 10
	jnc .done
	imul rax, rax, 10
	jo .overflow
	add rdi, 2
	add rax, rdx
	cmp rax, rcx
	jc .read_digits
.overflow:
	pop rdi
	push rdi	; force zero digits, fall through ...
.done:
	jecxz .positive ; note ECX!
	neg rax
.positive:
	pop rcx
	sub ecx, edi
	retn
	assert 64 >= $ - wtoi64_RDI

; ZF=1  RCX=0 on error, RAX invalid
;
; ZF=0  RCX : bytes consumed
;	RDI : updated, first non-digit character
;	RAX : signed-qword result
;	RDX : [0,9]

else ; ---------------------------------------------------- including interface

extrn wtoi64_RDI

end if
