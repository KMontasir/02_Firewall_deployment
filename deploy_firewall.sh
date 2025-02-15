#!/bin/bash

# Définition des variables
TEMPLATE_ID=14000  # ID du template de base à cloner
STORAGE_POOL="local-lvm-vm"  # Stockage des disques des VMs
CLOUDINIT_STORAGE="snippets" # Stockage des fichiers Cloud-Init
POOL_NAME="pare-feu"         # Pool où les VMs seront ajoutées
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="16G"  # Taille du disque pour chaque VM clonée
SNIPPETS_DIR="/var/lib/vz/snippets/snippets/"  # Dossier pour stocker les fichiers Cloud-Init
CLOUDINIT_DISK="${CLOUDINIT_STORAGE}:cloudinit"  # Disque Cloud-Init

# Liste des VMs et fichiers Cloud-Init
OPNSENSE_VMS=("Firewall-Relais" "Firewall-Expose" "Firewall-Interne")
VM_IDS=(4001 4002 4003)
CLOUDINIT_FILES=( 
  "firewall-relais.yaml"
  "firewall-expose.yaml"
  "firewall-interne.yaml"
)

NETWORK_CONFIGS=(
  "vmbr0,vmbr1,vmbr4"
  "vmbr1,vmbr2,vmbr4"
  "vmbr2,vmbr3,vmbr4"
)

# Fonction pour ajouter un fichier Cloud-Init en tant que snippet
add_cloudinit_snippet() {
    local source_file="./cloud_config/$1"
    local dest_file="${SNIPPETS_DIR}$1"

    if [ ! -f "$source_file" ]; then
        echo "$(date) - Erreur: Le fichier Cloud-Init $source_file n'existe pas."
        exit 1
    fi

    echo "$(date) - Copie du fichier Cloud-Init $source_file vers $dest_file..."
    cp "$source_file" "$dest_file"
    chmod 644 "$dest_file"

    # Vérification après copie
    if [ ! -f "$dest_file" ]; then
        echo "$(date) - Erreur: Le fichier Cloud-Init $dest_file n'a pas été copié correctement."
        exit 1
    fi
}

# Fonction pour créer une VM, configurer le Cloud-Init et la démarrer
create_and_configure_vm() {
    local vm_id=$1
    local name=$2
    local network_config=$3
    local cloudinit_file=$4

    echo "$(date) - Création de la VM $name à partir du template ID $TEMPLATE_ID"

    # Cloner la VM à partir du template
    qm clone "$TEMPLATE_ID" "$vm_id" --name "$name" --full --storage "$STORAGE_POOL"
    if [ $? -ne 0 ]; then
        echo "$(date) - Erreur lors du clonage de la VM $name"
        exit 1
    fi

    # Ajouter la VM au pool
    pvesh set /pools/"$POOL_NAME" --vm "$vm_id"

    # Configurer CPU, RAM et disque
    qm set "$vm_id" --cpu host --cores "$CORES" --memory "$MEMORY"
    qm resize "$vm_id" scsi0 "$DISK_SIZE"

    # Configurer les interfaces réseau
    IFS=',' read -r -a networks <<< "$network_config"
    qm set "$vm_id" --net0 virtio,bridge="${networks[0]},firewall=1"
    [ -n "${networks[1]}" ] && qm set "$vm_id" --net1 virtio,bridge="${networks[1]},firewall=1"
    [ -n "${networks[2]}" ] && qm set "$vm_id" --net2 virtio,bridge="${networks[2]},firewall=1"

    # Ajouter le disque Cloud-Init
    qm set "$vm_id" --ide2 "$CLOUDINIT_DISK,media=cdrom"

    # Ajouter le fichier Cloud-Init comme snippet
    add_cloudinit_snippet "$cloudinit_file"
    qm set "$vm_id" --cicustom "user=${CLOUDINIT_STORAGE}:snippets/${cloudinit_file}"

    echo "$(date) - VM $name clonée et ajoutée au pool '$POOL_NAME' avec Cloud-Init."
    sleep 5  # Attente de 5 secondes

    # Démarrer la VM
    qm start "$vm_id"
    echo "$(date) - VM $name démarrée avec Cloud-Init appliqué."
}

# Création et configuration des VMs
for i in "${!OPNSENSE_VMS[@]}"; do
    create_and_configure_vm "${VM_IDS[$i]}" "${OPNSENSE_VMS[$i]}" "${NETWORK_CONFIGS[$i]}" "${CLOUDINIT_FILES[$i]}"
done

echo "$(date) - Toutes les VMs OPNsense sont créées et configurées avec Cloud-Init."
