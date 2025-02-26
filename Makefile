
all: native arm

native:
	cargo build --release

arm:
	cargo build --target=armv7-unknown-linux-gnueabihf --release

