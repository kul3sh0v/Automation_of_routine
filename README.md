# find_content_files 
A simple Python utility that searches for a given string across all files in a directory 
and highlights the results in the console.

Простая утилита на Python, которая ищет заданную строку во всех файлах в каталоге 
и выделяет результаты в консоли.


## Возможности

- Поиск строки во **всех файлах** указанной директории (включая вложенные папки)  
- Подсветка найденных совпадений в **зелёный цвет**  
- Отображение **контекста** вокруг найденной строки (по умолчанию ±10 символов)  
- Поддержка **UTF-8** кодировки файлов  


## Как работает

1. Укажите папку для поиска (`DIRECTORY`)
2. Укажите строку, которую нужно найти (`FIND_STRING`)
3. Скрипт проходит по всем файлам, считывает их содержимое и ищет совпадения.
4. Если строка найдена, выводится:
   - путь к файлу,
   - небольшой фрагмент текста вокруг совпадения,
   - найденная строка подсвечена цветом.

---

# rename_files
A simple Python utility that renames files in a directory according to specific naming conventions.

Простая утилита на Python, которая переименовывает файлы в каталоге по заданным правилам.


## Возможности

- Рекурсивная обработка **всех файлов** в указанной директории (включая вложенные папки)  
- Замена теста в имени по шаблонам:  
- Безопасное переименование с сохранением расширения  


## Как работает

1. Укажите папку с файлами для переименования (`DIRECTORY`)
2. Укажите все необхадимые шаблоны в функции get_valid_name
3. Скрипт проходит по всем файлам в указанной директории и подкаталогах.
4. Для каждого файла применяются замены по шаблонам.
5. Изменения применяются **напрямую** — резервная копия не создаётся.


## Важно

> **Перед запуском обязательно сделайте резервную копию папки!**  
> Скрипт вносит **необратимые изменения** в имена файлов.

---

# ansible_auto_vpn
Авто-развертывание VPN на Ansible Xray VLESS+Reality под Ubuntu с выгрузкой клиентских артефактов.
Подробности и запуск: [ansible_auto_vpn](ansible_auto_vpn/README.md)

---

# unpack.sh
Bash-функция `unpack`, которая распаковывает архив по расширению файла.
Поддерживаются популярные форматы: `tar.*`, `zip`, `7z`, `rar`, `gz`, `bz2`, `xz`, `zst`.
Можно передать второй аргумент — каталог назначения для распаковки.

## Использование

```bash
# запуск файла как исполняемого скрипта
./unpack.sh archive.tar.gz ./output
./unpack.sh docs.zip /tmp/unpack_here

# или как функцию в текущей shell-сессии
source unpack.sh
unpack archive.tar.gz ./output
unpack docs.zip
```

## Коды возврата

- `0` — успешно
- `1` — файл не найден или это не файл
- `2` — не передан аргумент (`unpack <archive> [destination_dir]`)
- `3` — неподдерживаемый формат
- `127` — не установлена нужная утилита для распаковки (`unzip`, `7z`, `unrar` и т.д.)

---

# healthcheck.sh
Утилита для быстрого SRE health-check локального или удаленного (SSH) Linux-хоста.
Проверяет состояние сервиса и базовые системные показатели, может выводить результат в текстовом формате или JSON.

## Что проверяет

- `load average` с учетом числа CPU (`warning >= 1.5 * CPU`, `critical >= 2 * CPU`)
- использование диска `/` (`warning >= 80%`, `critical >= 90%`)
- использование inode `/` (`warning >= 80%`, `critical >= 90%`)
- доступную память (`warning < 15%`, `critical < 8%`)
- `systemctl is-active <service>` (если передан `--service`)
- `systemctl is-enabled <service>` (если передан `--service`)
- слушается ли `--check-port` через `ss -lnt` (если передан `--check-port`)
- TCP подключение к `127.0.0.1:<check-port>` (если передан `--check-port`)

## Аргументы

