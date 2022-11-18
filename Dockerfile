# FROM alpine/git

# RUN wget -q  https://api.github.com/repos/cli/cli/releases/latest \
#     && wget -q $(cat latest | grep linux_amd64.tar.gz | grep browser_download_url | grep -v .asc | cut -d '"' -f 4) \
#     && tar -xvzf gh*.tar.gz \
#     && mv gh*/bin/gh /usr/local/bin/ \
#     && rm -fr *

FROM ubuntu as builder
WORKDIR /home/ 
RUN apt-get update && \
      apt-get -y install sudo
RUN sudo apt-get -y install hub
RUN sudo apt-get install -y coreutils

# FROM alpine/git
# COPY --from=builder /home/ ./
# RUN apk add --no-cache git openssh-client
# RUN apk add coreutils

# RUN conda install -c conda-forge hub

# ENV CHOCO_URL=https://chocolatey.org/install.ps1
# RUN Set-ExecutionPolicy Bypass -Scope Process -Force; \
#  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'; \
#  iex ((New-Object System.Net.WebClient).DownloadString("$env:CHOCO_URL"));
# RUN choco install hub

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
