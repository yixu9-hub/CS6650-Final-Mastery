FROM golang:1.23-alpine AS build
WORKDIR /src
COPY . .
RUN go build -o /processor

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
COPY --from=build /processor /usr/local/bin/processor
ENTRYPOINT ["/usr/local/bin/processor"]
