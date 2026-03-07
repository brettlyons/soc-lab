#!/usr/bin/env bash
DOMAIN="fw-router"
C="--connect qemu:///system"
sk() { sudo virsh $C send-key "$DOMAIN" "$@"; sleep 0.15; }

line() {
  local text="$1"
  for (( i=0; i<${#text}; i++ )); do
    local ch="${text:$i:1}"
    case "$ch" in
      a) sk KEY_A ;; b) sk KEY_B ;; c) sk KEY_C ;; d) sk KEY_D ;;
      e) sk KEY_E ;; f) sk KEY_F ;; g) sk KEY_G ;; h) sk KEY_H ;;
      i) sk KEY_I ;; j) sk KEY_J ;; k) sk KEY_K ;; l) sk KEY_L ;;
      m) sk KEY_M ;; n) sk KEY_N ;; o) sk KEY_O ;; p) sk KEY_P ;;
      q) sk KEY_Q ;; r) sk KEY_R ;; s) sk KEY_S ;; t) sk KEY_T ;;
      u) sk KEY_U ;; v) sk KEY_V ;; w) sk KEY_W ;; x) sk KEY_X ;;
      y) sk KEY_Y ;; z) sk KEY_Z ;;
      0) sk KEY_0 ;; 1) sk KEY_1 ;; 2) sk KEY_2 ;; 3) sk KEY_3 ;;
      4) sk KEY_4 ;; 5) sk KEY_5 ;; 6) sk KEY_6 ;; 7) sk KEY_7 ;;
      8) sk KEY_8 ;; 9) sk KEY_9 ;;
      ' ') sk KEY_SPACE ;;
      '-') sk KEY_MINUS ;;
      '.') sk KEY_DOT ;;
      '/') sk KEY_SLASH ;;
      ':') sk KEY_LEFTSHIFT KEY_SEMICOLON ;;
    esac
  done
  sk KEY_ENTER
  sleep 0.5
}

echo "[1] Logging in as root..."
sk KEY_ENTER
sleep 0.5
line "root"
sleep 0.5
line "<fw-router-root-password>"
sleep 1

echo "[2] Setting up authorized_keys..."
line "mkdir -p /root/.ssh"
sleep 0.3
line "wget http://192.168.122.1:8080/fw-router-key.pub -O /root/.ssh/authorized_keys"
sleep 4
line "chmod 700 /root/.ssh"
sleep 0.3
line "chmod 600 /root/.ssh/authorized_keys"
sleep 0.3

echo "[3] Done — trying SSH now..."
