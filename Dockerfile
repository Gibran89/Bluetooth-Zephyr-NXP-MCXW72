
# Dockerfile
# Imagen oficial de desarrollo de Zephyr, versión estable fijada
FROM ghcr.io/zephyrproject-rtos/zephyr-build:v0.29.4

# Argumentos para coincidir con el usuario del host (sobrescribibles con --build-arg)
ARG UID=1000
ARG GID=1000
ARG USERNAME=zephyr

USER root

# Renombrar el usuario existente (UID 1000) a nuestro USERNAME
RUN existing_user=$(getent passwd ${UID} | cut -d: -f1) && \
    existing_group=$(getent group ${GID} | cut -d: -f1) && \
    if [ -n "$existing_user" ] && [ "$existing_user" != "${USERNAME}" ]; then \
        usermod -l ${USERNAME} -d /home/${USERNAME} -m "$existing_user" && \
        groupmod -n ${USERNAME} "$existing_group"; \
    fi && \
    mkdir -p /workdir && chown -R ${UID}:${GID} /workdir

USER ${USERNAME}
WORKDIR /workdir