ARG NODE_VERSION=20

# This is a multi-stage build. In this stage, all of the repo files are copied
# into the image and the `build-essentials` package is installed. This takes up
# a lot of image space, so we do it in this stage and later copy the resulting
# binaries only.
FROM docker.io/debian:bookworm-slim AS build

RUN apt-get update \
    && apt-get install -y build-essential \
    && apt-get install -y libcfitsio-dev \
    && apt-get install -y libcfitsio-bin

COPY . .

# This will create /src/webdir and copy some web root files there, and compile
# and install helper binaries to /usr/local/bin.
RUN ./configure \
   --prefix=/usr/local \
   --with-helper=nodejs \
   --with-webdir=/src/webdir \
   --with-cfitsio=/usr/lib \
   && make \
   && make install

# This is the actual base image. It is also Debian slim, but includes the
# required version of nodejs.
FROM docker.io/node:${NODE_VERSION}-bookworm-slim

# These next steps install some libraries and binaries for `js9helper`, as well
# as the supervisord package for managing multiple processes. Clean up after the
# apt commands to reduce the image size.
RUN apt-get update \
    && apt-get install -y libcfitsio-dev \
    && apt-get install -y btop \
    && apt-get install -y wget \
    && apt-get install -y file \
    && apt-get install -y funtools \
    && apt-get install -y supervisor \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && apt-get autoclean -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the web root files from the build stage.
COPY --from=build /src/webdir /app/web

# Copy the index and about files from the repo.
COPY ./index.html /app/web/index.html
COPY ./about.html /app/web/about.html

# Copy data files from the repo.
COPY ./demos/data /app/web/data

# Copy demo files from the repo.
COPY ./demos /app/web/demos

# Only copy the binaries from the build step. If we copy more, we get some cruft
# in /usr/local/share and other /usr/local directories. It does not appear that
# the build step includes anything in /usr/local/lib or related.
COPY --from=build /usr/local/bin /usr/local/bin

# Get a copy of the Caddy web server binary directly from its official image.
COPY --from=docker.io/caddy:2.8.4 /usr/bin/caddy /usr/bin/caddy

# Add a minimal Caddy configuration file.
COPY ./containerfiles/Caddyfile /etc/Caddyfile

# Add the Supervisor configuration file.
COPY ./containerfiles/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Use production node environment by default.
ENV NODE_ENV production

# Run the application as a non-root user. Commented for now since we run
# supervisor as root and tell it to run the applications as the `node` user.
# USER node

# Expose the web server port.
EXPOSE 9999

# Expose the node.js helper websocket port.
EXPOSE 2718

# Run the web server and application via supervisord.
CMD ["/usr/bin/supervisord"]
