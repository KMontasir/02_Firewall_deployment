#!/bin/bash

# Définition des variables
STORAGE_POOL="local-lvm-vm"  # Stockage des disques des VMs
CLOUDINIT_STORAGE="snippets" # Stockage des fichiers Cloud-Init
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="16G"  # Taille du disque pour le clone
SNIPPETS_DIR="/var/lib/vz/snippets/snippets/"  # Dossier pour stocker les fichiers Cloud-Init
CLOUDINIT_DISK="${CLOUDINIT_STORAGE}:cloudinit"

# Vérification du nombre d'arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <fichier_csv>"
    exit 1
fi

# Fichier CSV contenant les informations des clones
CSV_FILE=$1

# Vérifier si le fichier existe
if [ ! -f "$CSV_FILE" ]; then
    echo "Erreur : Le fichier $CSV_FILE n'existe pas."
    exit 1
fi

# Fonction pour créer une VM
create_vm() {
    TEMPLATE_ID=$1
    CLONE_ID=$2
    VM_NAME=$3
    CLOUDINIT_FILE=$4

    echo "Création de la VM $VM_NAME à partir du template ID $TEMPLATE_ID..."

    # Vérifier si le template existe
    if ! qm status "$TEMPLATE_ID" > /dev/null 2>&1; then
        echo "Erreur : Le template avec l'ID $TEMPLATE_ID n'existe pas."
        return 1
    fi

    # Vérifier si le fichier Cloud-Init existe dans le dossier source
    SOURCE_CLOUDINIT="./cloud_config/${CLOUDINIT_FILE}"
    if [ ! -f "$SOURCE_CLOUDINIT" ]; then
        echo "Erreur : Le fichier YAML ${CLOUDINIT_FILE} est introuvable !"
        return 1
    fi

    # Copier le fichier Cloud-Init dans le bon dossier Proxmox
    DEST_CLOUDINIT="${SNIPPETS_DIR}${CLOUDINIT_FILE}"
    echo "Copie du fichier Cloud-Init vers ${DEST_CLOUDINIT}..."
    cp "$SOURCE_CLOUDINIT" "$DEST_CLOUDINIT"

    # Cloner le template
    qm clone "$TEMPLATE_ID" "$CLONE_ID" --name "$VM_NAME" --full true --storage "$STORAGE_POOL"

    # Configurer la VM
    qm set "$CLONE_ID" --cpu host --cores "$CORES" --memory "$MEMORY"
    qm set "$CLONE_ID" --net0 virtio,bridge="$BRIDGE"
    qm resize "$CLONE_ID" scsi0 "$DISK_SIZE"

    # Ajout du disque Cloud-Init
    qm set "$CLONE_ID" --ide2 "$CLOUDINIT_DISK",media=cdrom

    # Importation du fichier Cloud-Init dans Proxmox
    echo "Importation du fichier Cloud-Init..."
    qm set "$CLONE_ID" --cicustom "user=${CLOUDINIT_STORAGE}:snippets/${CLOUDINIT_FILE}"

    # Ajouter la VM au pool "template"
    pvesh set /pools/template --vm "$CLONE_ID"

    # Démarrer la VM
    echo "Démarrage de la VM $VM_NAME..."
    qm start "$CLONE_ID"
}

# Lecture du fichier CSV et création des VMs
declare -a VM_IDS
declare -a VM_NAMES

echo "Création des VMs..."

while IFS=',' read -r TEMPLATE_ID CLONE_ID VM_NAME CLOUDINIT_FILE; do
    # Ignorer la première ligne si c'est un en-tête
    if [[ "$TEMPLATE_ID" == "TEMPLATE_ID" ]]; then
        continue
    fi

    # Créer la VM
    create_vm "$TEMPLATE_ID" "$CLONE_ID" "$VM_NAME" "$CLOUDINIT_FILE"

    # Ajouter l'ID et le nom de la VM à la liste pour le clonage
    VM_IDS+=("$CLONE_ID")
    VM_NAMES+=("$VM_NAME")

done < "$CSV_FILE"

echo "Toutes les VMs ont été créées."

# Demander à l'utilisateur si les VMs sont prêtes pour le clonage
read -p "Les VMs sont-elles prêtes à être clonées ? (y/n) " user_response

if [[ "$user_response" != "y" ]]; then
    echo "Clonage annulé. Vous pouvez reprendre le processus plus tard."
    exit 0
fi

# Arrêt des VMs avant clonage
echo "Arrêt des VMs avant clonage..."

for CLONE_ID in "${VM_IDS[@]}"; do
    echo "Arrêt de la VM ID $CLONE_ID..."
    qm stop "$CLONE_ID"
    sleep 5  # Attente de 5 secondes avant de passer au clonage
done

# Clonage des VMs
echo "Début du clonage des VMs..."

for i in "${!VM_IDS[@]}"; do
    CLONE_ID="${VM_IDS[$i]}"
    VM_NAME="${VM_NAMES[$i]}"

    # Cloner la VM
    echo "Clonage de la VM $VM_NAME..."
    qm clone "$CLONE_ID" "$CLONE_ID" --name "${VM_NAME}-clone" --full true --storage "$STORAGE_POOL"
    echo "Clonage de la VM $VM_NAME terminé."
done

echo "Tous les clones ont été créés."
