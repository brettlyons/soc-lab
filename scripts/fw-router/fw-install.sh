#!/usr/bin/env bash
DOMAIN="fw-router"
C="--connect qemu:///system"
sk() { sudo virsh $C send-key "$DOMAIN" "$@"; sleep 0.12; }

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
      '>') sk KEY_LEFTSHIFT KEY_DOT ;;
      '_') sk KEY_LEFTSHIFT KEY_MINUS ;;
    esac
  done
  sk KEY_ENTER
  sleep 0.4
}

echo "[1] Running setup-alpine with answerfile..."
line "setup-alpine -f alpine-answers"

echo "    Waiting 45s for mirrors + reach password prompt..."
sleep 45

echo "[2] Root password (x2)..."
line "<fw-router-root-password>"
sleep 1
line "<fw-router-root-password>"
sleep 2

echo "[3] Confirm disk erase..."
line "y"

echo "    Waiting 4 min for packages + disk install..."
sleep 240

echo "[4] Post-install: fix sshd + reboot..."
line "mount /dev/vda3 /mnt"
sleep 2
line "sed -i s/prohibit-password/yes/ /mnt/etc/ssh/sshd_config"
sleep 1
line "umount /mnt"
sleep 1
line "reboot"

echo "Done. VM rebooting into installed Alpine."
