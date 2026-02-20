#!/usr/bin/env bash

unpack() {
  local file="${1:-}"
  local dest="${2:-.}"
  local file_lc
  local file_abs
  local out_file

  if [[ -z "$file" ]]; then
    echo "Usage: unpack <archive> [destination_dir]" >&2
    return 2
  fi

  if [[ ! -f "$file" ]]; then
    echo "'$file' is not a valid file" >&2
    return 1
  fi

  if [[ -e "$dest" && ! -d "$dest" ]]; then
    echo "'$dest' exists and is not a directory" >&2
    return 1
  fi

  if ! mkdir -p -- "$dest"; then
    echo "Cannot create destination directory: '$dest'" >&2
    return 1
  fi

  file_lc="${file,,}"
  if [[ "$file" = /* ]]; then
    file_abs="$file"
  else
    file_abs="$PWD/$file"
  fi

  case "$file_lc" in
    *.tar.bz2|*.tbz2)  tar -xjvf "$file_abs" -C "$dest" ;;
    *.tar.gz|*.tgz)    tar -xzvf "$file_abs" -C "$dest" ;;
    *.tar.xz|*.txz)    tar -xJvf "$file_abs" -C "$dest" ;;
    *.tar.zst|*.tzst)  tar --zstd -xvf "$file_abs" -C "$dest" ;;
    *.tar)             tar -xvf "$file_abs" -C "$dest" ;;

    *.bz2)
      out_file="$dest/$(basename -- "${file%.*}")"
      bzip2 -dc -- "$file_abs" >"$out_file"
      ;;
    *.gz)
      out_file="$dest/$(basename -- "${file%.*}")"
      gzip -dc -- "$file_abs" >"$out_file"
      ;;
    *.xz)
      out_file="$dest/$(basename -- "${file%.*}")"
      xz -dc -- "$file_abs" >"$out_file"
      ;;
    *.zst)
      out_file="$dest/$(basename -- "${file%.*}")"
      zstd -dc -- "$file_abs" >"$out_file"
      ;;

    *.zip)
      command -v unzip >/dev/null || { echo "unzip not found" >&2; return 127; }
      unzip -o -- "$file_abs" -d "$dest"
      ;;
    *.7z)
      command -v 7z >/dev/null || { echo "7z not found" >&2; return 127; }
      7z x -y -o"$dest" -- "$file_abs"
      ;;
    *.rar)
      command -v unrar >/dev/null || { echo "unrar not found" >&2; return 127; }
      unrar x -o+ -- "$file_abs" "$dest/"
      ;;

    *.z)
      out_file="$dest/$(basename -- "${file%.*}")"
      gzip -dc -- "$file_abs" >"$out_file"
      ;;
    *.ace)
      command -v unace >/dev/null || { echo "unace not found" >&2; return 127; }
      (
        cd -- "$dest" || exit 1
        unace x -- "$file_abs"
      )
      ;;
    *)
      echo "'$file' cannot be unpacked via unpack()" >&2
      return 3
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  unpack "$@"
fi
