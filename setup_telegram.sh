#!/bin/bash

ALIAS_NAME="mtg"
BINARY_PATH="/usr/local/bin/mtg"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

check_root() {
    if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: запустите через sudo!${NC}"; exit 1; fi
}

install_deps() {
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        apt-get update && apt-get install -y qrencode || yum install -y qrencode
    fi
    cp "$0" "$BINARY_PATH" && chmod +x "$BINARY_PATH"
    echo -e "${GREEN}[OK] Скрипт доступен как команда: ${CYAN}mtg${NC}"
}

get_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org || curl -s -4 --max-time 5 https://icanhazip.com || echo "0.0.0.0")
    echo "$ip" | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1
}

show_config() {
    if ! docker ps | grep -q "mtproto-proxy"; then echo -e "${RED}Прокси не найден!${NC}"; return; fi
    SECRET=$(docker inspect mtproto-proxy --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    IP=$(get_ip)
    PORT=$(docker inspect mtproto-proxy --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    PORT=${PORT:-443}
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN}=== ПАНЕЛЬ ДАННЫХ (RU) ===${NC}"
    echo -e "IP: $IP | Port: $PORT"
    echo -e "Secret: $SECRET"
    echo -e "Link: ${BLUE}$LINK${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

menu_install() {
    clear
    echo -e "${CYAN}--- Выберите домен для маскировки (Fake TLS) ---${NC}"
    domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "ss.com" "autoauto.pl" "auto24.lv" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "dw.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com"
    )
    
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        [[ $(( (i+1) % 2 )) -eq 0 ]] && echo ""
    done
    
    read -p "Ваш выбор [1-20]: " d_idx
    DOMAIN=${domains[$((d_idx-1))]}
    DOMAIN=${DOMAIN:-google.com}

    echo -e "\n${CYAN}--- Выберите порт ---${NC}"
    echo -e "1) 443 (Рекомендуется)"
    echo -e "2) 8443"
    echo -e "3) Свой порт"
    read -p "Выбор: " p_choice
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "Введите свой порт: " PORT ;;
        *) PORT=443 ;;
    esac

    echo -e "${YELLOW}[*] Настройка прокси...${NC}"
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN")
    docker stop mtproto-proxy &>/dev/null && docker rm mtproto-proxy &>/dev/null
    
    docker run -d --name mtproto-proxy --restart always -p "$PORT":"$PORT" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$SECRET" > /dev/null
    
    clear
    show_config
    read -p "Установка завершена. Нажмите Enter..."
}

update_image() {
    echo -e "\n${YELLOW}[*] Обновление образа nineseconds/mtg:2...${NC}"

    if docker ps | grep -q "mtproto-proxy"; then
        # Сохраняем текущие настройки
        SECRET=$(docker inspect mtproto-proxy --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
        PORT=$(docker inspect mtproto-proxy --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
        PORT=${PORT:-443}
        
        echo -e "${CYAN}Найдены активные настройки:${NC}"
        echo -e "  Порт: $PORT"
        echo -e "  Secret: $SECRET"
        echo ""

        echo -e "${YELLOW}[*] Остановка старого контейнера...${NC}"
        docker stop mtproto-proxy &>/dev/null
        docker rm mtproto-proxy &>/dev/null
        
        echo -e "${YELLOW}[*] Загрузка нового образа...${NC}"
        docker pull nineseconds/mtg:2

        echo -e "${YELLOW}[*] Запуск контейнера с сохраненными настройками...${NC}"
        docker run -d --name mtproto-proxy --restart always -p "$PORT":"$PORT" \
            nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$SECRET" > /dev/null
        
        echo -e "${GREEN}[OK] Обновление завершено!${NC}"
    else
        echo -e "${YELLOW}[*] Загрузка нового образа...${NC}"
        docker pull nineseconds/mtg:2
        echo -e "${GREEN}[OK] Образ обновлен!${NC}"
        echo -e "${CYAN}Прокси не был запущен. Настройте его в пункте меню 1.${NC}"
    fi
    
    read -p "Нажмите Enter..."
}

show_exit() {
    clear
    show_config
    exit 0
}

check_root
install_deps

while true; do
    echo -e "\n${MAGENTA}=== MTProto Manager  ===${NC}"
    echo -e "1) ${GREEN}Установить прокси (9seconds/mtg Proxy)${NC}"
    echo -e "2) Показать данные подключения${NC}"
    echo -e "3) ${RED}Удалить прокси${NC}"
    echo -e "4) ${CYAN}Обновить (9seconds/mtg Proxy)${NC}"
    echo -e "0) Выход${NC}"
    read -p "Пункт: " m_idx
    case $m_idx in
        1) menu_install ;;
        2) clear; show_config; read -p "Нажмите Enter..." ;;
        3) docker stop mtproto-proxy && docker rm mtproto-proxy && echo "Удалено" ;;
        4) update_image ;;
        0) show_exit ;;
        *) echo "Неверный ввод" ;;
    esac
done
