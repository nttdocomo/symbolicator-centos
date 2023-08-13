FROM centos:7.8.2003

ARG BUILD_ARCH=x86_64
# Pin the Rust version for now
ARG RUST_TOOLCHAIN_VERSION=1.50.0
ENV BUILD_ARCH=${BUILD_ARCH}
ENV RUST_TOOLCHAIN_VERSION=${RUST_TOOLCHAIN_VERSION}

RUN set -x \
    && curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo \
    && yum clean all -y \
    && yum update -y \
    && yum makecache -y \
    && yum --nogpg install -y centos-release-scl scl-utils git openssl-devel zip \
    && yum --nogpg install -y devtoolset-7-gcc* \
    && yum clean all

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain=${RUST_TOOLCHAIN_VERSION}

WORKDIR /work

# #####################
# ### Builder stage ###
# #####################

# Build with the modern compiler toolchain enabled
RUN echo "source scl_source enable devtoolset-7" >> /etc/bashrc \
    && source /etc/bashrc \
    && echo -e "[net]\ngit-fetch-with-cli = true" > $CARGO_HOME/config \
    && git clone --branch 0.3.3 https://github.com/getsentry/symbolicator.git . \
    # && git update-index --skip-worktree $(git status | grep deleted | awk '{print $2}') \
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
    && mv "$SOURCE_BUNDLE" /opt/symbolicator.src.zip \
    && yum autoremove -y git openssl-devel zip scl-utils