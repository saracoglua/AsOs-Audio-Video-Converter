# =========================================================================================
# ASOS AUDİO & VİDEO CONVERTER
# =========================================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# =========================================================================================
# FFMPEG DİNAMİK UZANTI MOTORU
# =========================================================================================
function Get-FFmpegExtensions {
    $VarsayilanUzantilar = @(
        "mp4","mkv","avi","mov","wmv","ts","flv","webm","mpeg","mpg","m4v","3gp","vob",
        "mp3","m4a","wav","flac","ogg","aac","wma","m4b","mka","opus","amr"
    )
    $ffCheck = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffCheck) { return $VarsayilanUzantilar | Sort-Object }
    try {
        $rawOutput = & ffmpeg -demuxers -loglevel quiet
        $parsedExtensions = New-Object System.Collections.Generic.HashSet[string]
        foreach ($line in $rawOutput) {
            if ($line -match "^\s\s[D\s][E\s]\s([a-zA-Z0-9_,]+)\s") {
                foreach ($name in $Matches[1].Split(',')) {
                    $clean = $name.Trim().ToLower()
                    if ($clean -match "^[a-z0-9]+$" -and $clean.Length -le 5) { [void]$parsedExtensions.Add($clean) }
                }
            }
        }
        if ($parsedExtensions.Count -gt 0) { return $parsedExtensions | Sort-Object }
    } catch {}
    return $VarsayilanUzantilar | Sort-Object
}

$TumUzantilarListesi = Get-FFmpegExtensions
$PopulerVideolar = @("mp4","mkv","avi","mov","wmv","ts","flv","webm","mpeg","mpg","m4v","3gp")
$PopulerSesler   = @("mp3","m4a","wav","flac","ogg","aac","wma","m4b","mka","opus","amr")
$GorselUzantilari = @("jpg","jpeg","png","bmp","gif","tiff","tif","ico","icon","emf","wmf")

