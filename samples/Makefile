OBJS=bins/hello.o

ifdef DEBUG
	DEBUGFLGS = -g
else
	DEBUGFLGS =
endif


bins/hello: $(OBJS)
	ld $(OBJS) -o bins/hello -l System -syslibroot `xcrun --sdk macosx --show-sdk-path` -e main

bins/hello.o: hello.s
	as $(DEBUGFLGS) $< -o $@

clean:
	rm bins/*.o hello
