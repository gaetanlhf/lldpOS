FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        tar \
        xorriso \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub-common \
        mtools \
        dosfstools \
        cpio \
        xz-utils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

CMD ["./build.sh"]
