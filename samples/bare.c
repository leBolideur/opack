#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <errno.h>
#include <sys/mman.h>

const char *instructions = "\xd2\x80\x00\x00\xd2\x80\x00\x30\xd4\x00\x00\x01";
const size_t instructions_len = 12;

int main() {
  printf("        main @ %p\n", &main);
  printf("instructions @ %p\n", instructions);

  size_t region = (size_t)instructions;
  region = region & ~(0xFFF);
  printf("        page @ %p\n", (void *)region);

  printf("making instructions executable...\n");
  getchar();
  int ret = mprotect((void *)region, // addr
                     0x4000,         // len - now the size of a page (4KiB)
                     PROT_READ | PROT_EXEC // prot
  );
  if (ret != 0) {
    printf("mprotect failed: error %d\n", errno);
    return 1;
  }

  void (*f)(void) = (void *)instructions;
  printf("jumping...\n");
  f();
  printf("after jump\b");
}
