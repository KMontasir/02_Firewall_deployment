#!/bin/bash
# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
CLOUDINIT_DISK="${STORAGE_POOL}:cloudinit"
IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/14.1-RELEASE/amd64/Latest/FreeBSD-14.1-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz"

# Création de répertoires et de l'arborescence de travail
mkdir -p "$TEMPLATE_DIR"
cd "$TEMPLATE_DIR"

# Fonction pour créer un template
create_template() {
    local id=$1
    local name=$2
    local url=$3
    local img_file=$(basename "$url")
    local img_uncompressed="${img_file%.xz}"  # Supprime l'extension .xz

    echo "Création du template $name"

    # Création d'un répertoire pour le template
    mkdir -p "$name"
    cd "$name"

    # Télécharger l'image depuis l'URL officielle
    echo "Téléchargement de l'image FreeBSD CloudInit..."
    wget -q --show-progress "$url" -O "$img_file"

    # Décompression de l'image
    echo "Décompression de l'image..."
    xz -d "$img_file"

    # Création de la VM sans disque (id de la VM, nom, réseau, etc.)
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single

    # Importer l'image dans le stockage local
    echo "Importation de l'image disque dans Proxmox..."
    qm importdisk "$id" "${TEMPLATE_DIR}/${name}/${img_uncompressed}" "$STORAGE_POOL"

    # Lier le disque importé à la VM
    qm set "$id" --scsi0 "${STORAGE_POOL}:vm-${id}-disk-0"

    # Redimensionner le disque
    qm disk resize "$id" scsi0 "$DISK_SIZE"

    # Configuration de l'ordre de démarrage pour la VM
    qm set "$id" --boot order=scsi0

    # Configuration des ressources de la VM
    qm set "$id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Ajouter le disque CloudInit pour la configuration
    qm set "$id" --ide2 "$CLOUDINIT_DISK"

    # Activer l'agent QEMU (important pour CloudInit)
    qm set "$id" --agent enabled=1

    # Activer l'UEFI si nécessaire (FreeBSD peut en avoir besoin)
    qm set "$id" --bios ovmf --efidisk0 "$STORAGE_POOL:0,format=raw,efitype=4m"

    # Marquer cette VM comme un template
    qm template "$id"

    cd ..  # Revenir au répertoire précédent
    echo "Fin de création du template $name"
}

# Création du template avec FreeBSD CloudInit officiel
create_template 9999 "freebsd-14-cloudinit" "$IMAGE_URL"

echo "Fin de création du paramétrage de base de Proxmox avec le template FreeBSD 14.1"