# =========================================================================================
# 1. MOTOR: ARKA PLAN MEDYA (FFMPEG) BORU HATTI
# =========================================================================================
function Start-MediaPipeline {
    param(
        $Islem, $KaynakKlasor, $HedefKlasor, $AyniDosyayaYaz, $KaynakSil,
        $AyniUzantiAtla, $HedefFormat, $VideoCodec, $HedefCozunurluk, 
        $SesFormat, $SesBitrate, $LogBox, $SecilenFiltreUzantilar
    )

    $LogBox.AppendText("`r`n[BAŞLADI] Medya taraması başlatılıyor...`r`n")
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        $LogBox.AppendText("[HATA] FFmpeg motoru sistemde bulunamadı! Lütfen önce kurulumu tamamlayın.`r`n")
        return
    }
    if ($SecilenFiltreUzantilar.Count -eq 0) {
        $LogBox.AppendText("[!] Sol listeden taranacak en az bir uzantı seçmelisiniz!`r`n")
        return
    }
    if (-not $AyniDosyayaYaz -and -not (Test-Path $HedefKlasor)) {
        try { New-Item -ItemType Directory -Path $HedefKlasor -Force | Out-Null } catch { return }
    }

    $UzantFilter = $SecilenFiltreUzantilar | ForEach-Object { "*.$_" }
    $Dosyalar = Get-ChildItem -Path $KaynakKlasor -Include $UzantFilter -Recurse -ErrorAction SilentlyContinue
    if ($null -eq $Dosyalar) { $LogBox.AppendText("[!] Uygun medya dosyası bulunamadı.`r`n"); return }

    $EskiTempler = Get-ChildItem -Path $KaynakKlasor -Filter "*_temp.*" -Recurse -ErrorAction SilentlyContinue
    foreach ($oldTemp in $EskiTempler) {
        if (Test-Path $oldTemp.FullName) { Remove-Item $oldTemp.FullName -Force -ErrorAction SilentlyContinue }
    }

    $LogBox.AppendText("[OK] Toplam $($Dosyalar.Count) adet uygun dosya keşfedildi.`r`n")
    [System.Windows.Forms.Application]::DoEvents()

    foreach ($dosya in $Dosyalar) {
        if ($dosya.Name -like "*_temp.*") { continue }

        $giris = $dosya.FullName
        $eskiUzanti = $dosya.Extension.TrimStart('.').Trim().ToLower()
        $dosyaAdi = [System.IO.Path]::GetFileNameWithoutExtension($dosya.Name)

        $suAnkiHedefUzanti = switch ($Islem) {
            { $_ -in "donustur", "cozunurluk" } { $HedefFormat }
            { $_ -in "sesayir", "sesdonustur" } { $SesFormat }
        }
        $suAnkiHedefUzanti = $suAnkiHedefUzanti.Trim().ToLower()

        $tempCikis = if ($AyniDosyayaYaz) {
            if ($Islem -eq "sesayir") { Join-Path $dosya.DirectoryName "${dosyaAdi}.${suAnkiHedefUzanti}" }
            else { Join-Path $dosya.DirectoryName "${dosyaAdi}_temp.${suAnkiHedefUzanti}" }
        } else {
            Join-Path $HedefKlasor "${dosyaAdi}.${suAnkiHedefUzanti}"
        }

        if ($AyniUzantiAtla -and ($eskiUzanti -eq $suAnkiHedefUzanti) -and ($Islem -in "donustur", "sesdonustur")) {
            $LogBox.AppendText("[-] [ATLANDI] Zaten ${suAnkiHedefUzanti}: ${giris}`r`n")
            if ($AyniDosyayaYaz -and (Test-Path $tempCikis)) { Remove-Item $tempCikis -Force -ErrorAction SilentlyContinue }
            [System.Windows.Forms.Application]::DoEvents()
            continue
        }

        $audioParams = if ($SesBitrate -eq "copy") { @("-c:a", "copy") } else { 
            $secilenKodek = switch ($suAnkiHedefUzanti) { "mp3" { "libmp3lame" } "m4a" { "aac" } "aac" { "aac" } "wav" { "pcm_s16le" } "flac" { "flac" } default { "aac" } }
            @("-c:a", $secilenKodek, "-b:a", $SesBitrate, "-strict", "experimental") 
        }

        $commonParams = switch ($VideoCodec) {
            "h264_nvenc" { @("-c:v", "h264_nvenc", "-pixel_format", "yuv420p", "-cq", "23", "-rc", "constqp") }
            "h264_qsv"   { @("-c:v", "h264_qsv", "-global_quality", "23", "-look_ahead", "1") }
            "h264_amf"   { @("-c:v", "h264_amf", "-quality", "balanced") }
            default      { @("-c:v", "libx264", "-crf", "22", "-preset", "fast", "-pix_fmt", "yuv420p") }
        }

        $LogBox.AppendText("[İŞLENİYOR] -> ${giris}`r`n")
        [System.Windows.Forms.Application]::DoEvents()

        if (Test-Path $tempCikis) { Remove-Item $tempCikis -Force -ErrorAction SilentlyContinue }

        $params = switch ($Islem) {
            "donustur"    { @("-i", $giris) + $commonParams + $audioParams + @("-y", $tempCikis) }
            "cozunurluk"  { @("-i", $giris, "-vf", "scale=-2:$HedefCozunurluk") + $commonParams + $audioParams + @("-y", $tempCikis) }
            "sesayir"     { @("-i", $giris, "-vn") + $audioParams + @("-y", $tempCikis) }
            "sesdonustur" { @("-i", $giris) + $audioParams + @("-y", $tempCikis) }
        }

        & ffmpeg -loglevel error $params

        if ($LASTEXITCODE -eq 0) {
            if ($AyniDosyayaYaz -and ($Islem -ne "sesayir")) {
                $NihaiAd = "${dosyaAdi}.${suAnkiHedefUzanti}"
                Rename-Item -Path $tempCikis -NewName $NihaiAd -Force
                $nihaiYol = Join-Path $dosya.DirectoryName $NihaiAd
                if ($eskiUzanti -ne $suAnkiHedefUzanti) {
                    if (Test-Path $giris) { Remove-Item $giris -Force -ErrorAction SilentlyContinue }
                }
            } else {
                if ($KaynakSil) { if (Test-Path $giris) { Remove-Item $giris -Force -ErrorAction SilentlyContinue } }
                $nihaiYol = $tempCikis
            }
            $LogBox.AppendText("[BAŞARILI]  -> ${nihaiYol}`r`n")
        } else {
            $LogBox.AppendText("[HATA] Başarısız: ${giris}`r`n")
            if (Test-Path $tempCikis) { Remove-Item $tempCikis -Force -ErrorAction SilentlyContinue }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    $LogBox.AppendText("`r`n[BİTTİ] Tüm medya işlemleri tamamlandı!`r`n")
}

# =========================================================================================
# 2. MOTOR: ARKA PLAN GÖRSEL (IMAGE.DRAWING) BORU HATTI
# =========================================================================================
function Start-ImagePipeline {
    param(
        $KaynakKlasor, $HedefKlasor, $AyniDosyayaYaz, $JpegYap, $HedefFotoFormat,
        $DpiDegistir, $ManuelDPI, $YatayYukseklik, $DikeyYukseklik, $JpegKalite, $LogBox, $SecilenFiltreUzantilar
    )

    $LogBox.AppendText("`r`n[BAŞLADI] Görsel işleme algoritması devreye girdi...`r`n")
    if ($SecilenFiltreUzantilar.Count -eq 0) {
        $LogBox.AppendText("[!] Sol listeden işlenecek en az bir fotoğraf formatı seçmelisiniz!`r`n")
        return
    }
    
    $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegKalite)

    if (-not $AyniDosyayaYaz -and -not (Test-Path $HedefKlasor)) {
        New-Item -ItemType Directory -Path $HedefKlasor | Out-Null
    }

    $UzantFilter = $SecilenFiltreUzantilar | ForEach-Object { "*.$_" }
    $Dosyalar = Get-ChildItem -Path $KaynakKlasor -Include $UzantFilter -Recurse -ErrorAction SilentlyContinue
    if ($null -eq $Dosyalar) { $LogBox.AppendText("[!] Klasörde seçilen formatlara uygun fotoğraf bulunamadı.`r`n"); return }

    $LogBox.AppendText("[OK] Toplam $($Dosyalar.Count) adet fotoğraf işleme sırasına alındı.`r`n")
    [System.Windows.Forms.Application]::DoEvents()

    foreach ($dosya in $Dosyalar) {
        $gorselYolu = $dosya.FullName
        $eskiUzanti = $dosya.Extension.ToLower()
        
        if ($AyniDosyayaYaz) {
            $hedefDosyaYolu = $gorselYolu
        } else {
            $goreliYol = $gorselYolu.Substring($KaynakKlasor.Length).TrimStart('\')
            $hedefDosyaYolu = Join-Path $HedefKlasor $goreliYol
            $hedefAltKlasor = Split-Path $hedefDosyaYolu
            if (!(Test-Path $hedefAltKlasor)) { New-Item -ItemType Directory -Path $hedefAltKlasor -Force | Out-Null }
        }

        $belirlenmisUzanti = if ($JpegYap) { "jpg" } else { $HedefFotoFormat.Trim().ToLower() }
        $hedefDosyaYolu = [System.IO.Path]::ChangeExtension($hedefDosyaYolu, ".$belirlenmisUzanti")

        try {
            $tempGorsel = [System.Drawing.Image]::FromFile($gorselYolu)
            $orijinalDpiX = $tempGorsel.HorizontalResolution
            $orijinalDpiY = $tempGorsel.VerticalResolution
            $orijinal = New-Object System.Drawing.Bitmap $tempGorsel
            $tempGorsel.Dispose()

            if ($orijinal.Width -gt $orijinal.Height) {
                $hedefYukseklik = $YatayYukseklik
            } else {
                $hedefYukseklik = $DikeyYukseklik
            }

            $oran = $hedefYukseklik / $orijinal.Height
            if ($oran -ge 1) {
                $genislik = $orijinal.Width; $yukseklik = $orijinal.Height
            } else {
                $genislik = [int]($orijinal.Width * $oran); $yukseklik = [int]($orijinal.Height * $oran)
            }

            $yeniGorsel = New-Object System.Drawing.Bitmap $genislik, $yukseklik
            
            if ($DpiDegistir) {
                $yeniGorsel.SetResolution($ManuelDPI, $ManuelDPI)
                $suAnkiDpi = $ManuelDPI
            } else {
                $yeniGorsel.SetResolution($orijinalDpiX, $orijinalDpiY)
                $suAnkiDpi = $orijinalDpiX
            }
            
            $grafik = [System.Drawing.Graphics]::FromImage($yeniGorsel)
            $grafik.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $grafik.DrawImage($orijinal, 0, 0, $genislik, $yukseklik)

            if ($belirlenmisUzanti -eq "jpg" -or $belirlenmisUzanti -eq "jpeg") {
                $yeniGorsel.Save($hedefDosyaYolu, $jpegEncoder, $encoderParams)
            } else {
                $imgFormat = switch ($belirlenmisUzanti) {
                    "png"   { [System.Drawing.Imaging.ImageFormat]::Png }
                    "jpg"   { [System.Drawing.Imaging.ImageFormat]::Jpeg }
                    "bmp"   { [System.Drawing.Imaging.ImageFormat]::Bmp }
                    "gif"   { [System.Drawing.Imaging.ImageFormat]::Gif }
                    "tiff"  { [System.Drawing.Imaging.ImageFormat]::Tiff }
                    "tif"   { [System.Drawing.Imaging.ImageFormat]::Tiff }
                    "ico"   { [System.Drawing.Imaging.ImageFormat]::Icon }
                    "icon"  { [System.Drawing.Imaging.ImageFormat]::Icon }
                    default { [System.Drawing.Imaging.ImageFormat]::Png }
                }
                $yeniGorsel.Save($hedefDosyaYolu, $imgFormat)
            }

            if ($AyniDosyayaYaz -and ($eskiUzanti.TrimStart('.') -ne $belirlenmisUzanti)) { 
                if (Test-Path $gorselYolu) { Remove-Item $gorselYolu -Force } 
            }

            $grafik.Dispose(); $orijinal.Dispose(); $yeniGorsel.Dispose()
            $LogBox.AppendText("[GÖRSEL] -> $hedefDosyaYolu ($genislik x $yukseklik | DPI: $suAnkiDpi)`r`n")
        } catch {
            $LogBox.AppendText("[HATA] Fotoğraf hatası ($gorselYolu): $_`r`n")
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    $LogBox.AppendText("`r`n[BİTTİ] Tüm fotoğraf boyutlandırma işlemleri tamamlandı!`r`n")
}

# =========================================================================================
# GLOBAL SİSTEM DONANIM KONTROL MOTORU VE ANALİZİ
# =========================================================================================
$GpuListesi = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
$OneriIndex = 0
$OneriMetni = "Sisteminizde harici GPU algılanamadı. Standart CPU h264 modu kullanılacaktır."
$HasIntel = $false
foreach ($gpu in $GpuListesi) { if ($gpu -like "*Intel*") { $HasIntel = $true; break } }

foreach ($gpu in $GpuListesi) {
    if ($gpu -like "*NVIDIA*" -and $gpu -like "*MX*") {
        if ($HasIntel) {
            $OneriIndex = 2
            $OneriMetni = "NVIDIA MX serisi kartlarda NVENC çipi bulunmaz. İşlemci dahili Intel QuickSync birimi otomatik seçildi."
        }
        break
    }
    elseif ($gpu -like "*NVIDIA*") { 
        $OneriIndex = 1 
        $OneriMetni = "NVIDIA Ekran Kartı Algılandı! 'h264_nvenc' seçmeniz şiddetle önerilir."
        break 
    }
    elseif ($gpu -like "*Intel*") { 
        $OneriIndex = 2 
        $OneriMetni = "Intel QuickSync Birimi Algılandı! 'h264_qsv' seçmeniz önerilir."
        break 
    }
    elseif ($gpu -like "*AMD*") { 
        $OneriIndex = 3 
        $OneriMetni = "AMD Ekran Kartı Algılandı! 'h264_amf' seçmeniz önerilir."
        break 
    }
}

# =========================================================================================
# RESPONSIVE MASTER GUI FORM DESIGN
# =========================================================================================
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Asos Audio & Video Converter V2.0"
$Form.Size = New-Object System.Drawing.Size(1100, 950)
$Form.MinimumSize = New-Object System.Drawing.Size(1020, 880)

# CRITICAL FIX: EXE YAPILDIĞINDA PENCERELERİN ALTINDA KALMA ÖNLEYİCİ AYARLARI
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

$StandartFont = New-Object System.Drawing.Font("Segoe UI", 10)
$BoldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

# STÜDYO MASTER MOD SEÇİCİ
$pnlStudioMode = New-Object System.Windows.Forms.Panel
$pnlStudioMode.Location = New-Object System.Drawing.Point(20, 10)
$pnlStudioMode.Size = New-Object System.Drawing.Size(1040, 50)
$pnlStudioMode.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$Form.Controls.Add($pnlStudioMode)

$lblStudioMode = New-Object System.Windows.Forms.Label
$lblStudioMode.Text = "ÇALIŞMA MODU SEÇİNİZ:"
$lblStudioMode.Location = New-Object System.Drawing.Point(15, 15)
$lblStudioMode.Size = New-Object System.Drawing.Size(180, 20)
$lblStudioMode.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblStudioMode.ForeColor = [System.Drawing.Color]::Navy
$pnlStudioMode.Controls.Add($lblStudioMode)

$cmbStudioMode = New-Object System.Windows.Forms.ComboBox
$cmbStudioMode.Location = New-Object System.Drawing.Point(200, 11)
$cmbStudioMode.Size = New-Object System.Drawing.Size(320, 25)
$cmbStudioMode.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$cmbStudioMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$null = $cmbStudioMode.Items.Add("🎬 VİDEO & SES İŞLEME (FFmpeg Motoru)")
$null = $cmbStudioMode.Items.Add("🖼️ FOTOĞRAF BOYUTLANDIRMA & DPI (System.Drawing)")
$cmbStudioMode.SelectedIndex = 0
$pnlStudioMode.Controls.Add($cmbStudioMode)

$lblStatusText = New-Object System.Windows.Forms.Label
$lblStatusText.Location = New-Object System.Drawing.Point(540, 15)
$lblStatusText.Size = New-Object System.Drawing.Size(220, 20)
$lblStatusText.Font = $BoldFont
$pnlStudioMode.Controls.Add($lblStatusText)

$btnInstallFFmpeg = New-Object System.Windows.Forms.Button
$btnInstallFFmpeg.Text = "⚙️ FFmpeg Kur"
$btnInstallFFmpeg.Location = New-Object System.Drawing.Point(770, 10)
$btnInstallFFmpeg.Size = New-Object System.Drawing.Size(190, 30)
$btnInstallFFmpeg.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnInstallFFmpeg.BackColor = [System.Drawing.Color]::Goldenrod
$btnInstallFFmpeg.ForeColor = [System.Drawing.Color]::White
$btnInstallFFmpeg.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$pnlStudioMode.Controls.Add($btnInstallFFmpeg)

function Check-FFmpegStatus {
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
        $lblStatusText.Text = "🟢 FFmpeg: SİSTEMDE AKTİF"
        $lblStatusText.ForeColor = [System.Drawing.Color]::ForestGreen
        $btnInstallFFmpeg.Visible = $false
    } else {
        $lblStatusText.Text = "🔴 FFmpeg: BULUNAMADI!"
        $lblStatusText.ForeColor = [System.Drawing.Color]::DarkRed
        if ($cmbStudioMode.SelectedIndex -eq 0) { $btnInstallFFmpeg.Visible = $true } else { $btnInstallFFmpeg.Visible = $false }
    }
}

# SOL FİLTRE PANELİ
$grpFiltre = New-Object System.Windows.Forms.GroupBox
$grpFiltre.Text = " Taranacak Formatlar "
$grpFiltre.Location = New-Object System.Drawing.Point(20, 75)
$grpFiltre.Size = New-Object System.Drawing.Size(220, 700)
$grpFiltre.Font = $BoldFont
$Form.Controls.Add($grpFiltre)

$chkListUzantilar = New-Object System.Windows.Forms.CheckedListBox
$chkListUzantilar.Location = New-Object System.Drawing.Point(15, 60)
$chkListUzantilar.Size = New-Object System.Drawing.Size(190, 620)
$chkListUzantilar.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$chkListUzantilar.CheckOnClick = $true
$chkListUzantilar.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpFiltre.Controls.Add($chkListUzantilar)

$btnSecHepsi = New-Object System.Windows.Forms.Button
$btnSecHepsi.Text = "Tümünü Seç"
$btnSecHepsi.Location = New-Object System.Drawing.Point(15, 27)
$btnSecHepsi.Size = New-Object System.Drawing.Size(90, 25)
$btnSecHepsi.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSecHepsi.Add_Click({ for($i=0; $i -lt $chkListUzantilar.Items.Count; $i++) { $chkListUzantilar.SetItemChecked($i, $true) } })
$grpFiltre.Controls.Add($btnSecHepsi)

$btnSecBiraq = New-Object System.Windows.Forms.Button
$btnSecBiraq.Text = "Temizle"
$btnSecBiraq.Location = New-Object System.Drawing.Point(115, 27)
$btnSecBiraq.Size = New-Object System.Drawing.Size(90, 25)
$btnSecBiraq.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnSecBiraq.Add_Click({ for($i=0; $i -lt $chkListUzantilar.Items.Count; $i++) { $chkListUzantilar.SetItemChecked($i, $false) } })
$grpFiltre.Controls.Add($btnSecBiraq)

$SagLeft = 260

# DİZİN SEÇİMLERİ
$lblKaynak = New-Object System.Windows.Forms.Label ;
$lblKaynak.Text = "Kaynak Giriş Klasörü (X):" ; $lblKaynak.Font = $BoldFont ; $lblKaynak.Location = New-Object System.Drawing.Point($SagLeft, 75) ;
$lblKaynak.Size = New-Object System.Drawing.Size(200, 20) ; $Form.Controls.Add($lblKaynak)
$txtKaynak = New-Object System.Windows.Forms.TextBox ; $txtKaynak.Font = $StandartFont ; $txtKaynak.Text = "D:\Test" ;
$txtKaynak.Location = New-Object System.Drawing.Point($SagLeft, 98) ; $Form.Controls.Add($txtKaynak)
$btnKaynak = New-Object System.Windows.Forms.Button ; $btnKaynak.Text = "Gözat..." ; $btnKaynak.Font = $StandartFont ;
$btnKaynak.Location = New-Object System.Drawing.Point(950, 96) ; $btnKaynak.Size = New-Object System.Drawing.Size(95, 26)
$btnKaynak.Add_Click({ $f=New-Object System.Windows.Forms.FolderBrowserDialog; if($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$txtKaynak.Text=$f.SelectedPath} }) ;
$Form.Controls.Add($btnKaynak)

$lblHedef = New-Object System.Windows.Forms.Label ; $lblHedef.Text = "Hedef Çıktı Klasörü (Y):" ; $lblHedef.Font = $BoldFont ;
$lblHedef.Location = New-Object System.Drawing.Point($SagLeft, 133) ; $lblHedef.Size = New-Object System.Drawing.Size(200, 20) ; $Form.Controls.Add($lblHedef)
$txtHedef = New-Object System.Windows.Forms.TextBox ;
$txtHedef.Font = $StandartFont ; $txtHedef.Text = "D:\Test2" ; $txtHedef.Location = New-Object System.Drawing.Point($SagLeft, 156) ; $Form.Controls.Add($txtHedef)
$btnHedef = New-Object System.Windows.Forms.Button ;
$btnHedef.Text = "Gözat..." ; $btnHedef.Font = $StandartFont ; $btnHedef.Location = New-Object System.Drawing.Point(950, 154) ;
$btnHedef.Size = New-Object System.Drawing.Size(95, 26)
$btnHedef.Add_Click({ $f=New-Object System.Windows.Forms.FolderBrowserDialog; if($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$txtHedef.Text=$f.SelectedPath} }) ;
$Form.Controls.Add($btnHedef)

# =========================================================================================
# HEDEF KİLİTLEME FONKSİYONU (AYNI KLASÖRE KAYDET SEÇİLİNCE PASİFLEŞTİRME MOTORU)
# =========================================================================================
function Update-TargetDirectoryState {
    param($IsChecked)
    if ($IsChecked) {
        $txtHedef.Enabled = $false
        $btnHedef.Enabled = $false
        $txtHedef.BackColor = [System.Drawing.Color]::LightGray
    } else {
        $txtHedef.Enabled = $true
        $btnHedef.Enabled = $true
        $txtHedef.BackColor = [System.Drawing.Color]::White
    }
}

# =========================================================================================
# MEDYA PANELİ
# =========================================================================================
$pnlMediaControls = New-Object System.Windows.Forms.Panel
$pnlMediaControls.Location = New-Object System.Drawing.Point($SagLeft, 195)
$pnlMediaControls.Size = New-Object System.Drawing.Size(800, 310)
$Form.Controls.Add($pnlMediaControls)

$lblIslem = New-Object System.Windows.Forms.Label ;
$lblIslem.Text = "Yapılacak İşlem (Mod):" ; $lblIslem.Font = $BoldFont ; $lblIslem.Location = New-Object System.Drawing.Point(0, 0) ;
$lblIslem.Size = New-Object System.Drawing.Size(180, 20) ; $pnlMediaControls.Controls.Add($lblIslem)
$cmbIslem = New-Object System.Windows.Forms.ComboBox ; $cmbIslem.Font = $StandartFont ; $cmbIslem.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList ;
$cmbIslem.Location = New-Object System.Drawing.Point(0, 22) ; $cmbIslem.Size = New-Object System.Drawing.Size(270, 25)
@("donustur (Video Format Değiştir)","cozunurluk (Videoyu Yeniden Boyutlandır)","sesayir (Videodan Sesi Kopar)","sesdonustur (Ses Dosyası Dönüştür)") |
% { $null=$cmbIslem.Items.Add($_) } ; $cmbIslem.SelectedIndex = 0 ; $pnlMediaControls.Controls.Add($cmbIslem)

$lblDonanim = New-Object System.Windows.Forms.Label ; $lblDonanim.Text = "Donanım Motoru Seçimi:" ;
$lblDonanim.Font = $BoldFont ; $lblDonanim.Location = New-Object System.Drawing.Point(300, 0) ; $lblDonanim.Size = New-Object System.Drawing.Size(200, 20) ;
$pnlMediaControls.Controls.Add($lblDonanim)
$cmbDonanim = New-Object System.Windows.Forms.ComboBox ; $cmbDonanim.Font = $StandartFont ; $cmbDonanim.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList ; $cmbDonanim.Location = New-Object System.Drawing.Point(300, 22) ;
$cmbDonanim.Size = New-Object System.Drawing.Size(320, 25)
@("Standart CPU (libx264 - En Küçük Boyut)","NVIDIA NVENC (Donanım Hızlandırma)","INTEL QSV (Dahili Grafik Hızlandırma)","AMD AMF (Donanım Hızlandırma)") |
% { $null=$cmbDonanim.Items.Add($_) }
$cmbDonanim.SelectedIndex = $OneriIndex ; $pnlMediaControls.Controls.Add($cmbDonanim)

$grpFormat = New-Object System.Windows.Forms.GroupBox ;
$grpFormat.Text = " Hedef Kalite & Dosya Yönetim Stratejileri " ; $grpFormat.Font = $BoldFont ;
$grpFormat.Location = New-Object System.Drawing.Point(0, 60) ; $grpFormat.Size = New-Object System.Drawing.Size(800, 245) ;
$pnlMediaControls.Controls.Add($grpFormat)

$tblMediaGrid = New-Object System.Windows.Forms.TableLayoutPanel
$tblMediaGrid.Location = New-Object System.Drawing.Point(10, 25)
$tblMediaGrid.Size = New-Object System.Drawing.Size(780, 210)
$tblMediaGrid.ColumnCount = 2
$tblMediaGrid.RowCount = 1
[void]$tblMediaGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 390)))
[void]$tblMediaGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tblMediaGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpFormat.Controls.Add($tblMediaGrid)

