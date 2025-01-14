#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/stat.h>

// constante pour configurer la taille du buffer de messages
#define TAILLE_TAMPON 1024      // taille du buffer pour stocker les messages

// variables globales pour gérer l'état du client
int socket_client = -1;         // socket de connexion au serveur
pid_t pid_shell = -1;          // pid du processus fils qui exécute le shell joueur
int id_joueur = -1;            // identifiant du joueur attribué par le serveur

// fonction qui supprime les tubes nommés créés par le client
void nettoyer_tubes() {
    char nom_tube[20];
    if(id_joueur != -1) {
        sprintf(nom_tube, "%d.pipe", id_joueur);
        unlink(nom_tube);       // supprime le tube du joueur
    }
    unlink("gestionJeu.pipe");  // supprime le tube de gestion du jeu
}

// fonction appelée lors de la réception d'un signal (ctrl+c ou terminaison)
void gerer_signal(int sig) {
    printf("\n[DEBUG] Arrêt du client...\n");
    if(pid_shell > 0) {
        kill(pid_shell, SIGTERM);  // termine proprement le processus shell
        waitpid(pid_shell, NULL, 0);  // attend la fin du processus fils
    }
    if(socket_client != -1) {
        close(socket_client);    // ferme la connexion avec le serveur
    }
    nettoyer_tubes();           // supprime les tubes nommés
    exit(0);
}

// fonction qui crée les tubes nommés nécessaires à la communication locale
void creer_tubes_locaux(int id) {
    char nom_tube[20];
    
    // crée le tube spécifique au joueur
    sprintf(nom_tube, "%d.pipe", id);
    unlink(nom_tube);           // supprime l'ancien tube s'il existe
    if(mkfifo(nom_tube, 0666) == -1 && errno != EEXIST) {
        perror("[ERREUR] Échec de création du tube joueur");
        return;
    }
    printf("[DEBUG] Tube joueur créé : %s\n", nom_tube);

    // crée ensuite le tube de gestion du jeu
    unlink("gestionJeu.pipe");  // supprime l'ancien tube s'il existe
    if(mkfifo("gestionJeu.pipe", 0666) == -1 && errno != EEXIST) {
        perror("[ERREUR] Échec de création du tube de jeu");
        return;
    }
    printf("[DEBUG] Tube de jeu créé : gestionJeu.pipe\n");
    
    // pause pour s'assurer que les tubes sont bien créés
    sleep(1);
}

// fonction qui démarre le shell joueur dans un processus fils
void lancer_shell_joueur(int id) {
    char id_chaine[10];
    sprintf(id_chaine, "%d", id);
    
    printf("[DEBUG] Lancement de JoueurHumain.sh avec l'ID %s\n", id_chaine);
    
    // création du processus fils qui va exécuter le script joueur
    pid_shell = fork();
    if(pid_shell == 0) {
        // code exécuté par le processus fils
        execl("/bin/bash", "bash", "./JoueurHumain.sh", id_chaine, NULL);
        perror("[ERREUR] Échec de l'execl");
        exit(1);
    } else if(pid_shell > 0) {
        // code exécuté par le processus parent
        printf("[DEBUG] JoueurHumain.sh lancé avec PID %d\n", pid_shell);
    } else {
        perror("[ERREUR] Échec du fork");
    }
}

// fonction qui traite les messages reçus du serveur
void traiter_message_serveur(char *msg) {
    printf("[DEBUG] Reçu du serveur : %s\n", msg);
    
    // traite le message de démarrage qui contient l'id du joueur
    if(strncmp(msg, "START:", 6) == 0) {
        id_joueur = atoi(msg + 6);
        printf("[DEBUG] ID joueur reçu : %d\n", id_joueur);
        creer_tubes_locaux(id_joueur);
        lancer_shell_joueur(id_joueur);
        return;
    }
    
    // transmet les autres messages au shell joueur via son tube nommé
    char nom_tube[20];
    sprintf(nom_tube, "%d.pipe", id_joueur);
    
    int fd_tube = open(nom_tube, O_WRONLY);
    if(fd_tube != -1) {
        write(fd_tube, msg, strlen(msg));
        write(fd_tube, "\n", 1);
        close(fd_tube);
    }
}

