#!/bin/bash
# Variables communes
TEMPLATE_DIR="/root/02_Firewall_deployment/cloud_init/cloud-version"
STORAGE_POOL="local-lvm"
CORES=2
MEMORY=2048
DISK_SIZE="20G"
CLOUDINIT_DISK="${STORAGE_POOL}:cloudinit"

# Variables pour les VMs OPNsense
OPNSENSE_VMS=("opnsense1" "opnsense2" "opnsense3")
VM_IDS=(1001 1002 1003)

# Chemins vers les fichiers Cloud-init spécifiques
CLOUDINIT_FILES=(
  "./cloud_init/cloud-init-firewall-1.yml"
  "./cloud_init/cloud-init-firewall-2.yml"
  "./cloud_init/cloud-init-firewall-3.yml"
)

# Configuration des interfaces réseau pour chaque VM
NETWORK_CONFIGS=(
  "vmbr0,vmbr1,vmbr4"   # 1er firewall
  "vmbr1,vmbr2,vmbr4"   # 2ème firewall
  "vmbr2,vmbr3,vmbr4"   # 3ème firewall
)

# Fonction pour cloner une VM
clone_vm() {
    local vm_id=$1
    local name=$2
    local template_name=$3
    local network_config=$4
    echo "Clonage de la VM $name à partir du template $template_name"

    # Vérifier si la VM existe déjà, la supprimer si nécessaire
    if qm status "$vm_id" &>/dev/null; then
        echo "La VM $vm_id existe déjà, suppression en cours..."
        qm stop "$vm_id" --skiplock
        qm destroy "$vm_id" --destroy-unreferenced-disks 1
    fi

    # Cloner la VM à partir du template
    qm clone 9999 "$vm_id" --name "$name" --full --storage "$STORAGE_POOL"

    # Configurer les ressources de la VM (CPU, RAM, etc.)
    qm set "$vm_id" --cpu host --cores "$CORES" --memory "$MEMORY"

    # Configurer le disque dur
    qm set "$vm_id" --scsi0 "${STORAGE_POOL}:vm-${vm_id}-disk-0,iothread=1,backup=off"

    # Supprimer l'ancien disque CloudInit avant d'en ajouter un nouveau
    qm set "$vm_id" --delete ide2
    qm set "$vm_id" --ide2 "$CLOUDINIT_DISK,media=cdrom"

    # Configurer les cartes réseau en fonction du réseau spécifique
    IFS=',' read -r -a networks <<< "$network_config"
    qm set "$vm_id" --net0 virtio,bridge="${networks[0]},firewall=1"
    qm set "$vm_id" --net1 virtio,bridge="${networks[1]},firewall=1"
    qm set "$vm_id" --net2 virtio,bridge="${networks[2]},firewall=1"

    # Activer CloudInit et définir les paramètres de base
    qm set "$vm_id" --ciuser root --cipassword "your_password" --searchdomain local --nameserver 8.8.8.8

    # Démarrer la VM clonée
    qm start "$vm_id"
    echo "VM $name clonée et démarrée."
}

# Fonction pour appliquer un fichier Cloud-init spécifique
apply_cloudinit() {
    local vm_id=$1
    local cloudinit_file=$2

    echo "Application du fichier Cloud-init pour la VM $vm_id"

    # Vérifier que le fichier Cloud-init existe
    if [ ! -f "$cloudinit_file" ]; then
        echo "Erreur: Le fichier Cloud-init $cloudinit_file n'existe pas."
        exit 1
    fi

    # Copier le fichier Cloud-init sur la VM
    qm set "$vm_id" --ide2 "$cloudinit_file,media=cdrom"

    # Appliquer la configuration Cloud-init
    qm start "$vm_id"
    echo "Cloud-init appliqué à la VM $vm_id."
}

# Création des VMs OPNsense en clonant le template et en appliquant Cloud-init
for i in "${!OPNSENSE_VMS[@]}"; do
    clone_vm "${VM_IDS[$i]}" "${OPNSENSE_VMS[$i]}" "freebsd.template" "${NETWORK_CONFIGS[$i]}"
    apply_cloudinit "${VM_IDS[$i]}" "${CLOUDINIT_FILES[$i]}"
done

echo "Toutes les VMs OPNsense ont été clonées et configurées avec Cloud-init."
