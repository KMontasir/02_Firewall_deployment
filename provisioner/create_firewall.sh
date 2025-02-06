#!/bin/bash
# Variables communes
TEMPLATE_ID=9999
VM_STORAGE="local-lvm-vm"  # Stockage pour les VMs et le template
SNIPPET_STORAGE="snippets"  # Stockage des fichiers Cloud-Init
POOL_NAME="pare-feu"  # Pool où seront ajoutées les VMs
CORES=2
MEMORY=2048
DISK_SIZE="20G"
CLOUDINIT_DISK="${SNIPPET_STORAGE}:cloudinit"  # Cloud-Init reste sur "local"
# Variables pour les VMs OPNsense
OPNSENSE_VMS=("template" "opnsense1" "opnsense2" "opnsense3")
VM_IDS=(9998 1001 1002 1003)
# Chemins vers les fichiers Cloud-init spécifiques
CLOUDINIT_FILES=( 
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-template.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-1.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-2.yml"
  "/root/02_Firewall_deployment/cloud_init/cloud-init-firewall-3.yml"
)
# Copier les fichiers Cloud-init dans le snippets storage
for file in "${CLOUDINIT_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    cp "$file" "/var/lib/vz/$SNIPPET_STORAGE"
    echo "Copié : $file -> /var/lib/vz/$SNIPPET_STORAGE"
  else
    echo "Avertissement: Le fichier $file n'existe pas."
  fi
done
# Configuration des interfaces réseau pour chaque VM
NETWORK_CONFIGS=( 
  "vmbr0,vmbr1,vmbr4"
  "vmbr0,vmbr1,vmbr4"
  "vmbr1,vmbr2,vmbr4"
  "vmbr2,vmbr3,vmbr4"
)
# Vérification et création du pool "pare-feu" si nécessaire
if ! pvesh get /pools | grep -q "\"$POOL_NAME\""; then
    echo "Création du pool '$POOL_NAME'..."
    pvesh create /pools -poolid "$POOL_NAME"
fi
# Vérification et création du stockage snippets si nécessaire
if ! pvesm status | grep -q "$SNIPPET_STORAGE"; then
    echo "Création du stockage '$SNIPPET_STORAGE' pour les snippets..."
    pvesm add dir "$SNIPPET_STORAGE" --path /var/lib/vz --content snippets
fi
# Vérification et création du dossier snippets si nécessaire
SNIPPET_PATH="/var/lib/vz/snippets"  # Correction ici pour pointer vers le bon sous-dossier
mkdir -p "$SNIPPET_PATH"
chmod 755 "$SNIPPET_PATH"
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
# Fonction pour cloner une VM et l'ajouter au pool "pare-feu"
clone_vm() {
    local vm_id=$1
    local name=$2
    local network_config=$3
    echo "Clonage de la VM $name à partir du template ID $TEMPLATE_ID"
    # Vérifier si la VM existe déjà, la supprimer si nécessaire
    if qm status "$vm_id" &>/dev/null; then
        echo "La VM $vm_id existe déjà, suppression en cours..."
        qm stop "$vm_id" --skiplock
        sleep 2
        qm destroy "$vm_id" --destroy-unreferenced-disks 1
    fi
    # Cloner la VM à partir du template
    qm clone "$TEMPLATE_ID" "$vm_id" --name "$name" --full --storage "$VM_STORAGE"
    # Ajouter la VM au pool "pare-feu"
    pvesh set /pools/"$POOL_NAME" -vms "$vm_id"
    # Configurer les ressources de la VM
    qm set "$vm_id" --cpu host --cores "$CORES" --memory "$MEMORY"
    # Configurer et redimensionner le disque dur
    qm resize "$vm_id" scsi0 "$DISK_SIZE"
    # Configurer les interfaces réseau
    IFS=',' read -r -a networks <<< "$network_config"
    qm set "$vm_id" --net0 virtio,bridge="${networks[0]},firewall=1"
    qm set "$vm_id" --net1 virtio,bridge="${networks[1]},firewall=1"
    qm set "$vm_id" --net2 virtio,bridge="${networks[2]},firewall=1"
    # Activer CloudInit
    qm set "$vm_id" --ide2 "$CLOUDINIT_DISK,media=cdrom"
    # Démarrer la VM clonée
    qm start "$vm_id"
    echo "VM $name clonée, ajoutée au pool '$POOL_NAME' et démarrée."
    sleep 5
}
# Fonction pour appliquer un fichier Cloud-init spécifique
apply_cloudinit() {
    local vm_id=$1
    local cloudinit_file=$2
    local snippet_name=$(basename "$cloudinit_file")
    echo "Application du fichier Cloud-init pour la VM $vm_id"
    # Ajouter le fichier Cloud-init en tant que snippet
    add_cloudinit_snippet "$cloudinit_file"
    # Associer le fichier Cloud-init à la VM
    qm set "$vm_id" --cicustom "user=$SNIPPET_STORAGE:snippets/$snippet_name"
    # Redémarrer la VM pour appliquer Cloud-init
    qm stop "$vm_id"
    sleep 2
    qm start "$vm_id"
    echo "Cloud-init appliqué à la VM $vm_id."
}
# Création des VMs OPNsense en clonant le template, ajout au pool "pare-feu" et application de Cloud-init
for i in "${!OPNSENSE_VMS[@]}"; do
    clone_vm "${VM_IDS[$i]}" "${OPNSENSE_VMS[$i]}" "${NETWORK_CONFIGS[$i]}"
    apply_cloudinit "${VM_IDS[$i]}" "${CLOUDINIT_FILES[$i]}"
done
echo "Toutes les VMs OPNsense ont été clonées, ajoutées au pool '$POOL_NAME' et configurées avec Cloud-init."
