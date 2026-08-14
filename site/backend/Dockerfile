FROM ruby:3.4-slim

# build-essential: compila extensões nativas de gems (ex: nokogiri, via libxml)
# libpq-dev: headers do Postgres exigidos pela gem `pg`
# libyaml-dev: psych (parser YAML do Ruby) built-in do Ruby 3.4 depende disso pra compilar
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
