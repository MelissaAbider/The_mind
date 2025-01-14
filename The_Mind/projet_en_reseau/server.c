#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <time.h>

// constantes pour configurer le serveur
#define PORT 8080                // port d'écoute du serveur
#define NB_JOUEURS_MAX 10        // nombre maximum de joueurs supportés
#define TAILLE_TAMPON 1024       // taille du buffer pour les messages

// structure pour stocker les informations de chaque client connecté
typedef struct {
    int socket;                  // socket du client
    int id_joueur;              // identifiant du joueur
    char ip[INET_ADDRSTRLEN];   // adresse ip du client stockée sous forme de chaîne
} Client;

// variables globales pour gérer l'état du serveur
Client clients[NB_JOUEURS_MAX];  // tableau stockant les infos de tous les clients
int nb_clients = 0;             // nombre de clients connectés
int joueurs_attendus = 0;       // nombre de joueurs attendus pour démarrer la partie
int nb_robots = 0;              // nombre de robots à ajouter à la partie
int socket_serveur;             // socket principal du serveur
pid_t pid_jeu = -1;             // pid du processus fils qui gère le jeu
static int fd_pipe_jeu = -1;     // descripteur du pipe de communication avec le jeu

// Prototypes des fonctions
void init_pipe_jeu(void);
void verifier_messages_jeu(void);
void gerer_signal(int sig);
void demarrer_jeu(void);
void notifier_clients_demarrage(void);
void nettoyer_pipe_jeu(void);

// fonction qui initialise le pipe de communication entre le serveur et le jeu
void init_pipe_jeu() {
    printf("[DEBUG] Initialisation du pipe de jeu...\n");
    unlink("gestionJeu.pipe");  // supprime l'ancien pipe s'il existe
    
    // création du pipe nommé avec les permissions 666 (lecture/écriture pour tous)
    if(mkfifo("gestionJeu.pipe", 0666) == -1) {
        perror("[ERREUR] Échec de création du pipe nommé");
        return;
    }
    printf("[DEBUG] Pipe de jeu créé\n");
    
    // ouvre le pipe en lecture/écriture non bloquante
    fd_pipe_jeu = open("gestionJeu.pipe", O_RDWR | O_NONBLOCK);
    if(fd_pipe_jeu == -1) {
        perror("[ERREUR] Échec d'ouverture du pipe de jeu");
        return;
    }

    // maintient une connexion d'écriture ouverte pour éviter la fermeture du pipe
    int fd_ecriture_inactive = open("gestionJeu.pipe", O_WRONLY | O_NONBLOCK);
    if(fd_ecriture_inactive != -1) {
        printf("[DEBUG] Extrémité d'écriture du pipe ouverte\n");
    }
    
    printf("[DEBUG] Pipe de jeu ouvert avec fd: %d\n", fd_pipe_jeu);
}

// fonction qui vérifie et traite les messages venant du jeu
void verifier_messages_jeu() {
    static char tampon[TAILLE_TAMPON * 2];       // buffer pour stocker les messages reçus
    static size_t position_tampon = 0;          // position courante dans le buffer

    // lecture non bloquante des données depuis le pipe
    ssize_t octets = read(fd_pipe_jeu, tampon + position_tampon, TAILLE_TAMPON - position_tampon - 1);
    if(octets > 0) {
        position_tampon += octets;
        tampon[position_tampon] = '\0';
        
        printf("[DEBUG] Lu %zd octets du pipe: %s\n", octets, tampon);
        
        // recherche un message commençant par "ID:"
        char *chaine_id = strstr(tampon, "ID:");
        if(chaine_id) {
            int id_cible;
            char type[10], contenu[TAILLE_TAMPON];
            
            // met le message au format "ID:X;TYPE;CONTENU"
            if(sscanf(chaine_id, "ID:%d;%[^;];%[^\n]", &id_cible, type, contenu) == 3) {
                printf("[DEBUG] Traitement du message pour le client %d: %s;%s\n", id_cible, type, contenu);
                char msg_client[TAILLE_TAMPON];
                snprintf(msg_client, sizeof(msg_client), "%s;%s\n", type, contenu);
                
                // recherche le client cible et lui envoie le message
                for(int i = 0; i < nb_clients; i++) {
                    if(clients[i].id_joueur == id_cible) {
                        send(clients[i].socket, msg_client, strlen(msg_client), 0);
                        printf("[DEBUG] Message envoyé au client %d\n", id_cible);
                        break;
                    }
                }
                // déplace les données restantes au début du buffer
                memmove(tampon, chaine_id + strlen(chaine_id) + 1, position_tampon - (chaine_id - tampon) - strlen(chaine_id) - 1);
                position_tampon -= (chaine_id - tampon) + strlen(chaine_id) + 1;
            }
        }
    }
}

