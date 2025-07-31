# born2beroot

##Pre-install

##Post-install
build minimal debian server

🛠️ Étape 1 : Install ssh on debian

sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

🛠️ Étape 2 : Those lines shouldn't be commented on /etc/ssh/sshd_config

PermitRootLogin no
PasswordAuthentication yes

sudo systemctl restart ssh

🛠️ Étape 3 : Configure bien le port dans VirtualBox

    Ouvre VirtualBox > Sélectionne ta VM > Paramètres.

    Va dans Réseau > Carte 1 > Assure-toi que :

        ✅ Mode d’accès réseau = NAT

        ✅ Clique sur le bouton Avancé > Redirection de port.

    Ajoute une règle (ou modifie-la) comme suit :

Nom	Protocole	Hôte IP	Port Hôte	IP Invité	Port Invité
SSH4242	TCP		4242		22
➡️ Ici, on dit :
Quand tu accèdes à localhost:4242 sur le Mac, VirtualBox redirige vers 10.0.2.15:22 (la VM).

[image ici]

Test:
ssh -p 4242 radandri42@127.0.0.1

Copy born2beroot.bash in the VM:
scp -p 4242 born2beroot.bash radandri42@127.0.0.1:/home/radandri42

Add agremets before run:
chmod +x born2beroot.bash

Run:
sudo ./born2beroot.bash
