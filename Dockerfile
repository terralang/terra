FROM alpine:edge

RUN apk update && apk add git clang-dev clang-libs clang-static llvm7 llvm7-dev llvm7-libs llvm7-static libexecinfo libexecinfo-dev libffi-dev zlib-dev cmake make build-base

WORKDIR /terra/build

COPY . /terra

RUN cmake -d .. && make clean && make && make test

FROM alpine:latest

RUN apk add zlib zlib-dev libffi libffi-dev libexecinfo libexecinfo-dev libstdc++ libc-dev build-base

COPY --from=0 /terra/build/bin/terra /usr/bin/terra
COPY --from=0 /terra/build/include /usr/include
COPY --from=0 /terra/build/lib /usr/lib
COPY --from=0 /terra/tests /usr/share/terra/tests

CMD terra
