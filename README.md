# 🌌 Ocrato - Anti-Gravity OCR & Translate

**Ocrato** adalah aplikasi pemindai teks (OCR) dan penerjemah instan yang bekerja **100% Offline**. Dibangun dengan filosofi **Anti-Gravity Architecture**, aplikasi ini mengutamakan performa yang sangat ringan, UI yang sangat mulus (zero-lag), dan presisi tinggi.

---

## 🚀 Fitur Utama

- **Precision Scanning**: Hanya memindai teks yang berada di dalam kotak indikator (persegi presisi), bukan seluruh layar kamera.
- **100% Offline Core**: Semua proses pengenalan teks dan terjemahan dilakukan di perangkat tanpa API eksternal. Privasi terjaga dan hemat data.
- **Zero-Lag Interface**: Menggunakan pipeline asinkron untuk memastikan pratinjau kamera tetap berjalan pada 60+ FPS meskipun sedang melakukan pemrosesan berat.
- **Premium Aesthetics**: UI modern dengan animasi halus, haptic feedback, dan desain kartu mengambang yang elegan.
- **Copy-to-Clipboard**: Salin hasil terjemahan secara instan dengan satu ketukan.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev)
- **OCR Engine**: [Google ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition)
- **Translation Engine**: [Google ML Kit On-Device Translation](https://developers.google.com/ml-kit/language/translation)
- **Camera Handling**: [Camera Plugin](https://pub.dev/packages/camera)
- **Animations**: [Flutter Animate](https://pub.dev/packages/flutter_animate)
- **Typography**: [Google Fonts (Outfit)](https://pub.dev/packages/google_fonts)

---

## 🏗️ Anti-Gravity Architecture

Aplikasi ini menggunakan pendekatan arsitektur minimalis namun bertenaga:
1. **Service-Based Logic**: Pemisahan tegas antara logika OCR, Translasi, dan UI.
2. **Throttled Processing**: Mengatur frekuensi pemindaian (1 scan/detik) untuk efisiensi baterai dan CPU.
3. **Coordinate Mapping**: Menggunakan algoritma pemetaan koordinat untuk memfilter teks berdasarkan area spesifik di layar (Scanner Box).

---

## 📦 Instalasi

### Prasyarat
- Flutter SDK terbaru.
- **JDK 17** (Sangat direkomendasikan untuk menghindari error kompilasi pada Windows/Java 23).
- Perangkat fisik Android (API 21+) atau iOS.

### Langkah-langkah
1. Clone repositori ini.
2. Jalankan perintah untuk mengambil dependensi:
   ```bash
   flutter pub get
   ```
3. Hubungkan perangkat Anda.
4. Jalankan aplikasi:
   ```bash
   flutter run
   ```

> **Catatan**: Saat pertama kali dijalankan, aplikasi akan mengunduh paket bahasa (Inggris & Indonesia) secara otomatis untuk mendukung mode offline. Pastikan ada koneksi internet hanya untuk proses unduhan awal ini.

---

## 📝 Konfigurasi Platform

### Android
Pastikan `minSdkVersion` diatur ke **21** di file `android/app/build.gradle.kts`.

### iOS
Pastikan `NSCameraUsageDescription` sudah ditambahkan di `Info.plist` untuk izin akses kamera.

---

## 📄 Lisensi
Proyek ini dikembangkan sebagai bagian dari tugas Pengembangan Aplikasi Bergerak (PPB).
