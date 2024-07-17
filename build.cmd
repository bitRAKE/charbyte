@echo off
call fasm2 -e 50 wtoi64.asm
call fasm2 -e 50 charbyte.asm
link @charbyte.response charbyte.obj wtoi64.obj
