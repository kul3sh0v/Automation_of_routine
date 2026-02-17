# Xray VLESS+Reality (Ansible)

## Что делает
- Ставит Xray на Ubuntu/Debian
- Настраивает VLESS+Reality
- Открывает порт через UFW
- Генерирует ключи/UUID/shortId при необходимости
- Выгружает клиентские артефакты на контроллер

## Быстрый старт
1) Заполните `inventory/hosts.ini`:
   ```ini
   [vpn]
   myserver ansible_host=IP ansible_user=ubuntu xray_domain=vpn.example.com
   ```
2) Укажите параметры в `group_vars/all.yml`
3) Запуск:
   ```bash
   ansible-playbook -i inventory/hosts.ini site.yml
   ```

Артефакты клиентов появятся в `artifacts/<host>/`.

## Теги
- `base` — установка пакетов
- `firewall` — настройка UFW
- `xray` — установка и настройка Xray
- `artifacts` — генерация клиентских конфигов
- `restart` — перезапуск Xray

### Примеры использования тегов
```bash
# Только перезапустить Xray
ansible-playbook -i inventory/hosts.ini site.yml --tags restart

# Только установить Xray без артефактов
ansible-playbook -i inventory/hosts.ini site.yml --tags xray

# Пропустить firewall
ansible-playbook -i inventory/hosts.ini site.yml --skip-tags firewall
```

## Важно
- Для Reality используйте реальный домен и подходящий `dest`/`serverNames`.
- Укажите домен в inventory (`xray_domain`) или в `group_vars/all.yml`.
- Если хотите фиксированные ключи/UUID — задайте `xray_uuid`, `xray_short_id`, `xray_private_key`, `xray_public_key` в `group_vars/all.yml`.
- SSH подключение по умолчанию использует `~/.ssh/id_rsa`.
