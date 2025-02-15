#!/bin/bash

# Définition des variables
TEMPLATE_DIR="/var/lib/vz/snippets/images"
STORAGE_POOL="local-lvm-vm"  # Stockage des disques des VMs
CLOUDINIT_STORAGE="snippets" # Stockage des fichiers Cloud-Init
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
SNIPPETS_DIR="/var/lib/vz/snippets/snippets"
CLOUDINIT_DISK="${CLOUDINIT_STORAGE}:cloudinit"

# Création de répertoires et de l'arborescence de travail
mkdir -p "$TEMPLATE_DIR"
cd "$TEMPLATE_DIR"

# Vérification et création du répertoire Cloud-Init si nécessaire
if [ ! -d "$SNIPPETS_DIR" ]; then
    mkdir -p "$SNIPPETS_DIR"
    echo "Répertoire $SNIPPETS_DIR créé."
else
    echo "Le répertoire $SNIPPETS_DIR existe déjà."
fi

# Fonction pour créer un template
create_template() {
    local id=$1
    local name=$2
    local url=$3
    local img_file=$(basename "$url")

    echo "Création du template $name"
    mkdir -p "$name"
    cd "$name"
    wget "$url"

    # Création de la VM avec stockage sur local-lvm-vm
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single
    qm set "$id" --scsi0 "${STORAGE_POOL}:0,iothread=1,backup=off,format=qcow2,import-from=${TEMPLATE_DIR}/${name}/${img_file}"
    qm disk resize "$id" scsi0 "$DISK_SIZE"
    qm set "$id" --boot order=scsi0
    qm set "$id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Ajout du disque Cloud-Init
    qm set "$id" --ide2 "$CLOUDINIT_DISK",media=cdrom

    # Vérifier si les fichiers Cloud-Init existent avant de les ajouter
    if [ -f "$SNIPPETS_DIR/user-data" ] && [ -f "$SNIPPETS_DIR/network-config" ] && [ -f "$SNIPPETS_DIR/meta-data" ]; then
        qm set "$id" --cicustom "user=${CLOUDINIT_STORAGE}:snippets/user-data,network=${CLOUDINIT_STORAGE}:snippets/network-config,meta=${CLOUDINIT_STORAGE}:snippets/meta-data"
        echo "Fichiers Cloud-Init ajoutés à la VM $id"
    else
        echo "Attention : Un ou plusieurs fichiers Cloud-Init manquent dans $SNIPPETS_DIR !"
    fi

    qm set "$id" --agent enabled=1
    qm template "$id"

    cd ..
    echo "Fin de création du template $name"
}

# Création des templates
create_template 13000 "freebsd.template" "https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/freebsd/14.2/2024-12-08/zfs/freebsd-14.2-zfs-2024-12-08.qcow2"
create_template 11000 "debian.template" "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
create_template 12000 "archlinux.template" "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"

# Ajout des templates au pool "template"
pvesh set /pools/template --vm 13000
pvesh set /pools/template --vm 11000
pvesh set /pools/template --vm 12000

echo "Fin de création des templates sur Proxmox"
