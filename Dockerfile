FROM alpine:edge

RUN apk update && apk add clang-dev clang-libs clang-static llvm7 llvm7-dev llvm7-libs llvm7-static libexecinfo libexecinfo-dev libffi-dev zlib-dev cmake make build-base

WORKDIR /terra/build

COPY . /terra

RUN cmake -d ..

RUN make

FROM alpine:latest

RUN apk add zlib libffi libexecinfo libstdc++

COPY --from=0 /terra/build/bin/terra /usr/bin/terra
#COPY --from=0 /terra/build/include /usr/include
#COPY --from=0 /terra/build/lib /usr/lib

CMD terra
