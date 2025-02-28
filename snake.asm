;compilation : nasm -f elf64 snake.asm -o snake.o
;liaison : ld snake.o -o snake

;Définire l'architecture processeur qu'on va utiliser
[bits 64]

;Définition des séctions, par convention on utilise principalement 3 sections :
;rodata : section dans laquel on va définir des variables initialisées (avec une valeur donnée)
;bss : section dans laquel on définit des variables non initialisées
;text ou code : section qui va contenir les instructions du programe

section .rodata

    ;Je défini la taille de la zone de jeu en width et height
    map_width equ 20
    map_height equ 20
    ;la map sera stockée dans un tableau, ce tableau contiendra map_height valeurs, chacune de ces valeurs contiendra un tableau de map_width
    ;c'est le principe de tableau imbriqué.
    map_size equ map_height * map_width
    clear_scr db `\033[2J\033[H`,0  ; Séquence pour effacer l'écran
    clear_scr_len equ $ - clear_scr ; longueur de la séquence

section .bss

    ;Je reserver 2 octet pour y stocker les valeurs en x et y représentant la position de la tête du serpent, idem pour le fruit.
    ;Il serait possible de créer 2 variable une pour x une pour y, je choisi de combiner les valeurs en une pour voir l'utilisation des bits suppérieur et inférieur.
    snake_head resb 2 ; Réserve 2 octets sans y inclure de valeur
    fruit resb 2
    map resb map_size ; je reserve un espace mémoire capable de contenir mon tableau map complet
    score resb 2 ; je reserve 2 octets afin de pouvoir y stocker une grande valeure (65535)
    rand_number resb 1 ; je reserve 1 octets pour stocker le résultat de génération d'un nombre (pour positioner les fruit de manière aléatoire)
    elapsed_time resb 16 ; 16 bits reservé pour stocker la valeur gettimeofday
    last_elapsed_time resb 16
    direction resb 1 ; un octet reservé pour la direction (0 haut, 1 bas, 2 gauche, 3 droite)
    cursor_sequence resb 22 ; servira à gérer l'emplacement du curseur dans le terminal
    input resb 1 ; reserve un octet pour lire les touches de déplacement
   
   ; structure pour passer en mode non canonique (lecture immédiate des touches)
    Enter: Resb 1 
    Nada: Resb 1
    termios: 
        c_iflag resd 1    ; input mode flags
        c_oflag resd 1    ; output mode flags
        c_cflag resd 1    ; control mode flags
        c_lflag resd 1    ; local mode flags
        c_line resb 1     ; line discipline
        c_cc resb 19      ; control characters

section .text
    global _start ; le label attendu par linux pour débuter le code est le label _start, afin de rendre ce label accécible au kernel linux, il est necessaire de le rendre global

_start:

        ; Sauvegarder les attributs actuels du terminal
    mov rax, 16          ; Numéro de l'appel système ioctl
    mov rdi, 0           ; Descripteur de fichier pour stdin
    mov rsi, 0x5401      ; TCGETS pour obtenir les attributs du terminal
    mov rdx, termios ; Adresse où stocker les attributs
    syscall              ; Appel système

    And byte [c_lflag], 0xFD ; Clear ICANON to disable canonical mode

    ; Write termios structure back
    mov rax, 16          ; Numéro de l'appel système ioctl
    mov rdi, 0           ; Descripteur de fichier pour stdin
    mov rsi, 0x5402      ; TCSETS pour définir les attributs du terminal
    mov rdx, termios ; Adresse des attributs du terminal
    syscall              ; Appel système

    call init ; appel de la "fonction" init, quand le programme arrivera à l'instruction ret, il reviendra executer le code situé à la ligne suivante

    game_loop:
        call get_elapsed_time ; appel de la fonction get_elapsed_time

        mov eax, [elapsed_time] ; charge les secondes actuelles dans rax
        mov ebx, [last_elapsed_time] ; charge les secondes précédente dans rbx
        imul eax,eax, 1000 ; converti les secondes en millisecondes
        imul ebx, ebx,1000
        mov edx, [elapsed_time + 8] ; Charge les microsecondes actuelles dans RDX
        mov ecx, [last_elapsed_time + 8]; Charge les microsecondes précédentes dans RCX
        shr edx, 10 ; Divise par 1024 pour convertir les microsecondes en millisecondes
        shr ecx, 10
        add rax, rdx ; Ajoute les microsecondes aux secondes (en millisecondes)
        add rbx, rcx
        sub rax, rbx ; Soustrait les millisecondes précédentes des millisecondes actuelles

        cmp rax, 200 ; compare le temps écoulé avec 200 millisecondes
        jge move_snake ; déplace le code au label move_snake 
        
    game_loop_ret:
        call read_input

    jmp game_loop
   
    mov rax, 60 ; Numéro de l'appel système exit
    mov rdi, 0 ; Code de retour 0
    syscall ; Effectue l'appel système

