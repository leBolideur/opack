bins/hello-pie: bins/hello-pie.o
	ld bins/hello-pie.o -o bins/hello-pie -e main

bins/hello-pie.o: hello.s
	as -g $< -o $@

clean:
	rm bins/*.o bins/hello-pie
