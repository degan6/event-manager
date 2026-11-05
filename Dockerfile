# syntax=docker/dockerfile:1.4
# ========================================
# Stage 1: Builder - Install dependencies and build assets
# ========================================
FROM ruby:4.0.9 AS builder

# Install build dependencies
# ImageMagick: Debian metapackage; apt-get update picks up current security/main versions at build time
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libyaml-dev \
    curl \
    git \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 26.x LTS and Yarn 1.x (Classic) via Corepack, installed from npm since Node 25+ no longer bundles it (avoids deprecated apt-key Yarn repo)
RUN curl -fsSL https://deb.nodesource.com/setup_26.x | bash - && \
    apt-get update -qq && apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g corepack && corepack enable && corepack prepare yarn@1.22.22 --activate

WORKDIR /app

# Copy dependency files first (for better layer caching)
COPY Gemfile Gemfile.lock ./
COPY package.json yarn.lock* ./

# Install Ruby gems with cache mount for faster rebuilds
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Install Node modules with cache mount for faster rebuilds
RUN --mount=type=cache,target=/app/node_modules/.cache \
    yarn install --frozen-lockfile --production=false

# Copy application code
COPY . .

# VERSION file should be created by CI/CD before build
# If it doesn't exist (local builds), create it from git or use 'dev'
RUN if [ ! -f VERSION ]; then \
      git describe --tags --always 2>/dev/null > VERSION || echo "dev-local" > VERSION; \
    fi

# Build CSS and JS in parallel
RUN yarn build & yarn build:css & wait

# Precompile assets for production
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production bundle exec rake assets:precompile

# JS tooling is only needed to build assets; keep it out of the runtime image
RUN rm -rf node_modules

# ========================================
# Stage 2: Runtime - Minimal production image
# ========================================
FROM ruby:4.0.9-slim AS runtime

# Updated per deployment protocol: CI passes APP_VERSION; local builds default to dev
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

# Install only runtime dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    postgresql-client \
    libpq-dev \
    curl \
    imagemagick \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code and built assets
COPY --from=builder /app /app

# Expose port 3000
EXPOSE 3000

# Create a script to handle database setup and start the server
COPY docker-entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# Start the server
CMD ["rails", "server", "-b", "0.0.0.0"]
