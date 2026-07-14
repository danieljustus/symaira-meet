BINARY := symmeet

.PHONY: build test lint clean

build:
	swift build

test:
	swift test

lint:
	swift format lint --recursive Sources Tests

clean:
	swift package clean
	rm -rf .build
