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
    chmod 644 "$SNIPPET_PATH/$snippet_name"

    # Vérification
    ls -la "$SNIPPET_PATH"
}

# Fonction pour vérifier si un fichier YAML est valide
validate_yaml() {
    local file_path=$1
    if ! python3 -c 'import yaml, sys; yaml.safe_load(sys.stdin)' < "$file_path" > /dev/null; then
        echo "$(date) - Erreur: Le fichier Cloud-init $file_path est invalide."
        exit 1
    fi
}

# Fonction pour cloner une VM
clone_vm() {
    local vm_id=$1
    local name=$2
    local network_config=$3

    echo "$(date) - Clonage de la VM $name à partir du template ID $TEMPLATE_ID"

    # Supprimer la VM si elle existe déjà
    if qm list | grep -q "^$vm_id"; then
        echo "$(date) - La VM $vm_id existe déjà, suppression..."
        qm stop "$vm_id" --skiplock
        sleep 5
        qm destroy "$vm_id" --destroy-unreferenced-disks 1
    fi

    # Cloner la VM
    qm clone "$TEMPLATE_ID" "$vm_id" --name "$name" --full --storage "$VM_STORAGE"

    # Ajouter au pool sans écraser les autres VMs
    VM_IDS_LIST=$(pvesh get /pools/"$POOL_NAME" | grep -o '"vms":[^]]*' | sed 's/"vms":\[\([^]]*\)\]/\1/')
    VM_IDS_LIST="$VM_IDS_LIST,$vm_id"
    pvesh set /pools/"$POOL_NAME" -vms "$VM_IDS_LIST"

    # Configurer CPU, RAM, disque
    qm set "$vm_id" --cpu host --cores "$CORES" --memory "$MEMORY"
    qm resize "$vm_id" scsi0 "$DISK_SIZE"

    # Configurer les interfaces réseau
    IFS=',' read -r -a networks <<< "$network_config"
    qm set "$vm_id" --net0 virtio,bridge="${networks[0]},firewall=1"
    [ -n "${networks[1]}" ] && qm set "$vm_id" --net1 virtio,bridge="${networks[1]},firewall=1"
    [ -n "${networks[2]}" ] && qm set "$vm_id" --net2 virtio,bridge="${networks[2]},firewall=1"

    # Activer CloudInit
    qm set "$vm_id" --ide2 "$CLOUDINIT_DISK,media=cdrom"

    echo "$(date) - VM $name clonée et ajoutée au pool '$POOL_NAME'."
    sleep 5
}

# Fonction pour appliquer Cloud-init
apply_cloudinit() {
    local vm_id=$1
    local cloudinit_file=$2
    local snippet_name=$(basename "$cloudinit_file")

    echo "$(date) - Application du fichier Cloud-init pour la VM $vm_id"
    
    # Valider et ajouter le fichier Cloud-init
    validate_yaml "$cloudinit_file"
    add_cloudinit_snippet "$cloudinit_file"

    qm set "$vm_id" --cicustom "user=snippets:snippets/$snippet_name"
    qm start "$vm_id"
    echo "$(date) - Cloud-init appliqué à la VM $vm_id."
}

# Création et configuration des VMs
for i in "${!OPNSENSE_VMS[@]}"; do
    clone_vm "${VM_IDS[$i]}" "${OPNSENSE_VMS[$i]}" "${NETWORK_CONFIGS[$i]}"
    apply_cloudinit "${VM_IDS[$i]}" "${CLOUDINIT_FILES[$i]}"
done

echo "$(date) - Toutes les VMs OPNsense sont créées et configurées avec Cloud-init."
