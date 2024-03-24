# Définir les fichiers source
SOURCES := $(wildcard *.s)

# Convertir les sources en noms de fichiers objets et binaires
OBJECTS := $(patsubst %.s,bins/%.o,$(SOURCES))
BINARIES := $(patsubst %.s,bins/%,$(SOURCES))

# Règle par défaut pour construire tous les binaires
all: $(BINARIES)

# Règles génériques pour construire des binaires à partir d'objets
bins/%: bins/%.o
	ld $< -o $@ -e main

# Règles génériques pour construire des objets à partir de sources asm
bins/%.o: %.s
	as -g $< -o $@

# Règle de nettoyage
clean:
	rm -f $(OBJECTS) $(BINARIES)

# Éviter les conflits avec les fichiers de même nom
.PHONY: all clean
