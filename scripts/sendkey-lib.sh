#!/usr/bin/env bash
# sendkey-lib.sh — source this to get the sk() and line() helpers
# Supports full ASCII including uppercase letters, common punctuation
# Usage: source sendkey-lib.sh; DOMAIN=my-vm; line "some command"

DOMAIN="${DOMAIN:-}"
CONNECT="${CONNECT:---connect qemu:///system}"

sk() { sudo virsh $CONNECT send-key "$DOMAIN" "$@"; sleep 0.12; }

line() {
  local text="$1"
  for (( i=0; i<${#text}; i++ )); do
    local ch="${text:$i:1}"
    case "$ch" in
      # Lowercase letters
      a) sk KEY_A ;; b) sk KEY_B ;; c) sk KEY_C ;; d) sk KEY_D ;;
      e) sk KEY_E ;; f) sk KEY_F ;; g) sk KEY_G ;; h) sk KEY_H ;;
      i) sk KEY_I ;; j) sk KEY_J ;; k) sk KEY_K ;; l) sk KEY_L ;;
      m) sk KEY_M ;; n) sk KEY_N ;; o) sk KEY_O ;; p) sk KEY_P ;;
      q) sk KEY_Q ;; r) sk KEY_R ;; s) sk KEY_S ;; t) sk KEY_T ;;
      u) sk KEY_U ;; v) sk KEY_V ;; w) sk KEY_W ;; x) sk KEY_X ;;
      y) sk KEY_Y ;; z) sk KEY_Z ;;
      # Uppercase letters (Shift + key)
      A) sk KEY_LEFTSHIFT KEY_A ;; B) sk KEY_LEFTSHIFT KEY_B ;;
      C) sk KEY_LEFTSHIFT KEY_C ;; D) sk KEY_LEFTSHIFT KEY_D ;;
      E) sk KEY_LEFTSHIFT KEY_E ;; F) sk KEY_LEFTSHIFT KEY_F ;;
      G) sk KEY_LEFTSHIFT KEY_G ;; H) sk KEY_LEFTSHIFT KEY_H ;;
      I) sk KEY_LEFTSHIFT KEY_I ;; J) sk KEY_LEFTSHIFT KEY_J ;;
      K) sk KEY_LEFTSHIFT KEY_K ;; L) sk KEY_LEFTSHIFT KEY_L ;;
      M) sk KEY_LEFTSHIFT KEY_M ;; N) sk KEY_LEFTSHIFT KEY_N ;;
      O) sk KEY_LEFTSHIFT KEY_O ;; P) sk KEY_LEFTSHIFT KEY_P ;;
      Q) sk KEY_LEFTSHIFT KEY_Q ;; R) sk KEY_LEFTSHIFT KEY_R ;;
      S) sk KEY_LEFTSHIFT KEY_S ;; T) sk KEY_LEFTSHIFT KEY_T ;;
      U) sk KEY_LEFTSHIFT KEY_U ;; V) sk KEY_LEFTSHIFT KEY_V ;;
      W) sk KEY_LEFTSHIFT KEY_W ;; X) sk KEY_LEFTSHIFT KEY_X ;;
      Y) sk KEY_LEFTSHIFT KEY_Y ;; Z) sk KEY_LEFTSHIFT KEY_Z ;;
      # Digits
      0) sk KEY_0 ;; 1) sk KEY_1 ;; 2) sk KEY_2 ;; 3) sk KEY_3 ;;
      4) sk KEY_4 ;; 5) sk KEY_5 ;; 6) sk KEY_6 ;; 7) sk KEY_7 ;;
      8) sk KEY_8 ;; 9) sk KEY_9 ;;
      # Common punctuation
      ' ') sk KEY_SPACE ;;
      '-') sk KEY_MINUS ;;
      '_') sk KEY_LEFTSHIFT KEY_MINUS ;;
      '=') sk KEY_EQUAL ;;
      '+') sk KEY_LEFTSHIFT KEY_EQUAL ;;
      '.') sk KEY_DOT ;;
      ',') sk KEY_COMMA ;;
      '/') sk KEY_SLASH ;;
      '?') sk KEY_LEFTSHIFT KEY_SLASH ;;
      ':') sk KEY_LEFTSHIFT KEY_SEMICOLON ;;
      ';') sk KEY_SEMICOLON ;;
      "'") sk KEY_APOSTROPHE ;;
      '"') sk KEY_LEFTSHIFT KEY_APOSTROPHE ;;
      '`') sk KEY_GRAVE ;;
      '~') sk KEY_LEFTSHIFT KEY_GRAVE ;;
      '[') sk KEY_LEFTBRACE ;;
      ']') sk KEY_RIGHTBRACE ;;
      '{') sk KEY_LEFTSHIFT KEY_LEFTBRACE ;;
      '}') sk KEY_LEFTSHIFT KEY_RIGHTBRACE ;;
      '\') sk KEY_BACKSLASH ;;
      '|') sk KEY_LEFTSHIFT KEY_BACKSLASH ;;
      '!') sk KEY_LEFTSHIFT KEY_1 ;;
      '@') sk KEY_LEFTSHIFT KEY_2 ;;
      '#') sk KEY_LEFTSHIFT KEY_3 ;;
      '$') sk KEY_LEFTSHIFT KEY_4 ;;
      '%') sk KEY_LEFTSHIFT KEY_5 ;;
      '^') sk KEY_LEFTSHIFT KEY_6 ;;
      '&') sk KEY_LEFTSHIFT KEY_7 ;;
      '*') sk KEY_LEFTSHIFT KEY_8 ;;
      '(') sk KEY_LEFTSHIFT KEY_9 ;;
      ')') sk KEY_LEFTSHIFT KEY_0 ;;
      '<') sk KEY_LEFTSHIFT KEY_COMMA ;;
      '>') sk KEY_LEFTSHIFT KEY_DOT ;;
    esac
  done
  sk KEY_ENTER
  sleep 0.4
}
