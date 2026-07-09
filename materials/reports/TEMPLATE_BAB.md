# Template Per-Bab + Locked Chain

Dokumen ini menyimpan panduan template tiap bab yang sebelumnya tertulis langsung di dalam `chapters/Bab_*.tex`. Setelah isi sebenarnya ditulis, panduan asli tetap dapat ditelusuri di sini sehingga revisi berikutnya tidak kehilangan kerangka instruksi dari Prodi STI ITB. Baca dokumen ini bersama `WRITING_GUIDE.md` dan `README.md`.

## 1. Locked Chain (Rumusan Masalah → Tujuan → Bab IV → Bab V → Kesimpulan)

Platform Tugas Akhir ini bersifat domain-agnostic. *Use case* kripto hanya berperan sebagai kasus uji; semua rumusan masalah, tujuan, perancangan, dan implementasi berbicara pada level platform. Rantai berikut harus tetap sinkron pada setiap revisi.

| No | Rumusan Masalah (RM) | Tujuan (T) | Subbab Bab IV | Subbab Bab V | Poin Kesimpulan |
|----|----------------------|------------|---------------|--------------|------------------|
| 1  | Fragmentasi *tool* MLOps/DataOps menimbulkan biaya integrasi, duplikasi *pipeline*, dan ketidakkonsistenan antara fase data dan fase model. | Merancang arsitektur platform DataOps dan MLOps terintegrasi di atas Kubernetes yang menyatukan komponen data dan model pada satu bidang kendali. | IV.2 Perancangan Arsitektur Terintegrasi | V.2 Implementasi Arsitektur Terintegrasi | K1 |
| 2  | Tata kelola data sulit ditegakkan lintas siklus data–fitur–model sehingga *lineage*, kualitas, dan kepemilikan sulit ditelusuri. | Membangun *sub-sistem* tata kelola data (katalog, *lineage*, kualitas) yang berjalan otomatis di seluruh *pipeline*. | IV.3 *Sub-sistem* Tata Kelola Data | V.3 Implementasi *Sub-sistem* Tata Kelola | K2 |
| 3  | *Drift* data dan *concept drift* terjadi tanpa terdeteksi, sementara penyajian fitur lintas mode *batch* dan *streaming* rentan terhadap kebocoran temporal (*temporal leakage*). | Mengimplementasikan mekanisme deteksi *drift* terotomasi dengan pelatihan ulang berbasis kebijakan dan menjamin *point-in-time correctness* pada penyajian fitur. | IV.4 *Sub-sistem* Deteksi *Drift* dan *Continuous Training* | V.4 Implementasi Deteksi *Drift* dan *Continuous Training* | K3 |
| 4  | Fitur multimoda (vektor berdimensi tinggi, fitur agregat, fitur waktu nyata) sulit dilayani konsisten dengan SLA berbeda dari satu sumber kebenaran. | Mengembangkan layanan fitur *dual-store* (*offline* + *online*) yang melayani fitur tabular maupun vektor melalui satu kontrak API. | IV.5 *Sub-sistem* Layanan Fitur *Dual-Store* | V.5 Implementasi Layanan Fitur *Dual-Store* | K4 |

Subbab pengikat berada di kepala dan ekor tiap bab dan tidak masuk ke dalam rantai 1-1 di atas, tetapi wajib ada. Di kepala: IV.1 (Gambaran Umum Platform) dan V.1 (Lingkungan Implementasi) yang membuka konteks sebelum subbab rantai. Di ekor: IV.6 (Alur Kerja *End-to-End*) yang menyatukan keempat sub-sistem menjadi satu siklus *after* sebagai pasangan dari diagram *before* pada Bab III, dan V.6 (Verifikasi Implementasi) yang menjembatani ke evaluasi kuantitatif pada Bab VI. Panduan rinci pada `WRITING_GUIDE.md` §3.2.

