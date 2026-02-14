# Xray VLESS+Reality (Ansible)

## Что делает
- Ставит Xray на Ubuntu
- Настраивает VLESS+Reality
- Открывает порт через UFW
- Генерирует ключи/UUID/shortId при необходимости
- Выгружает клиентские артефакты на контроллер

## Быстрый старт
1) Заполните `ansible/inventory/hosts.ini`
2) Укажите домен и параметры в `ansible/group_vars/all.yml`
3) Запуск:

```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

Артефакты клиентов появятся в `ansible_auto_vpn/artifacts/<host>/`.

## Важно
- Для Reality используйте реальный домен и подходящий `dest`/`serverNames`.
- Если хотите фиксированные ключи/UUID — задайте `xray_uuid`, `xray_short_id`, `xray_private_key`, `xray_public_key` в `group_vars/all.yml`.
