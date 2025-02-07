#!/bin/bash

# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"  # Assurez-vous que ce pool existe !
POOL_TEMPLATE="template"   # Le pool auquel la VM doit être ajoutée
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="10G"
CLOUDINIT_DISK="snippets:snippets/user-data"  # Correction du chemin CloudInit
IMAGE_URL="https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/freebsd/14.2/2024-12-08/zfs/freebsd-14.2-zfs-2024-12-08.qcow2"
SNIPPETS_DIR="/var/lib/vz/snippets"  # Répertoire contenant les fichiers Cloud-Init

# Vérifier que le répertoire des snippets existe
if [ ! -d "$SNIPPETS_DIR" ]; then
    echo "Création du répertoire des snippets : $SNIPPETS_DIR"
    mkdir -p "$SNIPPETS_DIR"
    chmod 755 "$SNIPPETS_DIR"
fi

# Vérifier si le pool "template" existe, sinon le créer
if ! pvesh get /pools | grep -q "\"$POOL_TEMPLATE\""; then
    echo "Création du pool '$POOL_TEMPLATE'..."
    pvesh create /pools -poolid "$POOL_TEMPLATE"
fi

# Fonction pour créer le template et l'ajouter au pool "template"
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

    # Vérifier si la VM existe déjà
    if qm list | awk '{print $1}' | grep -q "^$id$"; then
        echo "La VM $id existe déjà, annulation de la création."
        return
    fi

    echo "Création du template $name"

    # Création d'un répertoire pour le template
    mkdir -p "$TEMPLATE_DIR/$name"
    cd "$TEMPLATE_DIR/$name" || exit

    # Télécharger l'image depuis l'URL officielle
    if [ ! -f "$img_file" ]; then
        echo "Téléchargement de l'image FreeBSD CloudInit..."
        wget -q --show-progress "$url" -O "$img_file"
        if [ $? -ne 0 ]; then
            echo "Erreur : Échec du téléchargement de l’image !"
            exit 1
        fi
    else
        echo "L'image FreeBSD existe déjà, pas besoin de télécharger."
    fi

    # Décompression de l'image si nécessaire
    if [[ "$img_file" == *.xz ]]; then
        echo "Décompression de l'image..."
        xz -d "$img_file"
    fi

    # Création de la VM sans disque
    qm create "$id" --name "$name" --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single --bios seabios

    # Importer l'image dans le stockage local-lvm
    echo "Importation de l'image disque dans Proxmox..."
    qm importdisk "$id" "${TEMPLATE_DIR}/${name}/${img_uncompressed}" "$STORAGE_POOL"

    # Lier le disque importé à la VM
    qm set "$id" --scsi0 "${STORAGE_POOL}:vm-${id}-disk-0"

    # Redimensionner le disque
    qm disk resize "$id" scsi0 "$DISK_SIZE"

    # Configuration de l'ordre de démarrage pour la VM
    qm set "$id" --boot order=scsi0 --bios seabios

    # Configuration des ressources de la VM
    qm set "$id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Ajouter le disque Cloud-Init pour la configuration
    qm set "$id" --ide2 "$CLOUDINIT_DISK,media=cdrom"

    # Activer l'agent QEMU (important pour Cloud-Init)
    qm set "$id" --agent enabled=1

    # Créer le fichier user-data Cloud-Init (configuration utilisateur et réseau)
    cat <<EOF > "$SNIPPETS_DIR/user-data"
#cloud-config
hostname: $name
users:
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo
    lock_passwd: false
    passwd: \$6\$rounds=4096\$SalTovPfoBlv\$GlnrwVfg0hl0yJcO69u6KYVjNcxU.GQCGzgmvDZ6Q3k0SeJt9N4tYOuAI3V0mADceoa2F4lg5pZj6cZWZYoeuQ==  # Mot de passe crypté (par exemple, admin/admin)
timezone: Europe/Paris

# Réseaux
network:
  version: 2
  ethernets:
    vtnet0:
      dhcp4: true
EOF

    # Appliquer le fichier Cloud-Init user-data
    qm set "$id" --cicustom "user=snippets/user-data"

    # Créer le fichier meta-data (ID et nom de la machine)
    echo "instance-id: $id" > "$SNIPPETS_DIR/meta-data"
    echo "local-hostname: $name" >> "$SNIPPETS_DIR/meta-data"

    # Appliquer le fichier meta-data
    qm set "$id" --cicustom "meta=snippets/meta-data"

    # Marquer cette VM comme un template
    qm template "$id"

    # Ajouter la VM au pool "template"
    pvesh set /pools/"$POOL_TEMPLATE" -vms "$id"

    echo "Fin de création du template $name et ajout au pool $POOL_TEMPLATE"
}

# Création du template avec FreeBSD CloudInit officiel
create_template 9999 "freebsd-14-cloudinit" "$IMAGE_URL"

echo "Fin de création du paramétrage de base de Proxmox avec le template FreeBSD 14.2"