Aturan turunan:
1. Jumlah RM = jumlah T = jumlah subbab rantai Bab IV (di luar pengikat IV.1 dan IV.6) = jumlah subbab rantai Bab V (di luar pengikat V.1 dan V.6) = jumlah poin Kesimpulan. Saat ini keempat angka tersebut bernilai 4.
2. Verba pada Tujuan tidak boleh berisi “mengevaluasi”, “menguji”, “mengukur”, atau “mendemonstrasikan”. Evaluasi adalah aktivitas metodologi, bukan tujuan.
3. Judul Bab IV menyebut nama artefak, bukan kata generik “Perancangan”. Judul yang digunakan: “Perancangan Arsitektur Platform DataOps dan MLOps”.
4. Setiap subbab Bab V membuka dengan referensi balik ke subbab Bab IV yang dipenuhi.
5. Setiap poin Kesimpulan menjawab tepat satu Tujuan.

## 2. Bab I Pendahuluan – Panduan Template Asli

(Disalin dari Bab_1.tex versi template.)

### 2.1 Latar Belakang

Subbab ini menjelaskan dasar pemikiran, motivasi, kebutuhan, alasan, atau urgensi pemilihan masalah Tugas Akhir. Subbab ini berisi penjelasan ringkas tentang kondisi atau situasi yang ada saat ini terkait dengan topik yang dibahas. Penulis perlu memuat:

1. Kondisi atau situasi topik yang dibahas beserta permasalahannya.
2. Urgensi atau pentingnya penyelesaian masalah tersebut.
3. Berbagai solusi yang telah diterapkan maupun yang memungkinkan untuk diterapkan.
4. Kelemahan atau kekurangan dari solusi yang telah/akan diterapkan sebagai dasar pemikiran rumusan masalah.

Panjang ideal 2–3 halaman. Hindari pernyataan yang terlalu umum atau terlalu luas. Sitasi mengikuti `biblatex` (`\textcite` naratif atau `\autocite` parentetik).

### 2.2 Rumusan Masalah

Berisi masalah utama yang dibahas. Struktur ideal:

1. Pokok persoalan dari kondisi atau situasi yang ada saat ini.
2. Elaborasi urgensi penyelesaian masalah (akibat jika tidak diselesaikan).
3. Usulan singkat solusi yang ditawarkan.

Hindari rumusan masalah yang terlalu umum (mis. “Bagaimana meningkatkan kualitas layanan kesehatan di Indonesia?”) dan yang merupakan keniscayaan TA (mis. “Bagaimana cara menguji sistem yang akan dibuat?”).

### 2.3 Tujuan

Tuliskan tujuan utama yang akan dicapai setelah Tugas Akhir selesai. Fokus pada hasil akhir, bukan kegiatan teknis. Sertakan kriteria keberhasilan.

### 2.4 Batasan Masalah

Batasan-batasan yang diambil. Opsional jika judul sudah cukup spesifik.

### 2.5 Metodologi

Tahapan pelaksanaan TA. Contoh tahapan dari template:

1. Investigasi pengumpulan fakta.
2. Studi literatur sistematis.
3. Analisis kebutuhan pengguna dan sistem.
4. Perancangan solusi.
5. Implementasi solusi.
6. Evaluasi solusi.
7. Penarikan kesimpulan dan saran.

### 2.6 Sistematika Penulisan

Gambaran umum isi setiap bab. Template menyebut Bab I s.d. Bab VII ditambah Daftar Pustaka dan Lampiran.

## 3. Bab II Studi Literatur – Panduan Template Asli

(Disalin dari Bab_2.tex versi template.)

Studi literatur berisi tinjauan pustaka, landasan teori, dan penelitian terdahulu yang relevan. Penulis menjelaskan:

1. Landasan teori dari literatur yang akan dipakai untuk menyelesaikan persoalan.
2. Pengetahuan tentang kasus yang dikaji.
3. Penelitian atau solusi terkait, untuk menentukan posisi persoalan dan ruang solusi.

Studi literatur bukan rangkuman; isi harus diolah secara sistematis. Alur penulisan yang dianjurkan: kasus → teori dasar → metode → penelitian terdahulu.

