# Build stage
FROM docker.io/library/haskell:9.6.7-slim AS build
WORKDIR /build
COPY orchestrator.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies
COPY . .
RUN cabal build exe:orchestrator -O2 \
    && cp $(cabal list-bin orchestrator) /usr/local/bin/orchestrator \
    && strip /usr/local/bin/orchestrator

# Runtime stage
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -r -s /bin/false orchestrator
COPY --from=build /usr/local/bin/orchestrator /usr/local/bin/orchestrator
USER orchestrator
ENTRYPOINT ["orchestrator"]
CMD ["--help"]
