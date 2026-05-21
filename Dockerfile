FROM ubuntu:24.04

# Install dosemu2 from the upstream Ubuntu PPA. software-properties-common
# provides add-apt-repository; gnupg/ca-certificates are needed for the PPA key.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        software-properties-common \
        ca-certificates \
        gnupg \
        locales \
 && add-apt-repository -y ppa:dosemu2/ppa \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        dosemu2 \
 && locale-gen en_US.UTF-8 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

# Run as an unprivileged user. The host can bind-mount over /home/dosuser/.dosemu
# to persist drive_c and config between container runs.
RUN useradd -m -s /bin/bash dosuser
USER dosuser
WORKDIR /home/dosuser

# No DISPLAY is set, so dosemu starts in terminal (S-Lang) video mode, which
# works inside a plain `docker run -it` session. Pass extra args after the
# image name to override (e.g. `-E dir`, `-dumb`, a unix path to a DOS exe).
ENTRYPOINT ["dosemu"]