Catatan struktur (revisi 2026-06): Bab II tidak lagi memiliki subbab "Cakupan Studi Literatur". Cakupan ditulis sebagai 1–2 paragraf pembuka tanpa nomor langsung setelah judul bab, mengikuti aturan paragraf pembuka bab pada `WRITING_GUIDE.md` §3.8. Subbab pertama langsung masuk materi (DataOps dan MLOps). Aturan kedalaman subbab mengikuti `WRITING_GUIDE.md` §3.9: subbab dengan empat paragraf atau lebih yang memuat lebih dari satu topik dipecah menjadi sub-subbab, sedangkan subbab pendek satu topik dibiarkan tanpa pemecahan. Setiap subbab yang memiliki sub-subbab dibuka dengan satu paragraf pengantar singkat sebelum sub-subbab pertama, meniru pola proposal dan paragraf pembuka bab; kedalaman berhenti pada sub-subbab (tidak ada `\subsubsection`). Judul subbab 2.3 adalah "Manajemen Data: Ingestasi, Pemrosesan, dan Penyimpanan" agar mencakup sub-subbab penyimpanan. Sejak revisi 2026-07, seluruh tabel perbandingan berskor dipindah ke Bab III §III.4 (Analisis Pemilihan Open Source Tools); Bab II hanya memperkenalkan konsep tiap lapis dan menyebut kandidat alat sebagai contoh, sedangkan perbandingan berskor dan keputusan pemilihan berada di Bab III.

Catatan tabel perbandingan (revisi 2026-06): seluruh tabel evaluasi alternatif pada Bab III §III.4 memakai skor 0–2 per kriteria (0 = tidak dipenuhi, 1 = parsial, 2 = penuh; Total maksimum 8) yang legendanya didefinisikan satu kali di awal §III.4 (Bab III) dan parameter penilaian per kriteria dirinci pada Lampiran B (`appx:rubrik`) yang dirujuk makro `\skorlegendtools` di bawah tiap tabel berskor, ditambah satu kolom tekstual **Lisensi (Yayasan)** di antara kriteria terakhir dan kolom Total, misalnya `Apache 2.0 (CNCF)`, `MPL 2.0 (LF)`, `BUSL 1.1 (mandiri)`. Kolom ini bersifat informasional sebagai bukti tata kelola *open source* (OSI + yayasan netral seperti ASF/CNCF/LF) dan tidak mengubah Total; `mandiri` berarti tanpa yayasan netral, `komunitas` khusus pgvector/PostgreSQL. Tata letak baku tujuh kolom (lebar, `\footnotesize`, `\tabcolsep`) didefinisikan pada `WRITING_GUIDE.md` §2.1 dan wajib identik di seluruh 24 tabel berskor (termasuk perbandingan distribusi Kubernetes, tabel berskor pertama pada §III.4 yang didahului legenda rubrik).

### 3.1 Format Gambar, Tabel, Rumus, dan Kode Program

Gambar:
- Diletakkan di posisi `[t]` (top) atau `[b]` (bottom).
- Judul (caption) berada di bawah gambar, ditengahkan secara horizontal, huruf kecil kecuali huruf pertama.
- Nomor gambar tidak diakhiri tanda baca.
- Resolusi cukup tinggi; hindari *screenshot*; gunakan re-draw (draw.io, PowerPoint, Figma, Canva) dengan zoom ekspor ≥ 300%.
- Diagram arsitektur dikelola sebagai *diagram-as-code* di folder `diagrams/` (satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di `figures/`; lihat `diagrams/README.md` dan `WRITING_GUIDE.md` §1.7). Sumber kebenaran Gambar III.1 dan IV.1: `diagrams/Fragment_General_Arch.eraser` dan `diagrams/Integrate_General_Arch.eraser`. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu; render ulang manual di https://app.eraser.io lalu ekspor PNG menimpa berkas lama.
- Landasan kematangan diagram (revisi 2026-07): pasangan *before/after* diikat ke kerangka terbit yang sama dengan Subbab II.1.3 (`subsec:maturity`, berjudul "Tingkat Kematangan MLOps dan DataOps"). `Fragment_General_Arch` memuat grup penanda MLOps level 0 dari googlecloud2024mlops (proses manual berbasis skrip, model diserahkan satu arah, tanpa CI/CD, tanpa pemantauan kinerja aktif) ditambah tahap awal model evolusi DataOps dari munappy2020adhoc (silo data, pemantauan *pipeline* manual). `Integrate_General_Arch` memuat grup pemetaan MLOps level 2 (tujuh komponen wajib: *source control* Gitea, *test/build* Tekton, *deployment* Argo CD, *model registry* MLflow, *feature store* Feast, metadata ML MLflow+MLMD, orkestrator *pipeline* Kubeflow Pipelines) ditambah tahap DataOps (CI/CD data, orkestrasi, pengujian dan pemantauan berkelanjutan). Model evolusi DataOps lima tahap (ad hoc, semi-otomatis, *agile data science*, pengujian dan pemantauan berkelanjutan, DataOps) diperkenalkan pada paragraf penutup Subbab II.1.3. Caption Gambar III.1/IV.1 mengutip kedua sumber; perubahan pada salah satu dari tiga tampilan (berkas `.eraser`, caption, prosa Subbab II.1.3/III.1.3/IV.1) wajib disinkronkan ke dua lainnya.