$pnlMediaLeftConfig = New-Object System.Windows.Forms.Panel
$pnlMediaLeftConfig.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblMediaGrid.Controls.Add($pnlMediaLeftConfig, 0, 0)

$lblVf = New-Object System.Windows.Forms.Label ;
$lblVf.Text="Video Format:"; $lblVf.Font=$StandartFont; $lblVf.Location=New-Object System.Drawing.Point(5,5); $lblVf.Size=New-Object System.Drawing.Size(100,20); $pnlMediaLeftConfig.Controls.Add($lblVf)
$cmbVf = New-Object System.Windows.Forms.ComboBox ; $cmbVf.Font=$StandartFont; $cmbVf.DropDownStyle=[System.Windows.Forms.ComboBoxStyle]::DropDownList; $cmbVf.Location=New-Object System.Drawing.Point(5,25); $cmbVf.Size=New-Object System.Drawing.Size(85,25); @("mp4","mkv","webm","avi")|%{$null=$cmbVf.Items.Add($_)} ;
$cmbVf.SelectedIndex=0; $pnlMediaLeftConfig.Controls.Add($cmbVf)
$lblRes = New-Object System.Windows.Forms.Label ; $lblRes.Text="Çözünürlük:"; $lblRes.Font=$StandartFont; $lblRes.Location=New-Object System.Drawing.Point(100,5); $lblRes.Size=New-Object System.Drawing.Size(100,20); $pnlMediaLeftConfig.Controls.Add($lblRes)
$cmbRes = New-Object System.Windows.Forms.ComboBox ; $cmbRes.Font=$StandartFont; $cmbRes.DropDownStyle=[System.Windows.Forms.ComboBoxStyle]::DropDownList;
$cmbRes.Location=New-Object System.Drawing.Point(100,25); $cmbRes.Size=New-Object System.Drawing.Size(100,25); @("1080p","720p","480p","360p")|%{$null=$cmbRes.Items.Add($_)} ; $cmbRes.SelectedIndex=0; $pnlMediaLeftConfig.Controls.Add($cmbRes)
$lblAf = New-Object System.Windows.Forms.Label ; $lblAf.Text="Audio Format:"; $lblAf.Font=$StandartFont; $lblAf.Location=New-Object System.Drawing.Point(210,5); $lblAf.Size=New-Object System.Drawing.Size(100,20); $pnlMediaLeftConfig.Controls.Add($lblAf)
$cmbAf = New-Object System.Windows.Forms.ComboBox ; $cmbAf.Font=$StandartFont; $cmbAf.DropDownStyle=[System.Windows.Forms.ComboBoxStyle]::DropDownList;
$cmbAf.Location=New-Object System.Drawing.Point(210,25); $cmbAf.Size=New-Object System.Drawing.Size(75,25); @("mp3","m4a","wav","flac")|%{$null=$cmbAf.Items.Add($_)} ; $cmbAf.SelectedIndex=0; $pnlMediaLeftConfig.Controls.Add($cmbAf)
$lblBit = New-Object System.Windows.Forms.Label ; $lblBit.Text="Bitrate:"; $lblBit.Font=$StandartFont; $lblBit.Location=New-Object System.Drawing.Point(295,5); $lblBit.Size=New-Object System.Drawing.Size(80,20); $pnlMediaLeftConfig.Controls.Add($lblBit)
$cmbBit = New-Object System.Windows.Forms.ComboBox ; $cmbBit.Font=$StandartFont; $cmbBit.DropDownStyle=[System.Windows.Forms.ComboBoxStyle]::DropDownList;
$cmbBit.Location=New-Object System.Drawing.Point(295,25); $cmbBit.Size=New-Object System.Drawing.Size(85,25); @("copy","320k","192k","128k")|%{$null=$cmbBit.Items.Add($_)} ; $cmbBit.SelectedIndex=0; $pnlMediaLeftConfig.Controls.Add($cmbBit)

