# Catatan Sistem SI-KARHUTLA

> Diperbarui: 18 Oktober 2026

## 1. Struktur Proyek

```
SI-KARHUTLA/
├── index.html                                   ← SISTEM BARU (aktif, sudah dites)
├── data/snapshot.js                             ← data titik panas nyata (hasil build)
├── tools/build_snapshot.pl                      ← pembangun snapshot dari file BMKG
├── indonesia_wildfire_hotspot_dashboard.html    ← versi lama (arsip/demo, data hardcode)
└── redmi.md                                     ← catatan ini
```

**Cara pakai:** buka `index.html` di browser (boleh dobel-klik, tidak perlu server).
Tampilan otomatis memuat snapshot, lalu mencoba menyegarkan data langsung dari BMKG.

---

## 2. Sistem Lama (arsip) — ringkasan

Satu file HTML dashboard karhutla: Leaflet + Chart.js + Tailwind + Gemini AI.
Isinya **12 titik panas hardcode** (bukan data nyata), tren 7 hari fiktif, API key Gemini
kosong (`const apiKey = ""`) sehingga fitur AI mati, dan kartu "Provinsi Terparah"/"Risiko Asap"
tidak pernah dihitung. Dipertahankan hanya sebagai arsip referensi UI.

---

## 3. Sistem Baru (`index.html`) — yang sudah dikerjakan

### A. Data benar-benar nyata
| Kebutuhan | Sumber | Status |
|---|---|---|
| Titik panas | **BMKG CEWS** `https://cews.bmkg.go.id/tempatirk/HOTSPOT/YYYYMMDD/hotspot_YYYYMMDD.txt` (TSV: bujur, lintang, kepastian, prov/kab/kec, satelit, waktu) | ✅ live |
| Cuaca per titik | **Open-Meteo** (suhu, lembab, angin, jarak pandang, curah hujan) — CORS `*`, tanpa API key | ✅ live |
| Kualitas udara | **Open-Meteo Air Quality** (PM2.5 + US AQI) | ✅ live |
| Arah angin nasional | Open-Meteo multi-lokasi (grid 7×16 = 112 titik, 1 request) | ✅ live |
| Batas provinsi | GeoJSON 38 provinsi (raw.githubusercontent, ACAO `*`) | ✅ live |
| Citra harian NASA | **NASA APOD** `https://api.nasa.gov/planetary/apod` (Astronomy Picture of the Day, API key gratis) | ✅ live |
| Riwayat 7 hari | Snapshot hasil pengunduhan file BMKG 11–17 Okt 2026 | ✅ ter-embed |

**Hasil data teruji (17 Okt 2026):** 13.275 baris mentah → **5.374 titik unik** (dedup 0,01°),
33 provinsi, 247 kabupaten, 966 kecamatan. Teratas: Papua Selatan 1.409 · Kalimantan Tengah 1.296.

### B. Pipeline data
`tools/build_snapshot.pl` — mengubah file TSV BMKG menjadi `data/snapshot.js`
(kamus prov/kab/kec + array titik terkompresi ±233 KB, format ringkas `[lon,lat,conf,iProv,iKab,iKec,iSat,waktu]`).

```bash
# unduh file harian lalu build ulang snapshot
curl -o /tmp/hs_20261017.txt https://cews.bmkg.go.id/tempatirk/HOTSPOT/20261017/hotspot_20261017.txt
perl tools/build_snapshot.pl /tmp/hs_*.txt
```

