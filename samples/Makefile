OBJS=bins/rlynodata.o

ifdef DEBUG
	DEBUGFLGS = -g
else
	DEBUGFLGS =
endif


bins/rlynodata: $(OBJS)
	ld $(OBJS) -o bins/rlynodata -l System -syslibroot `xcrun --sdk macosx --show-sdk-path` -e main

bins/rlynodata.o: rlynodata.s
	as $(DEBUGFLGS) $< -o $@

clean:
	rm bins/*.o rlynodata