$chkSkip = New-Object System.Windows.Forms.CheckBox ; $chkSkip.Text="Zaten hedef formatta olan dosyaları atla"; $chkSkip.Font=$StandartFont; $chkSkip.Location=New-Object System.Drawing.Point(5,65); $chkSkip.Size=New-Object System.Drawing.Size(370,25); $chkSkip.Checked=$true; $pnlMediaLeftConfig.Controls.Add($chkSkip)

# GERİ GETİRİLEN KİLİTLEME MOTORU (VİDEO)
$chkSameDirMedia = New-Object System.Windows.Forms.CheckBox ;
$chkSameDirMedia.Text="Aynı klasöre kaydet (X dizini)"; $chkSameDirMedia.Font=$StandartFont; $chkSameDirMedia.Location=New-Object System.Drawing.Point(5,95); $chkSameDirMedia.Size=New-Object System.Drawing.Size(250,25); $pnlMediaLeftConfig.Controls.Add($chkSameDirMedia)
$chkSameDirMedia.Add_Click({ Update-TargetDirectoryState $chkSameDirMedia.Checked })

$chkDeleteSource = New-Object System.Windows.Forms.CheckBox ;
$chkDeleteSource.Text="İşlem bittiğinde orijinal kaynak dosyayı sil"; $chkDeleteSource.Font=$StandartFont; $chkDeleteSource.Location=New-Object System.Drawing.Point(5,125); $chkDeleteSource.Size=New-Object System.Drawing.Size(370,25); $chkDeleteSource.ForeColor=[System.Drawing.Color]::DarkRed;
$pnlMediaLeftConfig.Controls.Add($chkDeleteSource)

