# Ubuntu 20.04 (focal), slim: test image for install-abb.sh / install.run.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# curl - fetches the script; headers/build-essential/libglib - what the ABB
# installer needs on a bare system (pre-baked only to keep CI fast).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo ca-certificates curl \
        linux-headers-generic build-essential libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    # synosnap postinst aborts when it finds no initrd file in /boot;
    # update-initramfs is absent, the file is found and skipped.
    && K=$(basename "$(ls -d /lib/modules/* | head -1)") \
    && touch "/boot/initrd.img-$K"

WORKDIR /root/ABB
CMD ["bash"]
