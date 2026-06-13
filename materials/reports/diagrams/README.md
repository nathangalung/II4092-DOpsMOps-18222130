# diagrams/ — diagram-as-code sources

Folder ini menampung seluruh sumber *diagram-as-code* laporan TA dalam format
eraser.io (`.eraser`), analog dengan `tables/` untuk tabel. PNG hasil render
tetap berada di `figures/` dan hanya berkas itu yang di-`\includegraphics` oleh
LaTeX; berkas `.eraser` di sini adalah sumber kebenarannya.

## Aturan

1. Satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di
   `figures/` (contoh: `Integrate_General_Arch.eraser` ->
   `figures/Integrate_General_Arch.png`).
2. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu.
3. Setiap node pada diagram arsitektur harus menamai tool yang benar-benar ada
   di `platform/components/`; jangan menghidupkan kembali node era proposal
   (Raystack, Kong, Redis Stack, Jaeger).
4. Diagram untuk bab mana pun (bukan hanya Bab III/IV) boleh ditaruh di sini
   selama mengikuti aturan penamaan di atas.

## Render ulang

1. Buka https://app.eraser.io lalu buat *diagram-as-code* baru.
2. Tempel isi berkas `.eraser`.
3. Ekspor PNG, timpa berkas padanannya di `figures/`.
4. Bangun ulang PDF (`make` di `materials/reports/`).

Konvensi lengkap: `WRITING_GUIDE.md` bagian 1.7 dan `TEMPLATE_BAB.md`.

## Isi saat ini

- `Fragment_General_Arch.eraser` — pandangan umum fragmentasi (Gambar III.1),
  status quo pra-platform: empat peran + tumpukan ad hoc generik, tanpa
  menamai komponen platform.
- `Integrate_General_Arch.eraser` — arsitektur umum platform (Gambar IV.1),
  tujuh lapisan Bab IV + empat peran pengguna + rantai GitOps.
