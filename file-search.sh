#!/usr/bin/env bash
SEARCH_DIR="$HOME"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMPTY_IMAGE="$SCRIPT_DIR/empty.png"

EXCLUDE_DIRS=(".git" "node_modules" ".cache" "/proc" "/run" "/tmp" "/var/cache")

FD_EXCLUDES=()
RG_EXCLUDES=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  FD_EXCLUDES+=(--exclude "$dir")
  RG_EXCLUDES+=(--glob "!$dir")
done

# Функция для превью файлов
preview_file() {
  local file="$1"
  local mime_type=$(file --mime-type -b "$file" 2>/dev/null)

  case "$mime_type" in
  image/*)
    echo -e "\n\033[1;36m📸 Изображение:\033[0m $file"
    echo -e "\033[1;33m📊 MIME тип:\033[0m $mime_type"
    echo -e "\033[1;33m📊 Размер:\033[0m $(identify -format '%wx%h' "$file" 2>/dev/null || echo 'неизвестно')"
    echo

    kitty icat --clear --transfer-mode=memory --stdin=no --place="${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - 6))@0x0" "$file"
    ;;
  video/*)
    echo -e "\033[1;35m🎥 Видео файл:\033[0m $file"
    echo -e "\033[1;33m📊 MIME тип:\033[0m $mime_type"
    echo -e "\033[1;33m💾 Размер:\033[0m $(stat -c%s "$file" 2>/dev/null | numfmt --to=iec || echo 'неизвестно')"
    kitty icat --clear --transfer-mode=memory --stdin=no "$EMPTY_IMAGE"
    ;;
  audio/*)
    echo -e "\033[1;34m🎵 Аудио файл:\033[0m $file"
    echo -e "\033[1;33m📊 MIME тип:\033[0m $mime_type"
    echo -e "\033[1;33m💾 Размер:\033[0m $(stat -c%s "$file" 2>/dev/null | numfmt --to=iec || echo 'неизвестно')"
    kitty icat --clear --transfer-mode=memory --stdin=no "$EMPTY_IMAGE"
    ;;
  application/pdf)
    echo -e "\033[1;31m📕 PDF документ:\033[0m $file"
    echo -e "\033[1;33m📊 MIME тип:\033[0m $mime_type"
    echo -e "\033[1;33m💾 Размер:\033[0m $(stat -c%s "$file" 2>/dev/null | numfmt --to=iec || echo 'неизвестно')"
    kitty icat --clear --transfer-mode=memory --stdin=no "$EMPTY_IMAGE"

    ;;
  text/* | application/json | application/xml | application/javascript | application/x-sh | application/x-shellscript)
    # Для текстовых файлов используем bat
    bat --color=always --style=numbers --line-range=:100 "$file" 2>/dev/null || head -n 100 "$file"
    kitty icat --clear --transfer-mode=memory --stdin=no "$EMPTY_IMAGE"
    ;;
  *)
    # Для остальных файлов показываем базовую информацию
    echo -e "\033[1;37m📄 Файл:\033[0m $(basename "$file")"
    echo -e "\033[1;33m📁 Полный путь:\033[0m $file"
    echo -e "\033[1;33m📊 MIME тип:\033[0m $mime_type"
    echo -e "\033[1;33m💾 Размер:\033[0m $(stat -c%s "$file" 2>/dev/null | numfmt --to=iec || echo 'неизвестно')"

    kitty icat --clear --transfer-mode=memory --stdin=no "$EMPTY_IMAGE"
    ;;
  esac
}

# функция открытия файла
open_file() {

  echo "Открываю файл: $1" >&2
  local file="$1"
  [[ -f "$file" ]] || {
    echo "Нет файла: $file" >&2
    return 1
  }
  local mime
  mime=$(file --mime-type -b "$file")

  case "$mime" in
  text/*)
    kitty --class editterm --config /dev/null -e bash -lc "nvim '$file'" 2>/dev/null &
    ;;
  image/*)
    imv "$file" 2>/dev/null &
    ;;
  video/*)
    vlc "$file" 2>/dev/null &
    ;;
  application/pdf)
    zathura "$file" 2>/dev/null &
    ;;
  audio/*)
    vlc "$file" &
    ;;
  *)
    echo "$file" | wl-copy -n
    notify-send "Path to file copy to clipboard" "$(basename "$file")" -i clipboard -t 1500
    echo "Скопировано: $file" >&2
    ;;
  esac
}

# экспортируем функцию для дочерних shell
export -f open_file
export -f preview_file

SHELL=$(which bash)
# Меню выбора режима
choice=$(printf "🔍 Поиск по имени файлов\n🧠 Поиск по содержимому" |
  fzf --prompt="Выбери режим > ")

case "$choice" in
"🔍 Поиск по имени файлов")
  fd "" "$SEARCH_DIR" --type f --hidden --no-ignore "${FD_EXCLUDES[@]}" 2>/dev/null |
    fzf --ansi --height=100% \
      --preview 'preview_file {}' \
      --bind "enter:execute:open_file {}" \
      --prompt "файл > " \
      --preview-window=right:70% \
      --bind="focus:transform-preview-label:echo [ {} ]" \
      --bind="ctrl-p:toggle-preview+transform-preview-label:echo [ {} ]"
  ;;
"🧠 Поиск по содержимому")
  query=$(
    echo "" | fzf --print-query \
      --prompt "🔍 Введите текст для поиска: " \
      --header="╭─ ПОИСК ПО СОДЕРЖИМОМУ ───────────────────╮
│ Введите текст и нажмите Enter для поиска │
╰──────────────────────────────────────────╯" \
      --border=rounded \
      --color='prompt:226,header:39'
  )
  # Берем только первую строку (введенный запрос)
  query=$(echo "$query" | head -1)
  [ -z "$query" ] && exit 0

  rg --hidden --no-ignore --no-heading --line-number --color=always "${RG_EXCLUDES[@]}" "$query" "$SEARCH_DIR" 2>/dev/null |
    fzf --ansi \
      --delimiter : \
      --nth 3.. \
      --preview 'bat --color=always --highlight-line {2} {1}' \
      --bind "enter:execute:open_file {1}" \
      --prompt "Результаты > " \
      --preview-window=right:70% \
      --bind="focus:transform-preview-label:echo [ {1} ]" \
      --bind="ctrl-p:toggle-preview+transform-preview-label:echo [ {1} ]" \
      --bind 'ctrl-c:abort'
  ;;
esac
