# ansible_auto_auditd

Автономный Ansible-проект для установки и базовой настройки `auditd` по заданному сценарию.

## Что делает
- Поддерживает Debian/Ubuntu, Arch Linux, RHEL/Alma/Rocky (через `ansible_os_family`).
- Проверяет `auditctl -s` и ставит нужные пакеты.
- Проверяет и запускает `auditd` (`enable --now` логика).
- Проверяет kernel cmdline на `audit=0`/`audit=1`.
- Применяет `auditd.conf` строго по вашему шаблону.
- Создает и заполняет `/etc/audit/rules.d/server.rules` строго вашими правилами.
- Выполняет `augenrules --load` и показывает `auditctl -l`.
- На каждом шаге печатает `START/END` и понятный статус в терминал.

## Структура
- `ansible.cfg`
- `inventory/hosts.ini`
- `group_vars/all.yml`
- `auditd_baseline.yaml`
- `roles/auditd/`

## Быстрый старт
1. Заполните `inventory/hosts.ini`:
   ```ini
   [auditd]
   my-server ansible_host=203.0.113.10 ansible_user=admin ansible_become=true ansible_become_method=sudo ansible_ssh_private_key_file=~/.ssh/id_rsa
   ```
2. Запустите playbook:
   ```bash
   cd ansible_auto_auditd
   ansible-playbook auditd_baseline.yaml
   ```
3. Если для `sudo` нужен пароль:
   ```bash
   ansible-playbook auditd_baseline.yaml -K
   ```

## SSH-ключ
1. Приватный ключ разместите на машине, откуда запускаете Ansible, в `~/.ssh/id_rsa` (или укажите другой путь в `ansible_ssh_private_key_file`).
2. Убедитесь, что права на приватный ключ ограничены: `chmod 600 ~/.ssh/id_rsa`.
3. Публичный ключ должен быть добавлен на целевом сервере в `/home/admin/.ssh/authorized_keys` для пользователя `admin`.
4. Проверить SSH-доступ до запуска playbook:
   ```bash
   ansible -i inventory/hosts.ini auditd -m ping
   ```

## Переменные
- `auditd_fail_when_kernel_disabled` (по умолчанию `false`):
  - `false` -> при `audit=0` будет предупреждение, но playbook продолжит работу.
  - `true` -> playbook завершится с ошибкой, если найден `audit=0`.
- `auditd_log_tail_lines` (по умолчанию `20`) — сколько строк лога показывать в шаге проверки логов.

## Важно
- Для `audit=0` автоматическое изменение GRUB не выполняется специально, чтобы не вносить рискованных изменений в загрузчик.
- Если нужно жесткое требование к kernel audit, включите `auditd_fail_when_kernel_disabled: true`.
- В playbook есть отдельная pre-check проверка `sudo` (`id -u` с `become`) для раннего и явного контроля прав.
