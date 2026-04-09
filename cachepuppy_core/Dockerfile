FROM hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20250428 AS build

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
RUN mix deps.compile

COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

FROM debian:bookworm-slim AS runtime

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses5 locales ca-certificates curl && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4000
ENV RELEASE_DISTRIBUTION=name

COPY --from=build /app/_build/prod/rel/cachepuppy_core ./

EXPOSE 4000

CMD ["bin/cachepuppy_core", "start"]
