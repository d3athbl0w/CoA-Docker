# syntax=docker/dockerfile:1
ARG UBUNTU_VERSION=24.04

# ==============================================================================
# Stage 1: Skeleton (Base OS directory layout & unprivileged user setup)
# ==============================================================================
FROM ubuntu:${UBUNTU_VERSION} AS skeleton

ARG TZ=Etc/UTC
ARG DEBIAN_FRONTEND=noninteractive
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_USER=acore

ENV AC_FORCE_CREATE_DB=1

# Create standard AzerothCore directory structure
RUN mkdir -pv \
        /azerothcore/bin                   \
        /azerothcore/data                  \
        /azerothcore/deps                  \
        /azerothcore/env/dist/bin          \
        /azerothcore/env/dist/data/Cameras \
        /azerothcore/env/dist/data/dbc     \
        /azerothcore/env/dist/data/maps    \
        /azerothcore/env/dist/data/mmaps   \
        /azerothcore/env/dist/data/vmaps   \
        /azerothcore/env/dist/logs         \
        /azerothcore/env/dist/temp         \
        /azerothcore/env/dist/etc          \
        /azerothcore/env/ref/etc           \
        /azerothcore/modules               \
        /azerothcore/src                   \
        /azerothcore/build

# Configure Timezone & Certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
        tzdata \
        ca-certificates \
        curl \
        adduser \
    && ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
    && echo "${TZ}" > /etc/timezone \
    && dpkg-reconfigure --frontend noninteractive tzdata \
    && rm -rf /var/lib/apt/lists/*

# Manage non-root user (remove existing default ubuntu user if present)
RUN (userdel --remove ubuntu 2>/dev/null || true) \
    && (addgroup --gid "${GROUP_ID}" "${DOCKER_USER}" 2>/dev/null || true) \
    && adduser --disabled-password --gecos '' --uid "${USER_ID}" --gid "${GROUP_ID}" "${DOCKER_USER}" \
    && passwd -d "${DOCKER_USER}" \
    && chown -R "${DOCKER_USER}:${DOCKER_USER}" /azerothcore

WORKDIR /azerothcore

# ==============================================================================
# Stage 2: Builder (Compile AzerothCore from source using Clang and Ninja)
# ==============================================================================
FROM skeleton AS builder

ARG CTOOLS_BUILD="all"
ARG CTYPE="RelWithDebInfo"
ARG CSCRIPTS="static"
ARG CMODULES="static"
ARG CWITH_WARNINGS="OFF"
ARG SOURCE_PATH="source"
ARG AC_REV_HASH="6b935188c99b"
ARG AC_REV_DATE="2026-09-13 15:04:25 +0300"
ARG AC_REV_BRANCH="main"

ARG CCACHE_DIR="/ccache"
ARG CCACHE_MAXSIZE="2000MB"

# Install complete build toolchain and development headers
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ccache \
        libtool \
        cmake-data \
        ninja-build \
        cmake \
        clang \
        git \
        lsb-base \
        curl \
        unzip \
        default-mysql-client \
        openssl \
        default-libmysqlclient-dev \
        libboost-all-dev \
        libssl-dev \
        libmysql++-dev \
        libreadline-dev \
        zlib1g-dev \
        libbz2-dev \
        libncurses5-dev \
        liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source tree components
COPY ${SOURCE_PATH}/CMakeLists.txt /azerothcore/CMakeLists.txt
COPY ${SOURCE_PATH}/conf /azerothcore/conf
COPY ${SOURCE_PATH}/deps /azerothcore/deps
COPY ${SOURCE_PATH}/src /azerothcore/src
COPY ${SOURCE_PATH}/modules /azerothcore/modules

WORKDIR /azerothcore/build

# Compile using Ninja and BuildKit compiler cache
RUN --mount=type=cache,target=/ccache,sharing=locked \
    cmake /azerothcore \
        -G Ninja \
        -DCMAKE_INSTALL_PREFIX="/azerothcore/env/dist" \
        -DAPPS_BUILD="all" \
        -DTOOLS_BUILD="${CTOOLS_BUILD}" \
        -DSCRIPTS="${CSCRIPTS}" \
        -DMODULES="${CMODULES}" \
        -DWITH_WARNINGS="${CWITH_WARNINGS}" \
        -DCMAKE_BUILD_TYPE="${CTYPE}" \
        -DCMAKE_CXX_COMPILER="clang++" \
        -DCMAKE_C_COMPILER="clang" \
        -DCMAKE_CXX_COMPILER_LAUNCHER="ccache" \
        -DCMAKE_C_COMPILER_LAUNCHER="ccache" \
        -DBoost_USE_STATIC_LIBS="ON" \
        -DWITHOUT_GIT=1 \
        -Drev_hash="${AC_REV_HASH}" \
        -Drev_branch="${AC_REV_BRANCH}" \
        -Drev_date="${AC_REV_DATE}" \
    && cmake --build . --config "${CTYPE}" -j $(($(nproc) + 1)) \
    && cmake --install . --config "${CTYPE}" \
    && mkdir -p /azerothcore/env/ref/etc \
    && cp -rn /azerothcore/env/dist/etc/* /azerothcore/env/ref/etc/

# ==============================================================================
# Stage 3: Runtime Base (Lean environment with dynamic runtime libraries only)
# ==============================================================================
FROM skeleton AS runtime

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_USER=acore

ENV ACORE_COMPONENT=undefined
ENV PATH="/azerothcore/env/dist/bin:$PATH"

# Install strictly runtime dynamic libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
        libmysqlclient21 \
        libreadline8t64 \
        libssl3 \
        libncurses6 \
        libicu74 \
        default-mysql-client \
        curl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy reference configuration templates generated by build
COPY --from=builder /azerothcore/env/ref/etc/ /azerothcore/env/ref/etc/

# Copy container entrypoint script
COPY docker/server/entrypoint.sh /azerothcore/entrypoint.sh
RUN chmod 755 /azerothcore/entrypoint.sh \
    && chown -R "${DOCKER_USER}:${DOCKER_USER}" /azerothcore

USER ${DOCKER_USER}

ENTRYPOINT ["/azerothcore/entrypoint.sh"]

# ==============================================================================
# Target: Auth Server
# ==============================================================================
FROM runtime AS authserver
LABEL description="AzerothCore WotLK (CoA) Authentication Server"

ENV ACORE_COMPONENT=authserver
ENV AC_UPDATES_ENABLE_DATABASES=0
ENV AC_DISABLE_INTERACTIVE=1
ENV AC_CLOSE_IDLE_CONNECTIONS=0

COPY --chown=acore:acore --from=builder \
    /azerothcore/env/dist/bin/authserver /azerothcore/env/dist/bin/authserver

CMD ["authserver"]

# ==============================================================================
# Target: World Server
# ==============================================================================
FROM runtime AS worldserver
LABEL description="AzerothCore WotLK (CoA) World Server"

ENV ACORE_COMPONENT=worldserver
ENV AC_UPDATES_ENABLE_DATABASES=0
ENV AC_DISABLE_INTERACTIVE=1
ENV AC_CLOSE_IDLE_CONNECTIONS=0

COPY --chown=acore:acore --from=builder \
    /azerothcore/env/dist/bin/worldserver /azerothcore/env/dist/bin/worldserver

CMD ["worldserver"]

# ==============================================================================
# Target: Database Import & Migration Tool
# ==============================================================================
FROM runtime AS db-import
LABEL description="AzerothCore WotLK (CoA) Database Import Tool"

ARG SOURCE_PATH="source"
ENV ACORE_COMPONENT=dbimport

# Include base and update SQL definitions
COPY --chown=acore:acore ${SOURCE_PATH}/data /azerothcore/data
COPY --chown=acore:acore ${SOURCE_PATH}/modules /azerothcore/modules

COPY --chown=acore:acore --from=builder \
    /azerothcore/env/dist/bin/dbimport /azerothcore/env/dist/bin/dbimport

CMD ["/azerothcore/env/dist/bin/dbimport"]

# ==============================================================================
# Target: Extractor Tools (Optional Profile)
# ==============================================================================
FROM runtime AS tools
LABEL description="AzerothCore WotLK (CoA) Map & DBC Extractors"

WORKDIR /azerothcore/env/dist/bin

COPY --chown=acore:acore --from=builder \
    /azerothcore/env/dist/bin/map_extractor \
    /azerothcore/env/dist/bin/mmaps_generator \
    /azerothcore/env/dist/bin/vmap4_assembler \
    /azerothcore/env/dist/bin/vmap4_extractor \
    /azerothcore/env/dist/bin/