// fonction appelée lors de la réception d'un signal (ctrl+c ou terminaison)
void gerer_signal(int sig) {
    printf("\n[DEBUG] Arrêt du serveur...\n");
    if(pid_jeu > 0) {
        kill(pid_jeu, SIGTERM);  // termine proprement le processus de jeu
    }
    nettoyer_pipe_jeu();        // supprime le pipe nommé
    // ferme toutes les connexions clients
    for(int i = 0; i < nb_clients; i++) {
        if(clients[i].socket != -1) {
            close(clients[i].socket);
        }
    }
    close(socket_serveur);      // ferme le socket serveur
    exit(0);
}

// fonction qui démarre le jeu une fois tous les joueurs connectés
void demarrer_jeu() {
    printf("[DEBUG] Démarrage de l'initialisation du jeu...\n");
    init_pipe_jeu();            // initialise le pipe de communication
    
    // convertit les nombres en chaînes pour l'envoi
    char nb_joueurs[10], nb_robots_str[10];
    sprintf(nb_joueurs, "%d", joueurs_attendus);
    sprintf(nb_robots_str, "%d", nb_robots);
    
    printf("[DEBUG] Démarrage du jeu avec %s joueurs et %s robots\n", nb_joueurs, nb_robots_str);
    
    // crée un pipe anonyme pour communiquer avec le processus fils
    int pipe_fd[2];
    if(pipe(pipe_fd) == -1) {
        perror("[ERREUR] Échec de création du pipe");
        return;
    }
    
    printf("[DEBUG] Attente avant le démarrage du processus de jeu...\n");
    sleep(2);
    
    // création du processus fils qui va exécuter le script de jeu
    pid_jeu = fork();
    if(pid_jeu == 0) {
        // code exécuté par le processus fils
        close(pipe_fd[1]);      // ferme l'extrémité d'écriture
        dup2(pipe_fd[0], STDIN_FILENO);  // redirige l'entrée standard
        close(pipe_fd[0]);
        
        printf("[DEBUG] Processus enfant démarrant GestionJeu.sh\n");
        execl("/bin/bash", "bash", "./GestionJeu.sh", "network", NULL);
        perror("[ERREUR] Échec de l'execl");
        exit(1);
    } else if(pid_jeu > 0) {
        // code exécuté par le processus parent
        printf("[DEBUG] Processus parent, pid_jeu = %d\n", pid_jeu);
        close(pipe_fd[0]);      // ferme l'extrémité de lecture
        
        // envoie le nombre de joueurs et de robots au processus fils
        write(pipe_fd[1], nb_joueurs, strlen(nb_joueurs));
        write(pipe_fd[1], "\n", 1);
        write(pipe_fd[1], nb_robots_str, strlen(nb_robots_str));
        write(pipe_fd[1], "\n", 1);
        
        close(pipe_fd[1]);
        
        printf("[DEBUG] Attente avant l'envoi des messages START...\n");
        sleep(2);
        
        notifier_clients_demarrage();
        
        printf("[DEBUG] Messages START envoyés, attente avant le traitement des messages de jeu...\n");
        sleep(2);
    } else {
        perror("[ERREUR] Échec du fork");
    }
}

// fonction qui notifie tous les clients que le jeu démarre
void notifier_clients_demarrage() {
    char msg_demarrage[TAILLE_TAMPON];
    for(int i = 0; i < nb_clients; i++) {
        // envoie un message START avec l'id du joueur
        sprintf(msg_demarrage, "START:%d", i);
        printf("[DEBUG] Envoi du message start au client %d: %s\n", i, msg_demarrage);
        ssize_t envoyes = send(clients[i].socket, msg_demarrage, strlen(msg_demarrage), 0);
        printf("[DEBUG] %zd octets envoyés\n", envoyes);
        usleep(100000);         // attente entre chaque envoi pour éviter une congestion
    }
}

// fonction qui nettoie le pipe de jeu
void nettoyer_pipe_jeu() {
    if(fd_pipe_jeu != -1) {
        close(fd_pipe_jeu);     // ferme le descripteur de fichier
        fd_pipe_jeu = -1;
    }
    unlink("gestionJeu.pipe");  // supprime le fichier du pipe nommé
}

