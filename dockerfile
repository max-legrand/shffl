FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY dist/linux/shffl zig-out/bin/shffl
COPY web/dist web/dist/
COPY .env .env

EXPOSE 5882

CMD ["./zig-out/bin/shffl"]
