FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates python3 python3-venv nodejs npm ripgrep less \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash coder \
 && mkdir -p /home/coder/.config/opencode /home/coder/.local/share/opencode /home/coder/.cache/opencode /work \
 && git config --system safe.directory /work
COPY opencode /usr/local/bin/opencode
COPY opencode.json /home/coder/.config/opencode/opencode.json
RUN chmod 755 /usr/local/bin/opencode && chown -R coder:coder /home/coder /work
USER coder
ENV HOME=/home/coder
WORKDIR /work
ENTRYPOINT ["opencode"]
