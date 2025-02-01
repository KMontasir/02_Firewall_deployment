#!/bin/bash
# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
CLOUDINIT_DISK="${STORAGE_POOL}:cloudinit"
IMAGE_URL="https://raw.github.com/KMontasir/ressources/refs/heads/main/deployment/vm/image/template_freebsd.qcow2"

# Création de répertoires et de l'arborescence de travail
mkdir -p "$TEMPLATE_DIR"
cd "$TEMPLATE_DIR"

# Fonction pour créer un template
create_template() {
    local id=$1
    local name=$2
    local url=$3
    local img_file=$(basename "$url")
    echo "Création du template $name"
    
    # Création d'un répertoire pour chaque template
    mkdir -p "$name"
    cd "$name"
    
    # Télécharger l'image depuis l'URL
    wget "$url" -O "$img_file"
    
    # Créer la machine virtuelle (id de la VM, nom, réseau, etc.)
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single
    
    # Importer l'image dans le stockage local
    qm importdisk "$id" "${TEMPLATE_DIR}/${name}/${img_file}" "$STORAGE_POOL"
    
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
    
    # Activer l'agent QEMU
    qm set "$id" --agent enabled=1
    
    # Marquer cette VM comme un template
    qm template "$id"
    
    cd ..  # Revenir au répertoire précédent
    echo "Fin de création du template $name"
}

# Création du template depuis l'URL GitHub
create_template 9999 "freebsd.template" "$IMAGE_URL"

echo "Fin de création du paramétrage de base de proxmox avec le template FreeBSD"
