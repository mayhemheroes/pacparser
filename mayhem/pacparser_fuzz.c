// libFuzzer harness for pacparser.
//
// The historical Mayhem target for this fork was the file-input CLI
// `pactester -p @@ -u google.com`. pactester is a thin allocate-and-exit
// wrapper that reads one PAC file and exits, so as a raw file-input target it
// re-launches a process per input and yields almost no coverage. This harness
// drives the SAME code path in-process (skill-endorsed conversion of an
// unfuzzable raw file-input CLI to an in-process libFuzzer target), feeding
// attacker-controlled bytes straight to the PAC engine:
//
//     pacparser_init -> pacparser_parse_pac_string -> pacparser_find_proxy
//
// which exercises the embedded QuickJS interpreter (lexer, parser, bytecode VM)
// plus pacparser's PAC helper functions on the fuzzed script. init/cleanup are
// balanced every iteration (pacparser keeps all state in process globals), so
// the harness owns no memory across runs.
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "pacparser.h"

// Swallow pacparser's error/debug output so a failed parse (the common case for
// fuzzer inputs) doesn't drown the run in stderr. Matches the library's
// pacparser_error_printer signature.
static int quiet_printer(const char *fmt, va_list argp) {
  (void)fmt;
  (void)argp;
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // NUL-terminate: pacparser_parse_pac_string takes a C string.
  char *script = (char *)malloc(size + 1);
  if (!script)
    return 0;
  if (size)
    memcpy(script, data, size);
  script[size] = '\0';

  pacparser_set_error_printer(quiet_printer);

  if (pacparser_init()) {
    if (pacparser_parse_pac_string(script)) {
      // Fixed URL/host: the fuzzed surface is the PAC script itself. The
      // returned string is an internal buffer owned by pacparser (valid until
      // the next call / cleanup) — do NOT free it.
      pacparser_find_proxy("http://www.example.com/index.html",
                           "www.example.com");
    }
    pacparser_cleanup();
  }

  free(script);
  return 0;
}
