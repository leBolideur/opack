#include <stdio.h>

int global_var = 4242;

int myFunction() {
  printf("Valeur: %d\n", global_var);
  return global_var;
}

int main() {
  int value = myFunction();
  return value;
}
