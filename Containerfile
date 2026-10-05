# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:45 AS builder
RUN dnf5 -y upgrade kernel* --refresh && \
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio, imagem final com driver NVIDIA versão 580 Negativo17
FROM quay.io/fedora/fedora-bootc:45 AS final

# 1. Configuração de repostórios e instalação de Kernel Extras + NVIDIA
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/ 
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/nvidia/ 
COPY 10-nvidia-args.toml nvidia-power.conf nvidia_packages /tmp/sysconfig/ 
RUN dnf5 -y upgrade --refresh && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install --setopt=tsflags=nodocs "kernel-modules-extra-${kver}" && \
    dnf5 download --destdir=/tmp/nvidia nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps --nosignature /tmp/nvidia/nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps --nosignature /tmp/nvidia/nvidia-driver-cuda*.rpm && \
    mv -v /tmp/sysconfig/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v /tmp/sysconfig/nvidia-power.conf /etc/modprobe.d/ && \
    grep -v '^#' /tmp/sysconfig/nvidia_packages | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 -y install /tmp/nvidia/kmod-nvidia-*.rpm && \
    rm -rf /tmp/nvidia && \
    dnf5 clean all && \
    rm -rf /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/* /var/cache/*

# 2. Instalação mínima do GNOME
RUN dnf5 install gnome-shell --setopt=tsflags=nodocs --setopt=install_weak_deps=False -y && \
    dnf5 clean all && \
    rm -rfv /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 3. Instalação de pacotes adicionais 
COPY pacotes_necessarios pacotes_desktop ./
RUN dnf5 install dnf-plugins-core -y && \
    dnf5 copr enable scottames/ghostty -y && \
    dnf5 install ghostty -y && \
    grep -v '^#' pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    grep -v '^#' pacotes_desktop | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 clean all && \
    rm -rfv /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 4. Configurações, scripts, links do sistema e tratamento de /opt e /usr/local
COPY locale.conf post-install.sh post-install.service zram-generator.conf vconsole.conf /tmp/sysconfig/
RUN mkdir -vp /var/opt /var/usrlocal /etc/sysusers.d /usr/lib/bootc/kargs.d /etc/modprobe.d && \
    rm -rfv /opt /usr/local && \
    ln -vrs /var/opt /opt && \
    ln -vrs /var/usrlocal /usr/local && \
    mv -v /tmp/sysconfig/zram-generator.conf /etc/systemd/ && \
    mv -v /tmp/sysconfig/vconsole.conf /etc/vconsole.conf && \
    mv -v /tmp/sysconfig/locale.conf /etc/locale.conf && \
    mv -v /tmp/sysconfig/post-install.sh /usr/bin/post-install.sh && \
    mv -v /tmp/sysconfig/post-install.service /usr/lib/systemd/system/post-install.service && \
    chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service spice-vdagentd.service && \
    systemctl mask systemd-remount-fs.service akmods-keygen@akmods-keygen.service && \
    systemctl mask NetworkManager-wait-online.service && \
    systemctl mask malcontent-timerd.service && \
    rm -rf /tmp/sysconfig /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 5. Validação do bootc
RUN bootc container lint
