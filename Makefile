source = src
compiler = odin
exe = gsolat.exe

$(exe):$(source)
	$(compiler) build $^ -out:$@

run:$(exe)
	@./$(exe)

rerun: clean run

prod:$(source)
	$(compiler) build $^ -out:$(exe) -o:speed -subsystem:windows

release: clean prod

clean:
	@rm -rf *.o *.obj *.exe; clear