### C. Refresh live (tanpa server)
Browser tidak boleh memanggil BMKG langsung (CORS), jadi ada rantai proxy:
1. `r.jina.ai` — **satu-satunya yang mengizinkan origin `null` (file://)**, terbukti jalan
2. `api.cors.lol` — fallback (ACAO `*`, punya rate limit)
3. `allorigins` / `codetabs` — hanya dipakai bila dibuka lewat `http://` (server lokal)

Halaman mencoba tanggal hari ini mundur 4 hari; bila semua gagal → tetap memakai snapshot
dan status berubah menjadi "Snapshot … (jaringan live belum tersedia)". Refresh otomatis tiap 15 menit.

### D. Peta menyesuaikan titik koordinat
- `fitBounds(dataBounds)` saat load → peta langsung pas dengan sebaran titik api
- Tombol **"Fokus ke titik api"** untuk kembali ke sebaran data
- 5.374 titik dimasukkan ke **MarkerCluster** (bola berwarna sesuai risiko tertinggi di dalamnya)
- Layer: titik, batas provinsi (klik provinsi → tabel otomatis terfilter), heatmap, panah angin grid, jalur asap
- 3 peta dasar: gelap / satelit / terang

### E. Bahasa awam (mudah dipahami)
- Legenda langsung di peta: **merah = hampir pasti api (9/10)**, **kuning = kemungkinan besar (8/10)**,
  **biru = perlu dicek petugas (7/10)**, **poligon jingga = perkiraan jalur asap**
- Banner peringatan berbahasa biasa: jumlah titik, wilayah terdampak, perubahan dari hari sebelumnya,
  arah angin dominan → arah sebaran asap, saran warga
- Panel detail: cuaca nyata, AQI dengan label sederhana ("Tidak sehat", "Berbahaya"), kalimat
  *"Angin bertiup dari Selatan … asap bergerak ke arah Utara sejauh ±20 km"*
- Kartu status nasional: AMAN / SIAGA / WASPADA / BAHAYA TINGGI dengan aturan ambang jelas
- Bagian "Panduan singkat untuk masyarakat" (apa itu titik panas, arti 7/8/9, yang harus dilakukan)
- Kapitalisasi nama wilayah otomatis ("PAPUA SELATAN" → "Papua Selatan")

### F. Analisis AI
- Tanpa API key → **analisis lokal** (aturan) sehingga tombol selalu berfungsi
- Dengan API key → Google Gemini (key & model diinput via modal Pengaturan, disimpan di `localStorage`,
  tidak ada key yang ditulis di source code)
- Mode dipakai selalu ditampilkan, dan selalu ada fallback bila panggilan Gemini gagal
- Tombol putar suara (Web Speech API `id-ID`) tetap ada

### G. Fitur lain
- 3 grafik (tren 7 hari, provinsi terdampak bertingkat, donat kepastian) — dihitung dari data nyata
- Tabel: cari kabupaten/kecamatan, filter provinsi & tingkat risiko, paginasi 25 baris, ekspor CSV
- Cuaca di-cache per lokasi, panel ikut berubah saat titik lain dipilih

### H. Hasil tes (Chrome headless)
- `mTotal` 5.374 · `mProv` Papua Selatan · status **BAHAYA TINGGI** · tren +11% vs hari sebelumnya
- Panel terpilih: suhu 26,3 °C, AQI 177 (Tidak sehat), plume polygon tergambar (2 layer)
- Live refresh sukses dari `file://` → status "Data langsung BMKG 2026-10-17"
- Tidak ada error JavaScript di console (hanya pesan CORS dari proxy cadangan yang memang tidak dipakai)

---

## 4. Masih perlu dikerjakan (prioritas)

| No | Ide | Dampak | Usaha |
|----|-----|--------|-------|
| 1 | Filter tanggal di UI (pilih hari dalam 7 hari terakhir dari snapshot / unduh harian lewat proxy) | ★★★★ | Sedang |
| 2 | Grid batas kabupaten (514 wilayah) untuk hitung "kabupaten dalam jalur asap" otomatis | ★★★★★ | Besar |
| 3 | Peringatan otomatis (notification) bila titik merah baru muncul dekat lokasi pengguna (Geolocation) | ★★★★ | Sedang |
| 4 | Model asap lebih ilmiah (PASQUILL-GIFFORD / HYSPLIT) + angin tinggi 850 hPa dari BMKG | ★★★★ | Besar |
| 5 | PWA + service worker (bisa dibuka offline di lapangan, data snapshot sudah tersimpan) | ★★★★ | Sedang |
| 6 | Integrasi ISPU resmi BMKG (bukan hanya US AQI Open-Meteo) | ★★★ | Kecil |
| 7 | Simpan riwayat harian otomatis (localStorage) supaya tren 7 hari ikut hidup saat live | ★★★ | Kecil |
| 8 | Sumber tambahan: NASA FIRMS (butuh MAP_KEY gratis) & SiPongi+ untuk perbandingan/validasi ganda | ★★★★ | Sedang |
| 9 | Grafik perbandingan antar-tahun (musim karhutla 2015/2019/2023/2026) | ★★★ | Besar |
| 10 | Catatan/status penanganan per titik (workflow posko: terdeteksi → diverifikasi → selesai) | ★★★ | Besar |

### Catatan teknis penting
- **API key tidak boleh ditulis di HTML** — bila butuh backend, pakai proxy kecil (Node/Python) dan
  simpan key di environment variable.
- Data BMKG berubah per hari (file `hotspot_YYYYMMDD.txt` muncul setelah overpass); pagi hari file
  tanggal hari ini belum tentu ada → sistem otomatis mundur ke hari sebelumnya.
- Kepastian BMKG memakai skala 0–10 (nilai yang muncul hanya 7, 8, 9) — bukan persen FIRMS.
- Suami NPP/SNPP akan dihentikan NASA 2 Nov 2026 → data berpindah ke NOAA-20/21; kolom satelit
  di sistem sudah memuat semua, hanya perlu pembaruan nama sensor di teks jika perlu.

---

## 5. Kesimpulan

Sistem sudah berubah dari **demo UI dengan data palsu** menjadi **portal informasi berbasis data nyata
BMKG + Open-Meteo** yang bisa dibuka langsung di browser, memvisualkan seluruh titik api Indonesia
sesuai koordinat asli, menjelaskan risiko dalam bahasa sehari-hari, dan tetap menampilkan data
terakhir meskipun jaringan live gagal.
