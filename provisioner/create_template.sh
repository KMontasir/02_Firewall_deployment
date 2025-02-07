#!/bin/bash

# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm-vm"  # Le pool de stockage pour le template
POOL_TEMPLATE="template"     # Le pool dans lequel la VM doit être ajoutée
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
CLOUDINIT_DISK="local:cloudinit"  # Le stockage CloudInit reste sur 'local'
IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/14.1-RELEASE/amd64/Latest/FreeBSD-14.1-RELEASE-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz"
SNIPPETS_DIR="/var/lib/vz/snippets"  # Répertoire des snippets, mais nous allons configurer sans les fichiers manquants

# Vérifier que le répertoire des snippets existe
if [ ! -d "$SNIPPETS_DIR" ]; then
    echo "Erreur : Le répertoire des snippets ($SNIPPETS_DIR) n'existe pas."
    exit 1
fi

# Fonction pour créer le template et l'ajouter au pool "template"
create_template() {
    local id=$1
    local name=$2
    local url=$3
    local img_file=$(basename "$url")
    local img_uncompressed="${img_file%.xz}"  # Supprime l'extension .xz

    # Vérifier si la VM existe déjà
    if qm list | awk '{print $1}' | grep -q "^$id$"; then
        echo "La VM $id existe déjà, annulation de la création."
        return
    fi

    echo "Création du template $name"

    # Création d'un répertoire pour le template
    mkdir -p "$TEMPLATE_DIR/$name"
    cd "$TEMPLATE_DIR/$name"

    # Télécharger l'image depuis l'URL officielle
    echo "Téléchargement de l'image FreeBSD CloudInit..."
    wget -q --show-progress "$url" -O "$img_file"
    if [ $? -ne 0 ]; then
        echo "Erreur : Échec du téléchargement de l’image !"
        exit 1
    fi

    # Décompression de l'image
    echo "Décompression de l'image..."
    xz -d "$img_file"

    # Création de la VM sans disque (id de la VM, nom, réseau, etc.) et utiliser seabios pour désactiver l'UEFI
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single --bios seabios

    # Importer l'image dans le stockage local-lvm-vm
    echo "Importation de l'image disque dans Proxmox..."
    qm importdisk "$id" "${TEMPLATE_DIR}/${name}/${img_uncompressed}" "$STORAGE_POOL"

    # Lier le disque importé à la VM
    qm set "$id" --scsi0 "${STORAGE_POOL}:vm-${id}-disk-0"

    # Redimensionner le disque
    qm disk resize "$id" scsi0 "$DISK_SIZE"

    # Configuration de l'ordre de démarrage pour la VM en utilisant le BIOS
    qm set "$id" --boot order=scsi0 --bios seabios

    # Configuration des ressources de la VM
    qm set "$id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Ajouter le disque CloudInit pour la configuration
    qm set "$id" --ide2 "$CLOUDINIT_DISK,media=cdrom"

    # Activer l'agent QEMU (important pour CloudInit)
    qm set "$id" --agent enabled=1

    # Marquer cette VM comme un template
    qm template "$id"  # Conversion de la VM en template

    # Ajouter la VM au pool "template"
    pvesh set /pools/"$POOL_TEMPLATE" -vms "$id"

    cd ..  # Revenir au répertoire précédent
    echo "Fin de création du template $name et ajout au pool $POOL_TEMPLATE"
}

# Création du template avec FreeBSD CloudInit officiel
create_template 9999 "freebsd-14-cloudinit" "$IMAGE_URL"

echo "Fin de création du paramétrage de base de Proxmox avec le template FreeBSD 14.1"
