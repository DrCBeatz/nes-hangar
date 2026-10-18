PYTHON ?= python3

.PHONY: all verify clean
all:
	$(PYTHON) tools/build.py

verify:
	$(PYTHON) tools/build.py --verify

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('build', ignore_errors=True)"
