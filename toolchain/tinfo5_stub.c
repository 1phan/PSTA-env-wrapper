/* Last-resort stub for the 4 libtinfo.so.5 symbols that some prebuilt LLVM
 * binaries import (terminal-color detection only). Used only if the host lacks
 * a usable libtinfo.so.5 AND the prebuilt LLVM was built against ncurses-5.
 * The default toolchain (ubuntu-22.04 / ncurses-6) does NOT need this.
 * Safe no-ops that report "no terminal" -> colorized diagnostics off; the
 * compiler/optimizer/analyzer are unaffected. Pair with tinfo5.map. */
typedef void TERMINAL;
int setupterm(char *term, int fildes, int *errret) { (void)term; (void)fildes; if (errret) *errret = 0; return -1; }
int tigetnum(char *capname) { (void)capname; return -1; }
TERMINAL *set_curterm(TERMINAL *nterm) { (void)nterm; return (TERMINAL *)0; }
int del_curterm(TERMINAL *oterm) { (void)oterm; return 0; }