$grpMediaGuide = New-Object System.Windows.Forms.GroupBox
$grpMediaGuide.Text = " 💡 Donanım & Kodlama Rehberi "
$grpMediaGuide.Font = $BoldFont
$grpMediaGuide.ForeColor = [System.Drawing.Color]::Navy
$grpMediaGuide.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblMediaGrid.Controls.Add($grpMediaGuide, 1, 0)

$txtMediaGuideText = New-Object System.Windows.Forms.TextBox
$txtMediaGuideText.Location = New-Object System.Drawing.Point(10, 22)
$txtMediaGuideText.Size = New-Object System.Drawing.Size(360, 160)
$txtMediaGuideText.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtMediaGuideText.Multiline = $true
$txtMediaGuideText.ReadOnly = $true
$txtMediaGuideText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtMediaGuideText.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtMediaGuideText.BackColor = $Form.BackColor
$txtMediaGuideText.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$txtMediaGuideText.Text = "📢 SİSTEM ÖNERİSİ: $OneriMetni`r`n`r`n" + "• NVIDIA NVENC / AMD AMF / INTEL QSV: İşlemleri ekran kartınızın özel çiplerine yaptırır. İşlemciyi (CPU) %100 yükten kurtarır...`r`n`r`n" + "• STANDART CPU (libx264): Ağır işler fakat dosya boyutunu en sıkışık hale getirir."
$txtMediaGuideText.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpMediaGuide.Controls.Add($txtMediaGuideText)

