# charbyte

`charbyte` is a small Win64 console utility for displaying all 256 byte values as a character table for a selected Windows code page and/or locale. It is intended for single-byte character sets; multibyte code pages are detected and reported with a warning by the program.

The repository includes the assembly sources and a checked-in `charbyte.exe` build.

## Usage

```text
charbyte [help|locale|codepage] <value>
```

Examples:

```bat
charbyte
charbyte codepage 437
charbyte codepage CP_OEMCP
charbyte locale en-US
```

Notes from the current command-line parser:

- `codepage` is the default mode, so `charbyte 437` is equivalent to `charbyte codepage 437`.
- The default code page is 437.
- `locale` accepts numeric LCIDs and locale names/strings that `ResolveLocaleName` and `LocaleNameToLCID` can resolve.
- Code-page aliases currently handled in source are `CP_ACP`, `CP_OEMCP`, `CP_MACCP`, `CP_THREAD_ACP`, `CP_UTF7`, and `CP_UTF8`.

## Building

The checked-in `build.cmd` documents the expected Windows build flow:

```bat
fasm2 -e 50 wtoi64.asm
fasm2 -e 50 charbyte.asm
link @charbyte.response charbyte.obj wtoi64.obj
```

Requirements:

- `fasm2` available on `PATH`.
- Microsoft `link.exe` and the standard Windows import libraries available from a Visual Studio / Build Tools developer command prompt.

`charbyte.asm` emits `charbyte.response` via its final `virtual as "response"` block, so the linker options are configured alongside the program source.
