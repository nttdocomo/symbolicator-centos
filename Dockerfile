# FROM python:3.6.13-slim-buster
FROM centos:7.8.2003 AS symbolicator-deps

ARG BUILD_ARCH=x86_64
# Pin the Rust version for now
ARG RUST_TOOLCHAIN_VERSION=1.58.1
ENV BUILD_ARCH=${BUILD_ARCH}
ENV BUILD_TARGET=${BUILD_ARCH}-unknown-linux-gnu
ENV RUST_TOOLCHAIN_VERSION=${RUST_TOOLCHAIN_VERSION}

# ENV RUSTUP_HOME=/usr/local/rustup \
#     CARGO_HOME=/usr/local/cargo \
#     PATH=/usr/local/cargo/bin:$PATH

# relay的编译依赖cmake3.2以上，系统默认的是2.8.12.2
COPY ./cmake-3.24.3.tar.gz /
RUN set -x \
    && yum --nogpg install -y gcc gcc-c++ make openssl-devel \
    && tar zxvf cmake-3.* \
    && rm cmake-3.*tar.gz \
    && cd cmake-3.* \
    && ./bootstrap --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && rm -rf /cmake-3.* \
    && yum clean all

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain=${RUST_TOOLCHAIN_VERSION}

WORKDIR /work

#####################
### Builder stage ###
#####################

FROM symbolicator-deps AS symbolicator-builder

# Build with the modern compiler toolchain enabled
RUN echo -e "[net]\ngit-fetch-with-cli = true" > $CARGO_HOME/config \
    && git clone --branch 21.5.0 https://github.com/getsentry/symbolicator.git . \
    && git update-index --skip-worktree $(git status | grep deleted | awk '{print $2}') \
    && cargo build --release --locked \
    && objcopy --only-keep-debug target/release/symbolicator target/release/symbolicator.debug \
    && objcopy --strip-debug --strip-unneeded target/release/symbolicator \
    && objcopy --add-gnu-debuglink target/release/symbolicator target/release/symbolicator.debug \
    && cp ./target/release/symbolicator /usr/local/bin \
    && zip /opt/symbolicator-debug.zip target/release/symbolicator.debug

COPY ./sentry-cli-Linux-x86_64 /bin/sentry-cli
RUN chmod ugo+x /bin/sentry-cli \
    # Collect source bundle
    && sentry-cli --version \
    && SOURCE_BUNDLE="$(sentry-cli difutil bundle-sources ./target/release/symbolicator.debug)" \
    && mv "$SOURCE_BUNDLE" /opt/symbolicator.src.zip