// fonction principale
int main(void) {
    struct sockaddr_in adresse_serveur;
    
    // configure les gestionnaires de signaux
    signal(SIGINT, gerer_signal);
    signal(SIGTERM, gerer_signal);
    
    // création du socket serveur
    if((socket_serveur = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("[ERREUR] Échec de création du socket");
        exit(1);
    }
    
    // initialise la structure d'adresse du serveur
    memset(&adresse_serveur, 0, sizeof(adresse_serveur));
    adresse_serveur.sin_family = AF_INET;
    adresse_serveur.sin_addr.s_addr = INADDR_ANY;
    adresse_serveur.sin_port = htons(PORT);
    
    // options du socket
    int opt = 1;
    setsockopt(socket_serveur, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    // associe le socket à l'adresse
    if(bind(socket_serveur, (struct sockaddr*)&adresse_serveur, sizeof(adresse_serveur)) == -1) {
        perror("[ERREUR] Échec du bind");
        exit(1);
    }
    
    // met le socket en mode écoute
    if(listen(socket_serveur, 5) == -1) {
        perror("[ERREUR] Échec du listen");
        exit(1);
    }
    
    // demande le nombre de joueurs et de robots
    printf("Combien de joueurs humains attendez-vous ? ");
    scanf("%d", &joueurs_attendus);
    printf("Combien de robots souhaitez-vous ? ");
    scanf("%d", &nb_robots);
    
    printf("Serveur démarré sur le port %d\nEn attente de %d joueurs...\n", PORT, joueurs_attendus);
    
    // variables pour la boucle principale
    fd_set fds_lecture;
    int fd_max;
    char tampon[TAILLE_TAMPON];
    struct timeval delai;
    
    // boucle principale du serveur
    while(1) {
        // initialise l'ensemble des descripteurs à surveiller
        FD_ZERO(&fds_lecture);
        FD_SET(socket_serveur, &fds_lecture);
        fd_max = socket_serveur;
        
        // ajoute les sockets clients à l'ensemble
        for(int i = 0; i < nb_clients; i++) {
            if(clients[i].socket != -1) {
                FD_SET(clients[i].socket, &fds_lecture);
                if(clients[i].socket > fd_max) {
                    fd_max = clients[i].socket;
                }
            }
        }
        
        // configure le délai de timeout pour select
        delai.tv_sec = 0;
        delai.tv_usec = 50000;  // timeout de 50ms
        
        // attend des événements sur les sockets
        int activite = select(fd_max + 1, &fds_lecture, NULL, NULL, &delai);
        
        if(activite < 0 && errno != EINTR) {
            perror("[ERREUR] Échec du select");
            continue;
        }
        
        // vérifie périodiquement les messages du jeu
        static time_t derniere_verif = 0;
        time_t maintenant = time(NULL);
        if(pid_jeu > 0 && (maintenant - derniere_verif) >= 1) {
            printf("[DEBUG] Vérification des messages du jeu...\n");
            verifier_messages_jeu();
            derniere_verif = maintenant;
        }
        
        // vérifie si une nouvelle connexion est disponible
        if(FD_ISSET(socket_serveur, &fds_lecture)) {
            struct sockaddr_in adresse_client;
            socklen_t longueur_client = sizeof(adresse_client);
            int socket_client = accept(socket_serveur, (struct sockaddr*)&adresse_client, &longueur_client);
            
            if(socket_client >= 0) {
                // vérifie si on peut encore accepter des joueurs
                if(nb_clients < joueurs_attendus) {
                    // stocke les informations du nouveau client
                    clients[nb_clients].socket = socket_client;
                    clients[nb_clients].id_joueur = nb_clients;
                    inet_ntop(AF_INET, &adresse_client.sin_addr, clients[nb_clients].ip, INET_ADDRSTRLEN);
                    
                    printf("Joueur %d connecté depuis %s\n", nb_clients, clients[nb_clients].ip);
                    nb_clients++;
                    
                    // si tous les joueurs sont connectés, démarre le jeu
                    if(nb_clients == joueurs_attendus) {
                        printf("[DEBUG] Tous les joueurs sont connectés. Démarrage du jeu...\n");
                        demarrer_jeu();
                    }
                } else {
                    // refuse la connexion si le nombre maximum de joueurs est atteint
                    printf("[DEBUG] Connexion refusée : nombre maximum de joueurs atteint\n");
                    close(socket_client);
                }
            }
        }
        
        // traite les messages des clients connectés
        for(int i = 0; i < nb_clients; i++) {
            if(clients[i].socket != -1 && FD_ISSET(clients[i].socket, &fds_lecture)) {
                // lit le message du client
                int octets = recv(clients[i].socket, tampon, TAILLE_TAMPON-1, 0);
                
                if(octets <= 0) {
                    // gère la déconnexion du client
                    printf("Client %d déconnecté\n", i);
                    close(clients[i].socket);
                    clients[i].socket = -1;
                } else {
                    // traite le message reçu
                    tampon[octets] = '\0';
                    printf("[DEBUG] Reçu du client %d: %s\n", i, tampon);
                    
                    // si c'est un message de jeu (commençant par "PLAY:")
                    if(strncmp(tampon, "PLAY:", 5) == 0) {
                        // transmet le message au processus de jeu via le pipe
                        int fd_pipe = open("gestionJeu.pipe", O_WRONLY | O_NONBLOCK);
                        if(fd_pipe != -1) {
                            write(fd_pipe, tampon + 5, strlen(tampon) - 5);
                            close(fd_pipe);
                        }
                    }
                }
            }
        }
        
        // pause pour éviter de surcharger le processeur
        usleep(10000);  // pause de 10ms
    }
    
    return 0;
}