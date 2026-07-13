// Standalone run-once reproducer for the pacparser libFuzzer harness.
//
// Links the same LLVMFuzzerTestOneInput WITHOUT the libFuzzer runtime: reads a
// single input file and runs the harness once so a crashing input can be
// replayed (and crashes naturally under ASan/UBSan). No fuzzing loop.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <input-file>\n", argv[0]);
    return 1;
  }
  FILE *f = fopen(argv[1], "rb");
  if (!f) {
    fprintf(stderr, "failed to open %s\n", argv[1]);
    return 2;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (size < 0) {
    fclose(f);
    return 3;
  }
  uint8_t *data = (uint8_t *)malloc((size_t)size + 1);
  if (!data) {
    fclose(f);
    return 3;
  }
  size_t r = size ? fread(data, 1, (size_t)size, f) : 0;
  fclose(f);
  LLVMFuzzerTestOneInput(data, r);
  free(data);
  return 0;
}
