# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:45 AS builder

# Chave GPG oficial do negativo17, versionada em security/keys/.
# Fingerprint: 0C5D 0F47 0484 AE2F C40A 9B65 97F3 0089 93E8 909B
COPY security/keys/RPM-GPG-KEY-slaanesh /tmp/RPM-GPG-KEY-slaanesh

RUN dnf5 -y upgrade 'kernel*' --refresh && \
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" && \
    echo "cd037a2d00bd3126e808d53921e28ca7bafabc1834abd675d4ad4b5b4d850f49  /tmp/RPM-GPG-KEY-slaanesh" | sha256sum -c - && \
    rpm --import /tmp/RPM-GPG-KEY-slaanesh && \
    curl --fail --silent --show-error --location --retry 3 \
      --output /etc/yum.repos.d/fedora-nvidia-580.repo \
      https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio, imagem final com driver NVIDIA versão 580 Negativo17
FROM quay.io/fedora/fedora-bootc:45 AS final

# Entradas usadas durante o build, antes dos passos pesados.
# 1) artefatos vindos do builder; 2) listas de pacotes.
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo \
    /var/cache/akmods/nvidia/kmod-nvidia*.rpm \
    /run/build-inputs/
COPY config/nvidia/nvidia_packages \
    config/packages/pacotes_necessarios \
    config/packages/pacotes_desktop \
    security/keys/RPM-GPG-KEY-slaanesh \
    /run/build-inputs/

# 1. Configuração de repositórios e instalação de Kernel Extras + NVIDIA
# rpmkeys sai com 0 também para pacote não assinado, por isso cada pacote é
# conferido individualmente. Mantido o rpm -vi --nodeps para NÃO puxar
# dependências de compilação para a imagem final (sem --nosignature).
# Só o kernel é atualizado aqui: o restante da base já é entregue pela tag
# fedora-bootc:45 (reconstruída diariamente) e um "dnf upgrade" completo
# criaria uma camada grande e volátil, que o bootc upgrade teria de baixar
# de novo a cada atualização. Atualizar o kernel mantém o módulo akmods
# alinhado ao kernel usado no estágio builder.
RUN mv /run/build-inputs/fedora-nvidia-580.repo /etc/yum.repos.d/ && \
    rpm --import /run/build-inputs/RPM-GPG-KEY-slaanesh && \
    dnf5 -y upgrade --refresh 'kernel*' && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install --setopt=tsflags=nodocs "kernel-modules-extra-${kver}" && \
    dnf5 download --destdir=/run/build-inputs nvidia-kmod-common nvidia-driver-cuda && \
    for pkg in /run/build-inputs/nvidia-kmod-common*.rpm /run/build-inputs/nvidia-driver-cuda*.rpm; do \
      LC_ALL=C rpmkeys --checksig "$pkg" | grep -q 'signatures OK' || \
        { echo "ERRO: pacote sem assinatura valida: $pkg"; exit 1; }; \
    done && \
    rpm -vi --nodeps /run/build-inputs/nvidia-kmod-common*.rpm /run/build-inputs/nvidia-driver-cuda*.rpm && \
    grep -v '^#' /run/build-inputs/nvidia_packages | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 -y install /run/build-inputs/kmod-nvidia-*.rpm && \
    rm -rf /run/build-inputs/nvidia-kmod-common*.rpm /run/build-inputs/nvidia-driver-cuda*.rpm /run/build-inputs/kmod-nvidia-*.rpm && \
    dnf5 clean all && \
    rm -rf /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/* /var/cache/*

# 2. Instalação mínima do GNOME
RUN dnf5 install gnome-shell --setopt=tsflags=nodocs --setopt=install_weak_deps=False -y && \
    dnf5 clean all && \
    rm -rfv /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 3. Instalação de pacotes adicionais
RUN grep -v '^#' /run/build-inputs/pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    grep -v '^#' /run/build-inputs/pacotes_desktop | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 clean all && \
    rm -rfv /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# Configurações finais e política de assinatura.
# Ficam depois dos passos pesados para não invalidar o cache do NVIDIA/GNOME.
COPY config/ /run/build-inputs/config/
COPY security/ /run/build-inputs/security/

# 4. Configurações, links do sistema e política de assinatura
RUN test -f /run/build-inputs/security/cosign.pub || \
      { echo "ERRO: crie security/cosign.pub com 'cosign generate-key-pair'"; exit 1; } && \
    install -Dm644 /run/build-inputs/config/nvidia/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    install -Dm644 /run/build-inputs/config/system/locale.conf /etc/locale.conf && \
    install -Dm644 /run/build-inputs/config/system/vconsole.conf /etc/vconsole.conf && \
    install -Dm644 /run/build-inputs/config/system/zram-generator.conf /etc/systemd/zram-generator.conf && \
    install -Dm644 /run/build-inputs/config/flatpak/flatpaks.preinstall /usr/share/flatpak/preinstall.d/flatpaks.preinstall && \
    install -Dm644 /run/build-inputs/config/systemd/post-install.service /usr/lib/systemd/system/post-install.service && \
    install -Dm644 /run/build-inputs/config/systemd/post-install.timer /usr/lib/systemd/system/post-install.timer && \
    install -Dm644 /run/build-inputs/security/policy.json /etc/containers/policy.json && \
    install -Dm644 /run/build-inputs/security/registries.d/ghcr.yaml /etc/containers/registries.d/ghcr.yaml && \
    install -Dm644 /run/build-inputs/security/cosign.pub /etc/pki/containers/bootc-gnome.pub && \
    mkdir -vp /var/opt /var/usrlocal && \
    rm -rfv /opt /usr/local && \
    ln -vrs /var/opt /opt && \
    ln -vrs /var/usrlocal /usr/local && \
    systemctl enable post-install.timer spice-vdagentd.service && \
    systemctl mask systemd-remount-fs.service akmods-keygen@akmods-keygen.service && \
    systemctl mask malcontent-timerd.service && \
    if command -v restorecon >/dev/null 2>&1; then restorecon -RFv /etc/containers /etc/pki/containers; fi && \
    rm -rf /run/build-inputs /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 5. Validação do bootc
RUN bootc container lint