// fonction qui vérifie et transmet les messages du shell joueur au serveur
void surveiller_tube_jeu() {
    if(id_joueur == -1) return;
    
    // lecture non bloquante du tube de jeu
    int fd_tube = open("gestionJeu.pipe", O_RDONLY | O_NONBLOCK);
    if(fd_tube != -1) {
        char tampon[TAILLE_TAMPON];
        int octets = read(fd_tube, tampon, TAILLE_TAMPON-1);
        
        if(octets > 0) {
            tampon[octets] = '\0';
            printf("[DEBUG] Lu depuis le tube de jeu : %s\n", tampon);
            
            // ajoute le préfixe PLAY: et envoie au serveur
            char msg[TAILLE_TAMPON+10];
            sprintf(msg, "PLAY:%s", tampon);
            ssize_t envoyes = send(socket_client, msg, strlen(msg), 0);
            printf("[DEBUG] Envoyé au serveur : %s (%zd octets)\n", msg, envoyes);
        }
        close(fd_tube);
    }
}

// fonction principale
int main(int argc, char *argv[]) {
    // vérifie les arguments de la ligne de commande (ex: ./client 123.456.789.0 0)
    if(argc != 3) {
        printf("Usage: %s <ip_serveur> <id_joueur>\n", argv[0]);
        return 1;
    }
    
    // configure les gestionnaires de signaux
    signal(SIGINT, gerer_signal);
    signal(SIGTERM, gerer_signal);
    
    printf("[DEBUG] Démarrage du client, en attente d'assignation par le serveur...\n");
    
    struct sockaddr_in adresse_serveur;
    char tampon[TAILLE_TAMPON];
    
    // création du socket client
    if((socket_client = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("[ERREUR] Échec de création du socket");
        return 1;
    }
    
    // initialise la structure d'adresse du serveur
    memset(&adresse_serveur, 0, sizeof(adresse_serveur));
    adresse_serveur.sin_family = AF_INET;
    adresse_serveur.sin_port = htons(8080);
    if(inet_pton(AF_INET, argv[1], &adresse_serveur.sin_addr) <= 0) {
        perror("[ERREUR] Adresse invalide");
        return 1;
    }
    
    // tente de se connecter au serveur
    printf("[DEBUG] Tentative de connexion au serveur %s\n", argv[1]);
    if(connect(socket_client, (struct sockaddr*)&adresse_serveur, sizeof(adresse_serveur)) == -1) {
        perror("[ERREUR] Échec de connexion");
        return 1;
    }
    
    printf("Connecté au serveur %s\n", argv[1]);
    
    // variables pour la boucle principale
    fd_set fds_lecture;
    struct timeval delai;
    
    // boucle principale du client
    while(1) {
        // initialise l'ensemble des descripteurs à surveiller
        FD_ZERO(&fds_lecture);
        FD_SET(socket_client, &fds_lecture);
        
        // configure le délai de timeout pour select
        delai.tv_sec = 0;
        delai.tv_usec = 100000;  // 100ms
        
        // attend des événements sur le socket
        int activite = select(socket_client + 1, &fds_lecture, NULL, NULL, &delai);
        
        if(activite < 0 && errno != EINTR) {
            perror("[ERREUR] Échec du select");
            continue;
        }
        
        // traite les messages reçus du serveur
        if(activite > 0 && FD_ISSET(socket_client, &fds_lecture)) {
            int octets = recv(socket_client, tampon, TAILLE_TAMPON-1, 0);
            if(octets <= 0) {
                printf("[DEBUG] Serveur déconnecté\n");
                break;
            } else {
                tampon[octets] = '\0';
                traiter_message_serveur(tampon);
            }
        }
        
        // vérifie périodiquement les messages du shell joueur
        if(id_joueur != -1 && access("gestionJeu.pipe", F_OK) == 0) {
            surveiller_tube_jeu();
        }
    }
    
    // nettoyage final avant de quitter
    gerer_signal(SIGTERM);
    return 0;
}