Tabel:
- Judul (caption) berada di atas tabel.
- Tabel pendek: lingkungan `table` biasa, gunakan `tabularx`/`threeparttable` ketika butuh kolom fleksibel dan catatan kaki.
- Tabel panjang: paket `longtable` agar dapat terpenggal antar-halaman.
- Penyebutan di teks dengan `\ref` dan huruf kapital pada kata “Tabel”.

Rumus matematika:
- Persamaan tunggal: lingkungan `equation` dengan `\label{eq:...}`.
- Persamaan multi-baris bernomor: `align` (nomor hanya di baris terakhir) atau `multline` (rumus melebar).
- Persamaan multi-baris tanpa nomor: `align*`.

Kode program / *script*:
- Gunakan paket `listings`. Kode pendek inline; kode panjang dipindah ke lampiran.

Algoritma:
- Gunakan paket `algorithmic` (atau `algorithm2e`/`algpseudocode` jika lebih cocok).

## 4. Bab III Analisis Masalah – Panduan Template Asli

(Disalin dari Bab_3.tex versi template + revisi 2026-05.)

Pembagian subbab tidak rigid. Bab III minimal berisi:

1. Analisis kebutuhan fungsional dan nonfungsional.
2. Analisis berbagai alternatif solusi yang dapat ditawarkan.
3. Metode pemilihan solusi yang diusulkan.

Struktur yang dipakai pada laporan ini (revisi 2026-05; subbab Beban Operasional sebelumnya dilebur menjadi sub-sub-subbab di dalam III.1 agar Analisis Masalah berfokus pada satu rantai tekanan yang sejalan dengan urutan pemicu pada Bab I Latar Belakang):

- III.1 Analisis Kondisi Saat Ini (tiga sumber tekanan yang diurutkan sesuai pemicu pada Bab I Latar Belakang).
  - III.1.1 Beban Konfigurasi Platform dari Nol (configure-from-0).
  - III.1.2 Biaya Berlangganan Layanan Terkelola (cloud subscription + trade-off waktu lawan anggaran).
  - III.1.3 Efek Domino Fragmentasi Lintas Peran (pandangan umum fragmentasi DataOps + MLOps; cukup pandangan umum pada Gambar III.1, tanpa rincian per peran, agar bab tetap ramping dan fragmentasi tetap menjadi tekanan ketiga yang lebih ringan).
- III.2 Analisis Kebutuhan (identifikasi masalah pengguna, kebutuhan fungsional KF-1..KF-n, kebutuhan nonfungsional KNF-1..KNF-n).
- III.3 Analisis Pemilihan Solusi (alternatif solusi, analisis penentuan solusi).
- III.4 Analisis Pemilihan Open Source Tools (pemilihan komponen per lapis arsitektur, merujuk konsep Bab II).

## 5. Bab IV Perancangan – Panduan Template Asli

(Disalin dari Bab_4.tex versi template + `WRITING_GUIDE.md` §3.2.)

Ilustrasikan desain konsep solusi dalam bentuk model konseptual beserta penjelasan ringkas. Ilustrasi harus dapat dibandingkan (*before* dan *after*) terhadap kondisi sistem saat ini yang digambar di awal Bab III.