init: ;partie du code qui va servir à initialiser le jeu
    call get_elapsed_time
    mov rax, [elapsed_time] 
    mov [last_elapsed_time], rax ; copie les secondes actuelles dans last_elapsed_time
    mov rax, [elapsed_time +8]
    mov [last_elapsed_time +8], rax ; copie les microsecondes dans last_elapsed_time
    mov ax, 3
    mov [direction], ax ; initialise la direction du serpent vers la droite.
    
    ;(re)mise à 0 des valeurs contenue dans mon tableau map
    mov ecx, map_size ; charge la taille totale du tableau dans ECX (compteur de boucle)
    xor eax,eax ; met le registre eax à zero (l'oppération xor vaut 0 si les bits comparé sont de même valeur, en comparant eax avec lui même, le résultat sera forcément zero)
    mov edi, map ; charge l'adresse de début du tableau (map) dans le registre edi

    clear_map_loop: ;début de ma boucle
        mov [edi], al ;met à zéro l'octet à l'adresse EDI
        inc edi ;incrémente edi pour passer à l'octet suivant
    loop clear_map_loop ;Décrémente ECX et boucle jusqu'à ce que ECX soit égale à zéro

    ;j'initialiser la position de la tête du serpent.
    ;je stock dans le registre AX (16 bits) la position Y dans les bits supérieurs et X dans les bits inférieur
    mov AX,map_width ; je stock le registre AX la valeur map_width
    SHR AX, 1 ; je divise la valeur stockée dans AX par 2 pour obtenir de centre de ma map, ici la division se fait en décalant les bits de 1 vers la droite
    ;20 en binaire = 0001 0100, 10 en binaire = 1010. Aurait également pu s'écrire "div AX, 2"
    mov bl, al ; je stock dans la valeur basse de BX (bl) la valeur basse de AX (al)

    mov AX,map_height ; je stock dans le registre AX la valeur map_height
    SHR AX,1
    mov bh, al ; je stock dans la valeur haute de BX (bh) la valeur basse de AX (ah)
    mov [snake_head],BX ; je stock dans snake_head la valeur contenu dans BX (BH et BL)
    movzx eax, bh ; étend bh (valeur haute de bx qui contiens la position y de snake_head) à eax afin de pouvoir faire des calcules en 32 bits
    movzx ecx, bl ; étend bl (valeur basse de bx qui contiens la position x de snake_head) à ecx 
    mov edx, map_width ; stock map_width dans edx afin de calculer l'index de mon tableau map correspondant à la position de snake_head
    imul eax, edx ; multipli eax à edx, le résultat de l'oppération sera stocké dans eax (snake_head.y + map_width)
    add eax, ecx ; ajoute ecx à eax, le résultat de l'oppération sera stocké dans eax ((snake_head.y + map_width)+snake_head.x) 
    mov byte [map + eax], 1 ; mets à 1 l'octet située à l'emplacement map[snake_head.y][snake_head.x] (adresse mémoire obtenue avec les oppérations précédentes)

    mov word [fruit], 0; je mets à zero la valeur de fruit
    call generate_fruit

    call draw_map
    ret

generate_fruit: ; générer un fruit à une position libre de la map
    call get_rand ; pour obtenir une valeur aléatoire en x, je fais un premier appel à ma fonction get_rand
    mov al, 2;[rand_number] ; charge la valeur aléatoire dans al
    call get_rand ; je fais un second appel pour la valeur y
    mov ah, 2;[rand_number] ; charge la valeur dans ah

    ; Calculer l'index pour accéder à map[y][x]
    movzx ebx, ah        ; Étend AH à EBX pour des calculs 32 bits
    movzx ecx, al        ; Étend AL à ECX pour des calculs 32 bits
    mov edx, map_width   ; Charge map_width dans EDX
    imul ebx, edx        ; Multiplie EBX (Y) par EDX (map_width)
    add ebx, ecx         ; Ajoute ECX (X) à EBX pour obtenir l'index final

    ; Vérifier si la case est libre
    cmp byte [map + ebx], 0 ; Compare la valeur dans map à l'index calculé
    je valid_fruit_position ; saute à l'adresse valid_fruit_position si la case est libre
    jmp generate_fruit ; rappel la procédure sinon

valid_fruit_position:
    mov [fruit], ax ; place la valeur de ax dans fruit
    mov byte [map + ebx], 3
    ret

get_rand:
    ;pour obtenir un nombre aléatoire on va utiliser un appel system à linux, dans ce cas on veux appeler le syscall getrandom
    ;pour obtenir des infos sur les syscall linux https://syscalls.w3challs.com/?arch=x86_64
    mov eax, 318 ; je place dans eax le numéro d'appel système correspondant à getrandom
    mov edi, rand_number ; je fournit à edi l'emplacement ou stocker le résultat
    mov esi, 1 ; je place dans esi le nombre d'octets à lire
    syscall ; Effectue l'appel système
    ;j'ai maintenant dans rand_number une valeur entre 0 et 255, je dois la réduire entre 0 et 19 pour correspondre à la taille de ma map
    mov eax, [rand_number] ; charge le nombre aléatoire dans eax
    mov ecx, map_width ; charge ma valeur max dans ecx
    xor edx,edx ; met edx à zéro
    div ecx ; Divise EAX par ECX, le reste est dans EDX
    mov [rand_number], dl ; stocke le reste dans rand_number, il faut utiliser dl qui est la valeure basse (8 derniers bits) de EDX car rand_number ne fais que 1 octet
    ret

get_elapsed_time:
    ;appel système gettimeofday
    mov rax, 96 ; numéro de l'appel système
    mov rdi, elapsed_time ; adresse où stocker la valeur
    mov rsi, 0 ; Pas de structure timezone
    syscall ; effectue l'appel système
    ret

move_snake:
    ;Mise à jour de last_elapsed_time
    mov rax, [elapsed_time]
    mov [last_elapsed_time], rax ; copie les secondes de elapsed_time dans last_elapsed_time
    mov rax, [elapsed_time+8]
    mov [last_elapsed_time+8], rax ; copie les microsecondes de elapsed_time dans last_elapsed_time
    ;oppération pour déplacer le serpent ici
    mov ax, [snake_head]
    ; mets à 0 l'ancien emplacement dans map
    movzx ebx, ah ; étend ah (position y de snake_head) à ebx (pour des calcules en 32 bits)
    movzx ecx, al ; étend ah (position x de snake_head) à ecx (pour des calcules en 32 bits)
    mov edx, map_width ; calcule l'index du tableau map pour la position y x de snake_head (map_width * snake_head.y + snake_head.x)
    imul ebx, edx
    add ebx, ecx
    mov byte [map + ebx], 0 ; mets à 0 l'ancienne valeur de snake_head dans le tableau

    mov al, [direction] ; regarde la direction du serpent
    cmp al, 0
    je move_snake_up
    cmp al, 1
    je move_snake_down
    cmp al, 2
    je move_snake_left
    cmp al, 3
    je move_snake_right
    move_snake_up:
        mov ax, [snake_head] ; récupère dans ax la valeure de la variable snake_head
        dec ah ; décrémente la valeur haute de ax (snake_head.y)
        cmp ah, 0 ; si snake_head.y = 0 va au label move_snake_death
        je move_snake_death
        mov [snake_head], ax ; mets à jour la variable snake_head
        jmp update_snake_in_map ; va au label update_snake_in_map

    move_snake_down:
        mov ax, [snake_head]
        inc ah
        cmp ah, map_height-1
        je move_snake_death
        mov [snake_head], ax
        jmp update_snake_in_map
    
    move_snake_left:
        mov ax, [snake_head]
        dec al
        cmp al, 0
        je move_snake_death
        mov [snake_head], ax
        jmp update_snake_in_map

    move_snake_right:
        mov ax, [snake_head]
        inc al
        cmp al, map_width-1
        je move_snake_death
        mov [snake_head], ax


    update_snake_in_map:
        ; mets à jour le nouvel emplacement dans map
        movzx ebx, ah ; étend ah (position y de snake_head) à ebx (pour des calcules en 32 bits)
        movzx ecx, al ; étend al (position x de snake_head) à ecx
        mov edx, map_width ; calcule l'index du tableau map pour la position y et x de snake_head
        imul ebx, edx
        add ebx, ecx
        mov byte [map + ebx], 1 ; mets à jour la valeur de map[snake_head.y][snake_head.x] à 1

    call draw_map

    jmp game_loop_ret; retour à game_loop 

    move_snake_death:
        call init
        jmp game_loop_ret  

read_input:
    ; Lire une entrée clavier
    mov rax, 0           ; Numéro de l'appel système read
    mov rdi, 0           ; Descripteur de fichier pour stdin
    mov rsi, input       ; Adresse où stocker l'entrée
    mov rdx, 1           ; Lire un seul caractère
    syscall              ; Appel système

    ; Vérifier quelle touche a été pressée
    cmp byte [input], 'z'
    je move_up

    cmp byte [input], 's'
    je move_down

    cmp byte [input], 'q'
    je move_left

    cmp byte [input], 'd'
    je move_right

    ret

    move_up:
        ; Traiter le mouvement vers le haut
        mov byte [direction], 0
        ret

    move_down:
        ; Traiter le mouvement vers le bas
        mov byte [direction], 1
        ret

    move_left:
        ; Traiter le mouvement vers la gauche
        mov byte [direction], 2
        ret

    move_right:
        ; Traiter le mouvement vers la droite
        mov byte [direction], 3
    
draw_map:
    call clear_screen
    xor rax, rax ; compteur de boucle y
    xor rbx, rbx ; compteur de boucle x
    draw_loop_y:
        cmp rbx, map_width  ; compare le compteur de boucle x avec la taille de la map
        jne draw_loop_x ; Si le compteur de boucle n'est pas égale à map_width, passe au label draw_loop_x
        inc rax ; incrémente le compteur de boucle y
        push rax ; sauvegarde l'état du compteur de boucle y dans la stack
        jmp send_sequence ; passe au laber send_sequence
        draw_loop_x:
            ;dessinner les contours de la map
            cmp rax,0 ; compare le compteur de boucle y à 0 (première ligne) 
            je draw_line ; Si égale, passe au label draw_line
            cmp rax, map_height-1 ; regarde si on est à la dernière ligne
            je draw_line ; si oui, passe au label draw_line
            cmp rbx,0 ; compare le compteur de boucle x à 0
            je draw_col ; si égale, passe au label draw_col
            cmp rbx, map_width-1 ; compare si on est à la dernière colone
            je draw_col ; si oui, passe au label draw_col

            ;dessiner les éléments du jeux (fruit et serpent, cette partie du code ne peux s'executer que si on ne déssine ni une ligne, ni une colone)
            push rax ; sauvegarde l'état du compteur de boucle y dans la stack
            mov rdx, map_width ; détermine l'index du tableau map (map_width * compteur de boucle Y + compteur de boucle X)
            imul rax, rdx
            add rax, rbx
            cmp byte [map+rax], 0 ; Si map[loopy][loopx] = 0 va à draw_space
            je draw_space
            cmp byte [map+rax], 3 ; Si map[loopy][loopx] = 3 va à draw_fruit
            je draw_fruit
            cmp byte [map+rax] , 1 ; Si map[loopy][loopx] = 1 va à draw_snake_head
            je draw_snake_head
            ;Si aucune des conditions précédente n'est rencontrée :
            pop rax ; récupère la valeur du compteur de boucle Y précédement stocké dans la Stack et place le dans rax
            inc rbx ; incrémente le compteur de boucle x
            jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y
            
    draw_line:
        mov byte [cursor_sequence + rbx], '_' ; Modifi 1 octet à la chaine de caractère contenue à l'adresse mémoire cursor_sequence + compteur de boucle X avec la caractère '_'
        inc rbx  ; incrémente le compteur de boucle x
        jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y
    draw_col:
        mov byte [cursor_sequence + rbx], '|' ; Modifi 1 octet à la chaine de caractère contenue à l'adresse mémoire cursor_sequence + compteur de boucle X avec la caractère '|'
        inc rbx ; incrémente le compteur de boucle x
        jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y
    draw_space:
        mov byte [cursor_sequence + rbx], ' ' ; Modifi 1 octet à la chaine de caractère contenue à l'adresse mémoire cursor_sequence + compteur de boucle X avec la caractère espace
        inc rbx ; incrémente le compteur de boucle x
        pop rax ; récupère la valeur du compteur de boucle Y précédement stocké dans la Stack et place le dans rax
        jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y
    draw_fruit:
        mov byte [cursor_sequence + rbx], '+' ; Modifi 1 octet à la chaine de caractère contenue à l'adresse mémoire cursor_sequence + compteur de boucle X avec la caractère '+'
        inc rbx ; incrémente le compteur de boucle x
        pop rax ; récupère la valeur du compteur de boucle Y précédement stocké dans la Stack et place le dans rax
        jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y
    draw_snake_head:
        mov byte [cursor_sequence + rbx], 'o' ; Modifi 1 octet à la chaine de caractère contenue à l'adresse mémoire cursor_sequence + compteur de boucle X avec la caractère 'o'
        inc rbx ; incrémente le compteur de boucle x
        pop rax ; récupère la valeur du compteur de boucle Y précédement stocké dans la Stack et place le dans rax
        jmp draw_loop_y ; continu la boucle (retourne au label draw_loop_y

    send_sequence:
        mov word [cursor_sequence + rbx], 0xA ; ajout d'un saut le ligne à la fin de la séquence
        mov rax, 1           ; Numéro de l'appel système write
        mov rdi, 0           ; Descripteur de fichier pour stdout
        mov rsi, cursor_sequence    ; Adresse du message
        mov rdx, 22 ; Longueur du message
        syscall         ; Appel système
        xor rbx,rbx ; remet à 0 le compteur de boucle x
        pop rax ; récupère la valeur du compteur de boucle Y précédement stocké dans la Stack et place le dans rax
        cmp rax, map_height ; regarde si on est à la dernière ligne (dernière élément du tableau map)
        je end_loop ; si oui passe au label end_loop (termine la boucle)
        jmp draw_loop_x ; retourne au label draw_loop_x (pas besoin de repasser par draw_loop_y, on viens de remetre le compteur de boucle x à 0, il ne vaut donc pas map_width)
    end_loop:
    ret

clear_screen: ;fonction pour vider le terminal
    mov rax, 1 ; Numéro de l'appel système write
    mov rdi, 1 
    mov rsi, clear_scr
    mov rdx, clear_scr_len
    syscall
    ret
