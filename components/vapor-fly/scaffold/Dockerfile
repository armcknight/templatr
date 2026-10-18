# syntax=docker/dockerfile:1
# The server's image, which Fly runs and docker-compose.yml runs locally. The
# build stage compiles a release binary; the runtime stage has only the binary,
# the resources and the libraries it needs.

# ---------- build ----------
# Keep the Swift version in step with the local toolchain, so that concurrency
# checks and diagnostics are the same locally and in the image.
FROM swift:{{inputs.swift_version}}-{{inputs.linux_distribution}} AS build
WORKDIR /build

# Resolve the dependencies in their own layer, which stays cached until the
# manifests change. Copy local path packages here too, before the resolve.
COPY Package.swift Package.resolved ./
RUN swift package resolve

COPY . .
RUN swift build -c release --product {{inputs.product}} --static-swift-stdlib

# Stage the binary and the resources the server reads at run time.
RUN mkdir -p /staging \
 && cp "$(swift build -c release --product {{inputs.product}} --show-bin-path)/{{inputs.product}}" /staging/ \
 && if [ -d Resources ]; then cp -R Resources /staging/Resources; fi \
 && if [ -d Public ]; then cp -R Public /staging/Public; fi \
 && if [ -d resources ]; then cp -R resources /staging/resources; fi

# ---------- runtime ----------
FROM swift:{{inputs.swift_version}}-{{inputs.linux_distribution}}-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --user-group --create-home --system --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

# The commit the image was built from. The health check at
# {{inputs.health_check_path}} returns it, so a deploy can tell that the new
# image is the one answering. `make server deploy` and fly-deploy.yml pass it
# with `--build-arg GIT_SHA=…`.
ARG GIT_SHA=unknown
ENV GIT_SHA=$GIT_SHA

USER vapor:vapor
# The server reads its templates and static files relative to /app.
EXPOSE {{inputs.internal_port}}
ENTRYPOINT ["./{{inputs.product}}"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "{{inputs.internal_port}}"]
