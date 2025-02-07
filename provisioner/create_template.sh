#!/bin/bash

# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"  # Assurez-vous que ce pool existe !
POOL_TEMPLATE="template"   # Le pool auquel la VM doit être ajoutée
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
IMAGE_URL="https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/freebsd/14.2/2024-12-08/zfs/freebsd-14.2-zfs-2024-12-08.qcow2"
SNIPPETS_DIR="/var/lib/vz/snippets"  # Répertoire contenant les fichiers Cloud-Init

# Créez l'ISO Cloud-Init ici
cloud-init init --config-file=user-data --meta-data=meta-data --output-dir=/tmp/cloud-init-iso

# Création du template avec l'image FreeBSD
create_template() {
    local id=$1
    local name=$2
    local url=$3
    local img_file=$(basename "$url")

    # Vérifier si l'image est compressée en .xz
    if [[ "$img_file" == *.xz ]]; then
        local img_uncompressed="${img_file%.xz}"  # Supprime l'extension .xz
    else
        local img_uncompressed="$img_file"
    fi

    # Création de la VM sans disque
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single --bios seabios

    # Importer l'image dans le stockage local-lvm
    qm importdisk "$id" "${TEMPLATE_DIR}/${name}/${img_uncompressed}" "$STORAGE_POOL"

    # Lier le disque importé à la VM
    qm set "$id" --scsi0 "${STORAGE_POOL}:vm-${id}-disk-0"

    # Redimensionner le disque
    qm disk resize "$id" scsi0 "$DISK_SIZE"

    # Configurer l'ordre de démarrage
    qm set "$id" --boot order=scsi0 --bios seabios

    # Configuration des ressources de la VM
    qm set "$id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Ajouter l'ISO Cloud-Init
    qm set "$id" --ide2 "$STORAGE_POOL:/tmp/cloud-init-iso/cloud-init.iso,media=cdrom"

    # Activer l'agent QEMU
    qm set "$id" --agent enabled=1

    # Appliquer la configuration Cloud-Init
    qm set "$id" --cicustom "user=snippets/user-data,meta=snippets/meta-data"

    # Marquer cette VM comme un template
    qm template "$id"

    # Ajouter la VM au pool "template"
    pvesh set /pools/"$POOL_TEMPLATE" -vms "$id"

    echo "Fin de création du template $name et ajout au pool $POOL_TEMPLATE"
}

create_template 9999 "freebsd-14-cloudinit" "$IMAGE_URL"

echo "Fin de création du paramétrage de base de Proxmox avec le template FreeBSD 14.2"
