#!/bin/bash

# Variables
TEMPLATE_ID=9999
VM_STORAGE="local-lvm-vm"
SNIPPET_STORAGE="snippets"
POOL_NAME="pare-feu"
CORES=2
MEMORY=2048
DISK_SIZE="20G"
CLOUDINIT_DISK="${SNIPPET_STORAGE}:cloudinit"

# VMs et fichiers Cloud-Init
OPNSENSE_VMS=("template" "Firewall-Relais" "Firewall-Expose" "Firewall-Interne")
VM_IDS=(9998 1001 1002 1003)
CLOUDINIT_FILES=(
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-template.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-1.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-2.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-3.yml"
)
NETWORK_CONFIGS=(
  "vmbr0,vmbr1,vmbr4"
  "vmbr0,vmbr1,vmbr4"
  "vmbr1,vmbr2,vmbr4"
  "vmbr2,vmbr3,vmbr4"
)

# Création du pool si nécessaire
if ! pvesh get /pools | grep -q "\"$POOL_NAME\""; then
    echo "$(date) - Création du pool '$POOL_NAME'..."
    pvesh create /pools -poolid "$POOL_NAME"
fi

# Création du stockage snippets si nécessaire
if ! pvesm status | grep -q "$SNIPPET_STORAGE"; then
    echo "$(date) - Création du stockage '$SNIPPET_STORAGE' pour les snippets..."
    pvesm add dir "$SNIPPET_STORAGE" --path /var/lib/vz --content snippets
fi

# Vérification et création du dossier snippets
SNIPPET_PATH="/var/lib/vz/snippets"
mkdir -p "$SNIPPET_PATH"
chmod 755 "$SNIPPET_PATH"

# Fonction pour ajouter un fichier Cloud-init en snippet
add_cloudinit_snippet() {
    local file_path=$1
    local snippet_name=$(basename "$file_path")

    if [ ! -f "$file_path" ]; then
        echo "$(date) - Erreur: Le fichier Cloud-init $file_path n'existe pas."
        exit 1
    fi

    echo "$(date) - Ajout du fichier Cloud-init $file_path en tant que snippet..."
    cp "$file_path" "$SNIPPET_PATH/$snippet_name"
    chmod
