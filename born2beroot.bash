#!/bin/bash

set -e

### === INSTALLATION DE BASE === ###
echo "[0/10] Vérification de sudo..."
if ! command -v sudo &>/dev/null; then
  echo "⚠️ sudo non installé. Installation en cours..."
  apt update && apt install -y sudo
fi

### === PARAMÈTRES === ###
SUDO_LOG_DIR="/var/log/sudo"
MONITOR_SCRIPT="/usr/local/bin/monitoring.sh"

### === OPTIONS ENTRÉES === ###
SKIP_SSH=false
FORCE_SSH=false

for arg in "$@"; do
  case $arg in
    --skip-ssh)
      SKIP_SSH=true
      shift
      ;;
    --force-ssh)
      FORCE_SSH=true
      shift
      ;;
  esac
done

### === DEMANDER LE LOGIN 42 === ###
read -p "Entrez votre login 42 (ex: radandri) : " LOGIN
USERNAME="$LOGIN"
HOSTNAME="${LOGIN}42"
GROUPNAME="${LOGIN}42"

echo "[1/10] Création de l'utilisateur $USERNAME si nécessaire..."
if id "$USERNAME" &>/dev/null; then
  echo "Utilisateur $USERNAME déjà présent."
else
  adduser --disabled-password --gecos "" "$USERNAME"
  echo "Veuillez entrer un mot de passe pour $USERNAME :"
  passwd "$USERNAME"
fi

echo "[2/10] Attribution des groupes..."
groupadd -f "$GROUPNAME"
usermod -aG sudo "$USERNAME"
usermod -aG "$GROUPNAME" "$USERNAME"

echo "[3/10] Configuration du hostname..."
if [ "$(hostname)" != "$HOSTNAME" ]; then
  echo "$HOSTNAME" > /etc/hostname
  hostnamectl set-hostname "$HOSTNAME"
  echo "Hostname mis à jour."
else
  echo "Hostname déjà correct."
fi

echo "[4/10] Politique de mot de passe (PAM + chage)..."
grep -q "pam_pwquality.so" /etc/pam.d/common-password || {
  echo "password requisite pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 reject_username difok=7 enforce_for_root" >> /etc/pam.d/common-password
}
chage -M 30 -m 2 -W 7 "$USERNAME"
chage -M 30 -m 2 -W 7 root

echo "[5/10] Configuration sudo sécurisée..."
mkdir -p "$SUDO_LOG_DIR"
chmod 700 "$SUDO_LOG_DIR"
touch /etc/sudoers.d/42sudo
echo "$USERNAME ALL=(ALL:ALL) ALL" > /etc/sudoers.d/42sudo
grep -q "Defaults logfile=" /etc/sudoers || echo "Defaults logfile=\"$SUDO_LOG_DIR/sudo.log\"" >> /etc/sudoers
grep -q 'Defaults log_input' /etc/sudoers || echo 'Defaults log_input' >> /etc/sudoers
grep -q 'Defaults log_output' /etc/sudoers || echo 'Defaults log_output' >> /etc/sudoers
grep -q 'Defaults iolog_dir=' /etc/sudoers || echo 'Defaults iolog_dir="/var/log/sudo"' >> /etc/sudoers
grep -q "Defaults badpass_message=" /etc/sudoers || echo "Defaults badpass_message=\"Wrong password... Access Denied.\"" >> /etc/sudoers
grep -q "Defaults passwd_tries=" /etc/sudoers || echo "Defaults passwd_tries=3" >> /etc/sudoers
grep -q "Defaults requiretty" /etc/sudoers || echo "Defaults requiretty" >> /etc/sudoers
grep -q "Defaults secure_path=" /etc/sudoers || echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"' >> /etc/sudoers

echo "[6/10] AppArmor (sécurité)..."
systemctl enable apparmor
systemctl start apparmor

echo "[7/10] Configuration du pare-feu UFW..."
apt install -y ufw
ufw allow 4242/tcp
ufw --force enable

### === SSH === ###
echo "[8/10] Gestion du SSH..."
if $SKIP_SSH; then
  echo "SSH ignoré (--skip-ssh activé)"
else
  if $FORCE_SSH || ! systemctl is-active ssh &>/dev/null; then
    echo "Installation et configuration de SSH..."
    apt install -y openssh-server
    sed -i 's/#Port 22/Port 4242/' /etc/ssh/sshd_config
    sed -i 's/Port 22/Port 4242/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl enable ssh
    systemctl restart ssh
    echo "SSH configuré sur le port 4242 (root interdit)"
  else
    echo "SSH déjà actif, configuration ignorée (utilisez --force-ssh pour forcer)"
  fi
fi

echo "[9/10] Déploiement du script monitoring.sh..."
cat << 'EOF' > "$MONITOR_SCRIPT"
#!/bin/bash
ARCH=$(uname -a)
PCPU=$(grep "physical id" /proc/cpuinfo | sort | uniq | wc -l)
VCPU=$(grep -c ^processor /proc/cpuinfo)
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_PERC=$(free | awk '/Mem:/ {printf("%.2f"), $3/$2 * 100}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_PERC=$(df / | awk 'NR==2 {printf("%.0f"), $3/$2 * 100}')
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
LAST_BOOT=$(who -b | awk '{print $3 " " $4}')
LVM=$(lsblk | grep -q "lvm" && echo "yes" || echo "no")
TCP_CONN=$(ss -ta | grep ESTAB | wc -l)
LOGGED_USERS=$(users | wc -w)
IPV4=$(hostname -I | awk '{print $1}')
MAC=$(ip link show | awk '/ether/ {print $2}' | head -n 1)
SUDO_CMDS=$(journalctl _COMM=sudo | grep COMMAND | wc -l)

wall << EOM
#Architecture: $ARCH
#CPU physical : $PCPU
#vCPU : $VCPU
#Memory Usage: $RAM_USED/${RAM_TOTAL}MB (${RAM_PERC}%)
#Disk Usage: $DISK_USED/${DISK_TOTAL} (${DISK_PERC}%)
#CPU load: $CPU_LOAD
#Last boot: $LAST_BOOT
#LVM use: $LVM
#Connections TCP : $TCP_CONN ESTABLISHED
#User log: $LOGGED_USERS
#Network: IP $IPV4 ($MAC)
#Sudo : $SUDO_CMDS cmd
EOM
EOF

chmod +x "$MONITOR_SCRIPT"
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT" ; echo "*/10 * * * * $MONITOR_SCRIPT") | crontab -

echo "Installation terminée avec succès !"