# =========================================================================================
# GÖRSEL PANELİ (FOTOĞRAF BOYUTLANDIRMA)
# =========================================================================================
$pnlImageControls = New-Object System.Windows.Forms.Panel
$pnlImageControls.Location = New-Object System.Drawing.Point($SagLeft, 195)
$pnlImageControls.Size = New-Object System.Drawing.Size(800, 310)
$pnlImageControls.Visible = $false
$Form.Controls.Add($pnlImageControls)

$grpImgFormat = New-Object System.Windows.Forms.GroupBox ;
$grpImgFormat.Text = " Fotoğraf Boyut, Kalite ve DPI Stratejileri "; $grpImgFormat.Font = $BoldFont ;
$grpImgFormat.Location = New-Object System.Drawing.Point(0, 0) ; $grpImgFormat.Size = New-Object System.Drawing.Size(800, 305) ;
$pnlImageControls.Controls.Add($grpImgFormat)

$tblImgGrid = New-Object System.Windows.Forms.TableLayoutPanel
$tblImgGrid.Location = New-Object System.Drawing.Point(10, 25)
$tblImgGrid.Size = New-Object System.Drawing.Size(780, 270)
$tblImgGrid.ColumnCount = 2
$tblImgGrid.RowCount = 1
[void]$tblImgGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 430)))
[void]$tblImgGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tblImgGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpImgFormat.Controls.Add($tblImgGrid)

$pnlImgLeftConfig = New-Object System.Windows.Forms.Panel
$pnlImgLeftConfig.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblImgGrid.Controls.Add($pnlImgLeftConfig, 0, 0)

$lblYatay = New-Object System.Windows.Forms.Label ; $lblYatay.Text = "Yatay Foto Genişlik px:" ; $lblYatay.Font = $StandartFont ;
$lblYatay.Location = New-Object System.Drawing.Point(5, 5) ; $lblYatay.Size = New-Object System.Drawing.Size(150, 20) ; $pnlImgLeftConfig.Controls.Add($lblYatay)
$numYatay = New-Object System.Windows.Forms.NumericUpDown ; $numYatay.Font = $StandartFont ; $numYatay.Minimum = 10 ;
$numYatay.Maximum = 10000 ; $numYatay.Value = 1080 ; $numYatay.Location = New-Object System.Drawing.Point(5, 25) ;
$numYatay.Size = New-Object System.Drawing.Size(120, 25) ; $pnlImgLeftConfig.Controls.Add($numYatay)

$lblDikey = New-Object System.Windows.Forms.Label ; $lblDikey.Text = "Dikey Foto Yükseklik px:" ; $lblDikey.Font = $StandartFont ;
$lblDikey.Location = New-Object System.Drawing.Point(170, 5) ; $lblDikey.Size = New-Object System.Drawing.Size(160, 20) ; $pnlImgLeftConfig.Controls.Add($lblDikey)
$numDikey = New-Object System.Windows.Forms.NumericUpDown ; $numDikey.Font = $StandartFont ; $numDikey.Minimum = 10 ;
$numDikey.Maximum = 10000 ; $numDikey.Value = 1920 ; $numDikey.Location = New-Object System.Drawing.Point(170, 25) ;
$numDikey.Size = New-Object System.Drawing.Size(120, 25) ; $pnlImgLeftConfig.Controls.Add($numDikey)

$lblQuality = New-Object System.Windows.Forms.Label ; $lblQuality.Text = "JPEG Kalite (1-100):" ; $lblQuality.Font = $StandartFont ;
$lblQuality.Location = New-Object System.Drawing.Point(315, 5) ; $lblQuality.Size = New-Object System.Drawing.Size(110, 20) ; $pnlImgLeftConfig.Controls.Add($lblQuality)
$numQuality = New-Object System.Windows.Forms.NumericUpDown ; $numQuality.Font = $StandartFont ; $numQuality.Minimum = 1 ;
$numQuality.Maximum = 100 ; $numQuality.Value = 80 ; $numQuality.Location = New-Object System.Drawing.Point(315, 25) ;
$numQuality.Size = New-Object System.Drawing.Size(95, 25) ; $pnlImgLeftConfig.Controls.Add($numQuality)

$chkDpi = New-Object System.Windows.Forms.CheckBox ; $chkDpi.Text = "Fotoğraf Çözünürlüğünü Sabitle (DPI Değiştir)" ; $chkDpi.Font = $StandartFont ;
$chkDpi.Location = New-Object System.Drawing.Point(5, 65) ; $chkDpi.Size = New-Object System.Drawing.Size(320, 25) ; $pnlImgLeftConfig.Controls.Add($chkDpi)
$numDpiYaz = New-Object System.Windows.Forms.NumericUpDown ; $numDpiYaz.Font = $StandartFont ; $numDpiYaz.Minimum = 72 ;
$numDpiYaz.Maximum = 1200 ; $numDpiYaz.Value = 300 ; $numDpiYaz.Location = New-Object System.Drawing.Point(330, 65) ;
$numDpiYaz.Size = New-Object System.Drawing.Size(80, 25) ; $numDpiYaz.Enabled = $false ; $pnlImgLeftConfig.Controls.Add($numDpiYaz)
$chkDpi.Add_Click({ $numDpiYaz.Enabled = $chkDpi.Checked })

