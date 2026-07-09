.PHONY: render check drift clean

render:
	./render.py

check:
	./render.py --check

drift:
	./scripts/drift_check.py

clean:
	rm -f rendered/*.rsc
