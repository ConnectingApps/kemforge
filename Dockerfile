FROM golang:1.25-alpine AS builder

RUN go install github.com/ConnectingApps/kemforge@latest

FROM alpine:latest

COPY --from=builder /go/bin/kemforge /usr/local/bin/kemforge

ENTRYPOINT ["kemforge"]
CMD ["--version"]