# GERİ GETİRİLEN KİLİTLEME MOTORU (FOTOĞRAF)
$chkSameDirImg = New-Object System.Windows.Forms.CheckBox ; $chkSameDirImg.Text = "Aynı klasörün içine kaydet (X dizini)" ; $chkSameDirImg.Font = $StandartFont ;
$chkSameDirImg.Location = New-Object System.Drawing.Point(5, 100) ; $chkSameDirImg.Size = New-Object System.Drawing.Size(410, 25) ; $pnlImgLeftConfig.Controls.Add($chkSameDirImg)
$chkSameDirImg.Add_Click({ Update-TargetDirectoryState $chkSameDirImg.Checked })

$chkToJpeg = New-Object System.Windows.Forms.CheckBox ; $chkToJpeg.Text = "Tüm Formatları Doğrudan JPEG (.jpg) Formatına Zorla" ; $chkToJpeg.Font = $BoldFont ;
$chkToJpeg.Location = New-Object System.Drawing.Point(5, 135) ; $chkToJpeg.Size = New-Object System.Drawing.Size(410, 25) ; $chkToJpeg.ForeColor = [System.Drawing.Color]::DarkBlue ;
$pnlImgLeftConfig.Controls.Add($chkToJpeg)

$lblHedefFotoFormat = New-Object System.Windows.Forms.Label ; $lblHedefFotoFormat.Text = "Farklı Formata Dönüştür:" ; $lblHedefFotoFormat.Font = $StandartFont ;
$lblHedefFotoFormat.Location = New-Object System.Drawing.Point(5, 175) ; $lblHedefFotoFormat.Size = New-Object System.Drawing.Size(160, 20) ; $pnlImgLeftConfig.Controls.Add($lblHedefFotoFormat)
$cmbHedefFotoFormat = New-Object System.Windows.Forms.ComboBox ; $cmbHedefFotoFormat.Font = $StandartFont ; $cmbHedefFotoFormat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList ;
$cmbHedefFotoFormat.Location = New-Object System.Drawing.Point(170, 172) ; $cmbHedefFotoFormat.Size = New-Object System.Drawing.Size(120, 25)
@("png","jpg","bmp","gif","tiff","ico") | % { $null = $cmbHedefFotoFormat.Items.Add($_) } ; $cmbHedefFotoFormat.SelectedIndex = 0 ; $pnlImgLeftConfig.Controls.Add($cmbHedefFotoFormat)

$chkToJpeg.Add_Click({ if($chkToJpeg.Checked){ $cmbHedefFotoFormat.Enabled = $false } else { $cmbHedefFotoFormat.Enabled = $true } })

$grpImgGuide = New-Object System.Windows.Forms.GroupBox
$grpImgGuide.Text = " 💡 Görsel İşleme & Boyut Rehberi "
$grpImgGuide.Font = $BoldFont
$grpImgGuide.ForeColor = [System.Drawing.Color]::Navy
$grpImgGuide.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblImgGrid.Controls.Add($grpImgGuide, 1, 0)

$txtImgGuideText = New-Object System.Windows.Forms.TextBox
$txtImgGuideText.Location = New-Object System.Drawing.Point(10, 22)
$txtImgGuideText.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtImgGuideText.Multiline = $true
$txtImgGuideText.ReadOnly = $true
$txtImgGuideText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtImgGuideText.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtImgGuideText.BackColor = $Form.BackColor
$txtImgGuideText.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$txtImgGuideText.Text = "• AKILLI BOYUTLANDIRMA:`r`nFotoğraflarınızın en-boy oranı milimetrik korunur. Sistem görsele bakar;`r`n" +
                        "  » Fotoğraf YATAY ise: Girdiğiniz Yatay Genişlik değerini baz alarak otomatik ölçekler.`r`n" +
                        "  » Fotoğraf DİKEY ise: Girdiğiniz Dikey Yükseklik değerini temel alarak boyutlandırır.`r`n`r`n" +
                        "• KALİTE (1-100):`r`n80 değeri dosya boyutu ve netlik için mükemmel dengedir.`r`n`r`n" +
                        "• DPI AYARI:`r`nSadece profesyonel yazıcı baskı kalitesini ayarlar (Standart: 300). Ekran görüntüsünü etkilemez."
$txtImgGuideText.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpImgGuide.Controls.Add($txtImgGuideText)

# =========================================================================================
# DİNAMİK CANLI LOG AKIŞ PANELİ (ALT ALAN)
# =========================================================================================
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.BackColor = [System.Drawing.Color]::Black
$txtLog.ForeColor = [System.Drawing.Color]::LightGreen
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtLog.Location = New-Object System.Drawing.Point($SagLeft, 515)
$txtLog.Size = New-Object System.Drawing.Size(800, 320)
$Form.Controls.Add($txtLog)

# =========================================================================================
# ANA İŞLEM TETİKLEME BUTONU
# =========================================================================================
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "⚡ STÜDYO İŞLEMİNİ BAŞLAT ⚡"
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnStart.BackColor = [System.Drawing.Color]::DarkGreen
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.Location = New-Object System.Drawing.Point(20, 855)
$btnStart.Size = New-Object System.Drawing.Size(1040, 45)

# MOD DEĞİŞİMİNDE DURUMU KORUYAN TETİKLEYİCİLER
$cmbStudioMode.Add_SelectedIndexChanged({
    $chkListUzantilar.Items.Clear()
    if ($cmbStudioMode.SelectedIndex -eq 0) {
        $pnlMediaControls.Visible = $true
        $pnlImageControls.Visible = $false
        $TumUzantilarListesi | % { $null = $chkListUzantilar.Items.Add($_) }
        for($i=0; $i -lt $chkListUzantilar.Items.Count; $i++) {
            if ($chkListUzantilar.Items[$i] -in $PopulerVideolar) { $chkListUzantilar.SetItemChecked($i, $true) }
        }
        Update-TargetDirectoryState $chkSameDirMedia.Checked
    } else {
        $pnlMediaControls.Visible = $false
        $pnlImageControls.Visible = $true
        $GorselUzantilari | % { $null = $chkListUzantilar.Items.Add($_) }
        for($i=0; $i -lt $chkListUzantilar.Items.Count; $i++) { $chkListUzantilar.SetItemChecked($i, $true) }
        Update-TargetDirectoryState $chkSameDirImg.Checked
    }
    Check-FFmpegStatus
})

