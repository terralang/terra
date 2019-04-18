FROM ubuntu:16.04

RUN apt-get update 
RUN apt-get install -y curl zip

WORKDIR /terra

RUN curl -L https://github.com/zdevito/terra/releases/download/release-1.0.0-beta1/terra-Linux-x86_64-2e2032e.zip -o /terra/terra.zip

RUN unzip terra.zip

CMD ["bash"]

FROM ubuntu:16.04

COPY --from=0 /terra/terra-Linux-x86_64-2e2032e/ /

ENTRYPOINT [ "/bin/terra" ]