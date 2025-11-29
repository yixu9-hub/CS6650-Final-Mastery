FROM golang:1.23-alpine AS build
WORKDIR /src

# Download deps
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /receiver

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
COPY --from=build /receiver /usr/local/bin/receiver
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/receiver"]