Aturan WRITING_GUIDE.md §3.2 yang berlaku:
- Judul bab tidak boleh “Perancangan” saja; sebut nama artefak.
- IV.1 selalu “Gambaran Umum” dengan diagram sistem secara keseluruhan.
- IV.2..N memetakan satu lawan satu dengan Tujuan 1..N.
- Pemetaan peran pengguna ke antarmuka (tabel `peran_akses`) ditempatkan di IV.1 Gambaran Umum sebagai orientasi “siapa yang memakai platform”, bukan sebagai subbab tersendiri di bawah IV.2. Keputusan ini menurunkan bingkai per-peran dari rancangan ke orientasi: IV.2 berisi murni rancangan tujuh lapis (T-1), tanpa subbab “Pandangan per Peran”. Identitas/SSO bersama dijelaskan sekali di IV.3.3 (identitas-akses), tidak diulang di IV.1. Tidak ada gambar penuh-halaman per peran di Bab IV. Lampiran fragmentasi per peran (dahulu Lampiran C) telah dihapus karena tesis konsisten bersifat *layer-centric*: masalah dirumuskan sebagai kontrak antar lapis, KF/KNF dipetakan ke lapis, rancangan Bab IV memuat tujuh lapis, dan diagram *after* terorganisasi per lapis, sehingga diagram *before* per peran menjadi satu-satunya artefak yang terorganisasi per peran dan menimbulkan ketaksesuaian taksonomi *before*/*after* yang rawan dipersoalkan penguji. Pandangan umum fragmentasi (Gambar III.1) sudah memuat keempat peran dalam satu tampilan sehingga rincian per peran tidak diperlukan. Bingkai per-peran pada Bab III ditulis kebutuhan-dahulu (peran sebagai tempat kebutuhan paling terasa), bukan peran-dahulu.

Landasan tujuh lapis (revisi 2026-07): pengelompokan tujuh lapis pada IV.2 bukan taksonomi baru, melainkan penataan ulang dua rujukan terbit, yaitu enam kategori komponen arsitektur MLOps hasil pemetaan sistematis najafabadi2024analysis (*data curation*, *storage and versioning*, *ML training*, CI/CD, *inference*, *infrastructure and supporting services*, disintesis dari 35 komponen pada 43 studi primer) dan sembilan komponen teknis kreuzberger2023mlops. Dua penataan ulang dinyatakan eksplisit pada prosa IV.2: kategori *data curation* dipecah menjadi lapisan ingestasi dan lapisan pemrosesan (jalur *batch*/*stream*), dan komponen pemantauan dipindah dari kategori *inference* menjadi lapisan tata kelola dan observabilitas yang ditambah katalog, *lineage*, serta kualitas data (tuntutan integrasi DataOps, munappy2020adhoc). Jangan pernah menyebut tujuh lapis sebagai standar industri; selalu sebagai penataan komponen bersumber yang dapat dirunut. Lead-in §III.4 memakai jangkar yang sama (komponen teknis kreuzberger2023mlops + lapis manajemen data jain2025integrating/rella2022mlops) dan menyatakan eksplisit bahwa sembilan kelompok penilaian alat pada §III.4 dikonsolidasikan menjadi tujuh lapis IV.2. Abstrak menyebut ketujuh lapis dengan nama yang sama persis dengan IV.2, dan judul Subbab IV.2.2 adalah "Lapisan Ingestasi, Pemrosesan, dan Penyimpanan Fitur" (tiga lapis yang dicakupnya, sama dengan caption Gambar fig:layer-data).

## 6. Bab V Implementasi – Panduan Template Asli

Template tidak menyertakan instruksi rinci untuk Bab V; gunakan aturan dari `WRITING_GUIDE.md` §3.3:

- Setiap subbab Bab V berpasangan satu lawan satu dengan subbab Bab IV.
- Setiap subbab merujuk balik pada subbab Bab IV yang dipenuhi.
- Implementasi dijelaskan apa adanya berdasarkan kondisi sistem yang sudah berjalan.

## 7. Bab VI Evaluasi – Panduan Template Asli

(Disalin dari Bab_6.tex versi template.)

Bab Evaluasi berisi metode evaluasi, hasil evaluasi, dan pembahasan hasil. Catatan gaya bahasa Indonesia ilmiah yang harus dijaga di seluruh laporan:

1. *“di mana”* / *“dimana”* tidak digunakan sebagai pengganti *which* dalam bahasa Inggris; ganti dengan “dengan”, “tempat”, atau “yang” sesuai konteks (referensi: Buku Praktis Bahasa Indonesia / BPBI).
2. Konjungsi *sedangkan* dan *sehingga* hanya boleh sebagai konjungsi intrakalimat, tidak diletakkan di awal kalimat. *sedangkan* didahului koma; *sehingga* tidak.
3. Istilah baku: analisa → analisis, eksisting → yang ada, bisnis proses → proses bisnis, user → pengguna, system → sistem, database → basis data, aktifitas → aktivitas, efektifitas → efektivitas, sosial media → media sosial.
4. Pemisah desimal memakai koma (50,6%), bukan titik.
5. Daftar memakai angka (1, 2, 3) atau huruf (a, b, c); hindari *bullet points*. Jika hanya satu *item*, tidak perlu nomor. Judul item dan penjelasannya tetap pada halaman yang sama.
6. *masing-masing* diletakkan di belakang kata yang diterangkan; *setiap*/*tiap-tiap* diletakkan di depannya.

Catatan revisi 2026-07 (Bab VI): bab evaluasi diakhiri seksi Perbandingan
Biaya Infrastruktur dan Tenaga Kerja sebelum Pembahasan. Seksi ini memuat
tiga artefak berurutan: tabel biaya bulanan tiga skenario (VPS multi-penyedia,
GKE, layanan terkelola) dengan harga daftar per 16 Juni 2026 yang setiap
barisnya bercatatan sumber, tabel ilustrasi biaya tiga tahun yang
menggabungkan infrastruktur dan tenaga kerja (gaji acuan bersumber panduan
gaji terbit, kurs JISDOR, alokasi FTE dinyatakan sebagai asumsi), dan gambar
proyeksi biaya kumulatif tiga puluh enam bulan. Seluruh angka harus punya sumber
atau dinyatakan eksplisit sebagai asumsi; tidak ada angka tanpa baseline.

## 8. Bab VII Kesimpulan dan Saran – Panduan Template Asli

Template tidak menyertakan rincian; gunakan aturan `WRITING_GUIDE.md` §3.4:

- Kesimpulan menjawab Tujuan satu per satu, dengan urutan yang sama.
- Tidak menambahkan klaim baru yang belum muncul di bab sebelumnya.
- Saran berisi arah pengembangan lanjutan, terutama untuk tujuan-tujuan yang belum tertutup penuh oleh evaluasi awal.

## 9. Daftar Berkas Pendukung

- `WRITING_GUIDE.md` – pedoman gambar/tabel/struktur bab.
- `README.md` – konvensi struktur direktori dan penamaan berkas.
- `daftar-pustaka.bib` – daftar pustaka BibLaTeX.
- `figures/` – semua *figure* berformat PNG/JPG (hasil render saja).
- `diagrams/` – sumber *diagram-as-code* (`.eraser`) untuk semua bab; dirender manual ke PNG di `figures/`.
- `tables/` – tabel yang di-`\input` dari berkas utama.
- `listings/` – kode program panjang.
- `algorithms/` – pseudocode algoritma.

## 10. Catatan Pemeliharaan

Apabila rantai pada §1 berubah (mis. tujuan diperluas atau dipersempit), perbarui:

1. Tabel rantai di §1 dokumen ini.
2. Daftar subbab pada Bab I (Rumusan Masalah, Tujuan, Sistematika).
3. Daftar subbab pada Bab IV dan Bab V.
4. Poin Kesimpulan pada Bab VII.

Sinkronisasi rantai diperiksa setiap kali revisi besar selesai. Setelah revisi yang memindahkan atau menambah istilah, audit ulang Daftar Singkatan (`frontmatter/14_Daftar_Singkatan.tex`): hanya akronim yang benar-benar muncul pada Bab 1–5, urut alfabetis, kolom pemakaian pertama mengikuti bab kemunculan pertama (periksa dengan `grep` per akronim berurutan Bab 1 → 2 → 3 → 4 → 5; seluruh tabel perbandingan berskor di-`\input` di Bab III §III.4).