- `--mode local|ssh` — режим работы, по умолчанию `local`
- `--host HOST` — удаленный хост (обязателен при `--mode ssh`)
- `--user USER` — SSH пользователь
- `--port-ssh PORT` — SSH порт, по умолчанию `22`
- `--identity PATH` — путь к SSH ключу
- `--service NAME` — имя systemd-сервиса (опционально)
- `--check-port PORT` — порт для сетевых проверок (опционально)
- `--timeout SEC` — timeout для сетевых операций, по умолчанию `3`
- `--json` — вывод в JSON
- `-h`, `--help` — справка

## Примеры

```bash
# базовая локальная проверка хоста
./healthcheck.sh

# JSON-вывод для интеграции в мониторинг/cron
./healthcheck.sh --json

# проверка конкретного сервиса и порта
./healthcheck.sh --service nginx --check-port 8443

# проверка удаленного хоста с нестандартным SSH-портом и ключом
./healthcheck.sh --mode ssh --host 203.0.113.10 --user ubuntu --port-ssh 2222 --identity ~/.ssh/id_rsa --json
```

## Коды возврата

- `0` — все проверки `OK`
- `1` — есть `WARN`, но нет `CRITICAL`
- `2` — есть `CRITICAL`
- `3` — ошибка аргументов или иная ошибка запуска

---

# incident_bundle.py
Утилита для сбора инцидентных артефактов в отдельную папку и архив `tar.gz`.
Работает локально или через SSH и сохраняет `manifest.json` с результатами всех шагов.

## Что собирает

- `hostnamectl`
- `date -Is`
- `uptime`
- `journalctl -p err --since <since> --no-pager`
- `dmesg -T | tail -n 400`
- `ss -tulpen`
- `df -h`
- `df -i`
- `free -m`
- `journalctl -u <service> --since <since> --no-pager` (если передан `--service`)
- `systemctl status <service> --no-pager` (если передан `--service`)
- `systemctl show <service> -p ActiveState,SubState,ExecMainStatus,ExecMainStartTimestamp` (если передан `--service`)
- дополнительные файлы из `--include` (если файл существует и доступен для чтения)

## Аргументы

- `--mode local|ssh` — режим работы, по умолчанию `local`
- `--host HOST` — удаленный хост (обязателен при `--mode ssh`)
- `--user USER` — SSH пользователь
- `--port-ssh PORT` — SSH порт, по умолчанию `22`
- `--identity PATH` — путь к SSH ключу
- `--service NAME` — имя сервиса (опционально)
- `--since PERIOD` — период для `journalctl`, по умолчанию `2h`
- `--out DIR` — каталог вывода, по умолчанию `./bundles`
- `--include PATH1,PATH2` — CSV-список файлов для включения (опционально)
- `-h`, `--help` — справка

## Структура результатов

```text
<out>/incident_<target>_<YYYYmmdd_HHMMSS>/
  commands/
    *.log
  files/
    *.txt
  manifest.json

<out>/incident_<target>_<YYYYmmdd_HHMMSS>.tar.gz
```

`manifest.json` содержит:
- `target`, `mode`, `service`, `since`
- `started_at`, `finished_at`, `duration_ms`
- `command_results` (команда, код возврата, длительность, размер stdout/stderr)
- `included_files` (путь, собран/не собран, причина)
- `overall_status` (`ok` | `partial` | `error`)

## Примеры

```bash
# локальный сбор с параметрами по умолчанию
python3 incident_bundle.py

# локальный сбор с сервисом и include-списком
python3 incident_bundle.py --mode local --service nginx --since "4h" --out ./bundles --include "/etc/hosts,/etc/nginx/nginx.conf"

# удаленный сбор по SSH
python3 incident_bundle.py --mode ssh --host 203.0.113.10 --user ubuntu --service nginx --since "2h" --out ./bundles

# удаленный сбор с ключом и нестандартным SSH-портом
python3 incident_bundle.py --mode ssh --host 203.0.113.10 --user ubuntu --port-ssh 2222 --identity ~/.ssh/id_rsa
```

## Коды возврата

- `0` — сбор полностью успешен (`overall_status = ok`)
- `1` — частичный успех (`overall_status = partial`)
- `2` — фатальная ошибка (`overall_status = error` или невозможность запуска/доступа)
