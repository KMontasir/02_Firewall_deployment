#!/bin/bash

# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"
SNIPPET_STORAGE="local"  # Modifier si nécessaire
CORES=2
MEMORY=2048
DISK_SIZE="20G"
CLOUDINIT_DISK="${STORAGE_POOL}:cloudinit"

# Variables pour les VMs OPNsense
OPNSENSE_VMS=("opnsense1" "opnsense2" "opnsense3")
VM_IDS=(1001 1002 1003)

# Chemins vers les fichiers Cloud-init spécifiques
CLOUDINIT_FILES=(
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-1.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-2.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-3.yml"
)

# Configuration des interfaces réseau pour chaque VM
NETWORK_CONFIGS=(
  "vmbr0,vmbr1,vmbr4"   # 1er firewall
  "vmbr1,vmbr2,vmbr4"   # 2ème firewall
  "vmbr2,vmbr3,vmbr4"   # 3ème firewall
)

# Vérification et création du stockage snippets si nécessaire
if ! pvesm status | grep -q "$SNIPPET_STORAGE"; then
    echo "Création du stockage '$SNIPPET_STORAGE' pour les snippets..."
    pvesm add dir "$SNIPPET_STORAGE" --path /var/lib/vz --content snippets
fi

# Vérification et création du dossier snippets si nécessaire
SNIPPET_PATH="/var/lib/vz/snippets"
if [ ! -d "$SNIPPET_PATH" ]; then
    echo "Création du répertoire snippets..."
    mkdir -p "$SNIPPET_PATH"
    chmod 755 "$SNIPPET_PATH"
fi

# Fonction pour ajouter un fichier Cloud-init en tant que snippet
add_cloudinit_snippet() {
    local file_path=$1
    local snippet_name=$(basename "$file_path")

    if [ ! -f "$file_path" ]; then
        echo "Erreur: Le fichier Cloud-init $file_path n'existe pas."
        exit 1
    fi

    echo "Ajout du fichier Cloud-init $file_path en tant que snippet..."
    cp "$file_path" "$SNIPPET_PATH/$snippet_name"
    chmod 644 "$SNIPPET_PATH/$snippet_name"
}

# Fonction pour cloner une VM
clone_vm() {
    local vm_id=$1
    local name=$2
    local network_config=$3
    local template_id=9999  # ID du template à cloner

    echo "Clonage de la VM $name à partir du template ID $template_id"

    # Vérifier si la VM existe déjà, la supprimer si nécessaire
    if qm status "$vm_id" &>/dev/null; then
        echo "La VM $vm_id existe déjà, suppression en cours..."
        qm stop "$vm_id" --skiplock
        qm destroy "$vm_id" --destroy-unreferenced-disks 1
        qm wait "$vm_id"
    fi

    # Cloner la VM à partir du template
    qm clone "$template_id" "$vm_id" --name "$name" --full --storage "$STORAGE_POOL"

    # Configurer les ressources de la VM (CPU, RAM, etc.)
    qm set "$vm_id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Configurer le disque dur
    qm set "$vm_id" --scsi0 "${STORAGE_POOL}:vm-${vm_id}-disk-0,iothread=1,backup=off"

    # Configurer les cartes réseau en fonction du réseau spécifique
    IFS=',' read -r -a networks <<< "$network_config"
    qm set "$vm_id" --net0 virtio,bridge="${networks[0]},firewall=1"
    qm set "$vm_id" --net1 virtio,bridge="${networks[1]},firewall=1"
    qm set "$vm_id" --net2 virtio,bridge="${networks[2]},firewall=1"

    # Activer CloudInit
    qm set "$vm_id" --ide2 "$CLOUDINIT_DISK,media=cdrom"
    qm set "$vm_id" --ciuser root --cipassword "your_password" --searchdomain local --nameserver 8.8.8.8

    # Démarrer la VM clonée
    qm start "$vm_id"
    echo "VM $name clonée et démarrée."
    sleep 5  # Attendre que la VM démarre pour appliquer Cloud-init
}

# Fonction pour appliquer un fichier Cloud-init spécifique
apply_cloudinit() {
    local vm_id=$1
    local cloudinit_file=$2
    local snippet_name=$(basename "$cloudinit_file")

    echo "Application du fichier Cloud-init pour la VM $vm_id"

    # Vérifier et ajouter le fichier Cloud-init en tant que snippet
    add_cloudinit_snippet "$cloudinit_file"

    # Associer le fichier Cloud-init à la VM
    qm set "$vm_id" --cicustom "user=$SNIPPET_STORAGE:snippets/$snippet_name"

    # Redémarrer la VM pour appliquer Cloud-init
    qm stop "$vm_id"
    sleep 2
    qm start "$vm_id"

    echo "Cloud-init appliqué à la VM $vm_id."
}

# Création des VMs OPNsense en clonant le template et en appliquant Cloud-init
for i in "${!OPNSENSE_VMS[@]}"; do
    clone_vm "${VM_IDS[$i]}" "${OPNSENSE_VMS[$i]}" "${NETWORK_CONFIGS[$i]}"
    apply_cloudinit "${VM_IDS[$i]}" "${CLOUDINIT_FILES[$i]}"
done

echo "Toutes les VMs OPNsense ont été clonées et configurées avec Cloud-init."
