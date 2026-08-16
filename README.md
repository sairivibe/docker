# SAIRI

Docker image serbaguna berbasis `debian:bullseye-slim` yang sudah dilengkapi banyak runtime dan tools populer, siap pakai untuk development, automation, atau environment container (mis. panel hosting berbasis container seperti Pterodactyl/Pelican).

## Fitur / Yang Terpasang
 
- **Bahasa & Runtime**
  - Node.js (versi dapat diatur lewat env `NODE_VERSION`, terinstall otomatis saat container start)
  - Bun
  - Go `1.24.0`
  - Python `3.13.0`
  - PHP `8.3` (via repo Sury/Ondřej, mendukung multi-versi PHP)
  - Java (Eclipse Temurin/Adoptium) `21`
- **Package manager**: npm, pnpm, yarn, pm2, Composer
- **Database client**: `mysql` — hanya client, tidak menjalankan server database di dalam container
- **Tools umum**: git, curl, wget, zip/unzip, tar, jq, nano, vim, figlet, net-tools, dll
- **Media**: ffmpeg, imagemagick, graphicsmagick, webp, mediainfo
- **Automation/Browser**: Playwright (beserta dependency browser)
- **Networking**: Cloudflare Tunnel (`cloudflared`)

## Environment Variables

| Variabel | Deskripsi | Contoh |
|---|---|---|
| `NODE_VERSION` | Versi Node.js yang ingin diinstall/diaktifkan saat container start | `20`, `v20.11.0` |
| `ENABLE_CF_TUNNEL` | Set `true`/`1` untuk mengaktifkan Cloudflare Tunnel otomatis | `true` |
| `CF_TOKEN` | Token tunnel Cloudflare (wajib jika `ENABLE_CF_TUNNEL` aktif) | `xxxxxxxx` |
| `ENABLE_PHP_WEB` | Set `true`/`1` untuk mengaktifkan Nginx + PHP-FPM (dikelola Supervisor) | `true` |
| `SERVER_PORT` | Port yang dipakai Nginx untuk serve PHP web app (biasanya otomatis diisi Pterodactyl) | `8080` |
| `WEB_ROOT` | Folder root aplikasi PHP (document root Nginx) | `/home/container/public` |

## PHP-FPM + Nginx

Image ini sudah menyertakan **Nginx** dan **PHP-FPM**, dijalankan bersamaan lewat **Supervisor** (bukan `php -S` built-in server), supaya lebih cocok untuk beban production dan tetap kompatibel dengan model satu-proses-utama ala Pterodactyl.

Cara pakai:
1. Set env `ENABLE_PHP_WEB=true` di panel Pterodactyl (Startup Variables).
2. (Opsional) set `WEB_ROOT` kalau document root aplikasi kamu bukan `/home/container/public` (mis. Laravel: `/home/container/public` sudah pas karena itu nama folder public bawaan Laravel; framework lain sesuaikan).
3. `SERVER_PORT` biasanya sudah otomatis di-inject Pterodactyl sesuai alokasi port allocation kamu — nggak perlu diisi manual.
4. Jalankan container seperti biasa. Entrypoint akan otomatis generate config Nginx dari template, lalu start `supervisord` di background yang menjaga Nginx + PHP-FPM tetap hidup (auto-restart kalau crash).
5. Banner start-up akan menampilkan status `PHP-Web (Nginx+FPM): Aktif` beserta port & root yang dipakai.

Log tersedia di `/home/container/logs/` (nginx-access.log, nginx-error.log, php-fpm-error.log, supervisord.log, dll) — gampang dicek langsung dari file manager Pterodactyl karena semua di dalam `/home/container`.

**Catatan:** semua proses (Nginx + PHP-FPM + Supervisor) jalan sebagai user non-root `container`, sesuai model keamanan container Pterodactyl — nggak butuh privileged mode atau root.

## Cara Pakai

### Build image

```bash
docker build -t sairi .
```

### Jalankan container

```bash
docker run -it \
  -e NODE_VERSION=20 \
  -e ENABLE_CF_TUNNEL=false \
  sairi
```

Saat container berjalan, `entrypoint.sh` akan:
1. Menyiapkan/menginstall Node.js sesuai `NODE_VERSION` (jika diset).
2. Menjalankan Cloudflare Tunnel jika diaktifkan.
3. Menampilkan banner info sistem (OS, CPU, RAM, disk, dan versi masing-masing runtime).
4. Masuk ke shell interaktif (`bash`).

### Connect ke database eksternal

Client `mysql` dipakai untuk connect ke database MySQL/MariaDB yang jalan di luar container (mis. fitur Databases di Pterodactyl, atau database cloud lain):

```bash
mysql -h db-host -u user -p -e "SHOW DATABASES;"
```

## CI/CD

Repository ini menggunakan GitHub Actions (`.github/workflows/docker-publish.yml`) untuk build & push image secara otomatis ke GitHub Container Registry (`ghcr.io`) setiap kali ada push ke branch `main`, tag versi baru, atau sesuai jadwal harian.

## Lisensi

Proyek ini dilisensikan di bawah [MIT License](LICENSE).

## Author

**SairiDev**
Email: sairidev@gmail.com 