$btnStart.Add_Click({
    $btnStart.Enabled = $false
    $btnStart.Text = "⏳ İŞLEM YAPILIYOR, LÜTFEN BEKLEYİNİZ..."
    $btnStart.BackColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    $SecilenUzantilar = New-Object System.Collections.Generic.List[string]
    foreach ($item in $chkListUzantilar.CheckedItems) { [void]$SecilenUzantilar.Add($item.ToString()) }

    if ($cmbStudioMode.SelectedIndex -eq 0) {
        $secilenIslem = $cmbIslem.SelectedItem.ToString().Split(' ')[0]
        $secilenKodek = $cmbDonanim.SelectedItem.ToString().Split(' ')[1].Replace('(','').Replace(')','')
        $resMapping = switch($cmbRes.SelectedItem.ToString()){ "1080p"{1080} "720p"{720} "480p"{480} "360p"{360} default{1080} }
        
        Start-MediaPipeline -Islem $secilenIslem `
                            -KaynakKlasor $txtKaynak.Text `
                            -HedefKlasor $txtHedef.Text `
                            -AyniDosyayaYaz $chkSameDirMedia.Checked `
                            -KaynakSil $chkDeleteSource.Checked `
                            -AyniUzantiAtla $chkSkip.Checked `
                            -HedefFormat $cmbVf.SelectedItem.ToString() `
                            -VideoCodec $secilenKodek `
                            -HedefCozunurluk $resMapping `
                            -SesFormat $cmbAf.SelectedItem.ToString() `
                            -SesBitrate $cmbBit.SelectedItem.ToString() `
                            -LogBox $txtLog `
                            -SecilenFiltreUzantilar $SecilenUzantilar
    } else {
        Start-ImagePipeline -KaynakKlasor $txtKaynak.Text `
                            -HedefKlasor $txtHedef.Text `
                            -AyniDosyayaYaz $chkSameDirImg.Checked `
                            -JpegYap $chkToJpeg.Checked `
                            -HedefFotoFormat $cmbHedefFotoFormat.SelectedItem.ToString() `
                            -DpiDegistir $chkDpi.Checked `
                            -ManuelDPI $numDpiYaz.Value `
                            -YatayYukseklik $numYatay.Value `
                            -DikeyYukseklik $numDikey.Value `
                            -JpegKalite $numQuality.Value `
                            -LogBox $txtLog `
                            -SecilenFiltreUzantilar $SecilenUzantilar
    }

    $btnStart.Enabled = $true
    $btnStart.Text = "⚡ STÜDYO İŞLEMİNİ BAŞLAT ⚡"
    $btnStart.BackColor = [System.Drawing.Color]::DarkGreen
})

$btnInstallFFmpeg.Add_Click({
    $txtLog.AppendText("`r`n[SİSTEM] FFmpeg otomatik indirme süreci tetiklendi...`r`n")
    $btnInstallFFmpeg.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $tempZip = Join-Path $env:TEMP "ffmpeg.zip"
        $destFolder = "C:\ffmpeg"
        $binFolder = "C:\ffmpeg\bin"
        
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        $txtLog.AppendText("[1/4] Güvenli kaynaktan FFmpeg build paketleri çekiliyor...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        $url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        Invoke-WebRequest -Uri $url -OutFile $tempZip -TimeoutSec 120
        
        $txtLog.AppendText("[2/4] Zip arşivi açılıyor ve C:\ffmpeg dizinine yerleştiriliyor...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        if (Test-Path $destFolder) { Remove-Item $destFolder -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $tempZip -DestinationPath $destFolder -Force
        
        $extracted = Get-ChildItem -Path $destFolder -Directory
        if ($extracted) {
            $innerBin = Join-Path $extracted.FullName "bin"
            if (Test-Path $innerBin) {
                if (-not (Test-Path $binFolder)) { New-Item -ItemType Directory -Path $binFolder -Force | Out-Null }
                Get-ChildItem -Path $innerBin -Filter "*.exe" | % { Copy-Item $_.FullName $binFolder -Force }
            }
        }
        
        $txtLog.AppendText("[3/4] Kullanıcı Ortam Değişkenleri (User PATH) güncelleniyor...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        $oldPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($oldPath -notlike "*C:\ffmpeg\bin*") {
            $newPath = $oldPath + ";C:\ffmpeg\bin"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            $env:PATH += ";C:\ffmpeg\bin"
        }
        
        $txtLog.AppendText("[4/4] Kurulum doğrulama aşaması...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        Check-FFmpegStatus
    } catch {
        $txtLog.AppendText("[HATA] Kurulum sırasında hata: $_`r`n")
    }
    $btnInstallFFmpeg.Enabled = $true
})

$Form.Controls.Add($btnStart)

# =========================================================================================
# MASTER UNIFIED RESPONSIVE ENGINE
# =========================================================================================
$DynamicLayoutEngine = {
    $FormGenislik = $Form.ClientSize.Width
    $FormYukseklik = $Form.ClientSize.Height

    $pnlStudioMode.Width = $FormGenislik - 40
    $grpFiltre.Height = $FormYukseklik - 200
    $chkListUzantilar.Height = $grpFiltre.Height - 75

    $SagAlanGenislik = $FormGenislik - $SagLeft - 20
    $txtKaynak.Width = $SagAlanGenislik - 115
    $btnKaynak.Left = $FormGenislik - 115
    $txtHedef.Width = $SagAlanGenislik - 115
    $btnHedef.Left = $FormGenislik - 115
    
    $pnlMediaControls.Width = $SagAlanGenislik
    $grpFormat.Width = $SagAlanGenislik
    $pnlImageControls.Width = $SagAlanGenislik
    $grpImgFormat.Width = $SagAlanGenislik

    $txtLog.Left = $SagLeft
    $txtLog.Width = $SagAlanGenislik
    $txtLog.Height = $FormYukseklik - $txtLog.Top - 95
    
    $btnStart.Width = $FormGenislik - 40
    $btnStart.Top = $FormYukseklik - 65
}

$Form.Add_Resize($DynamicLayoutEngine)

# CRITICAL SECURITY LOOP FOR BRING TO FRONT IN EXE FORM
$Form.Add_Load({
    &$DynamicLayoutEngine
    $cmbStudioMode.SelectedIndex = 0
    
    # Exe tetiklendiğinde pencerelerin arkasında uyanmayı engelleme rutini
    $Form.TopMost = $true
})

$Form.Add_Shown({
    Check-FFmpegStatus
    
    # Form ekrana basılıp stabil hale geldiğinde odağı zorla al ve arka katmana kaymayı durdur
    $Form.Activate()
    $Form.BringToFront()
    $Form.TopMost = $false  # Kullanıcıyı kilitlemesin diye öne getirdikten sonra sabitlemeyi bırakıyoruz
})

# SUITE RUNNER
[System.Windows.Forms.Application]::Run($Form)