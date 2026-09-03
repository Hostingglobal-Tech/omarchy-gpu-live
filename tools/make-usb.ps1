<#
  AI-OS USB 만들기 (Windows)

  Ventoy 를 USB 에 설치하고 ISO 를 복사한다. 그 다음부터는 ISO 파일을
  그냥 복사해 넣기만 하면 여러 개를 골라 부팅할 수 있다.

  쓰는 법:
      .\make-usb.ps1 -List                        # 꽂힌 USB 목록만 본다
      .\make-usb.ps1 -Disk 2 -Iso .\aios.iso      # 2번 디스크에 굽는다

  ★관리자 권한으로 실행해야 한다.
  ★지정한 디스크를 통째로 지운다. 두 번 확인한다.
#>

param(
    [switch]$List,
    [int]$Disk = -1,
    [string]$Iso = "",
    [int]$ReserveMB = 20480   # 영구 저장용으로 뒤에 남길 공간
)

$ErrorActionPreference = "Stop"

function Say  { param($m) Write-Host $m }
function Ok   { param($m) Write-Host $m -ForegroundColor Green }
function Warn { param($m) Write-Host $m -ForegroundColor Yellow }
function Die  { param($m) Write-Host $m -ForegroundColor Red; exit 1 }

function Show-Usb {
    Say ""
    Say "꽂혀 있는 이동식 디스크:"
    Say ""
    Get-Disk | Where-Object { $_.BusType -eq 'USB' } |
        Select-Object Number,
                      @{n='크기';e={"{0:N1} GB" -f ($_.Size/1GB)}},
                      FriendlyName |
        Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Host
    Say ""
    Say "위 목록에서 Number 를 골라:  .\make-usb.ps1 -Disk <번호> -Iso <iso파일>"
    Say ""
}

if ($List) { Show-Usb; exit 0 }

# ── 관리자 확인 ──────────────────────────────────────────────────────
$admin = ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Die "관리자 권한으로 실행하라 (PowerShell 을 관리자로 열고 다시)." }

if ($Disk -lt 0 -or -not $Iso) { Show-Usb; Die "디스크 번호와 ISO 를 지정하라." }
if (-not (Test-Path $Iso))     { Die "ISO 파일이 없다: $Iso" }

# ── 이동식인지 확인 (내장 디스크 삭제 사고 방지) ────────────────────
$d = Get-Disk -Number $Disk -ErrorAction SilentlyContinue
if (-not $d)                { Die "그런 디스크가 없다: $Disk" }
if ($d.BusType -ne 'USB')   { Die "디스크 $Disk 는 USB 가 아니다 ($($d.BusType)). 내장 디스크를 지울 뻔했다 - 멈춘다." }
if ($d.IsBoot -or $d.IsSystem) { Die "디스크 $Disk 는 부팅/시스템 디스크다 - 멈춘다." }

$sizeGB = "{0:N1}" -f ($d.Size/1GB)
$isoGB  = "{0:N2}" -f ((Get-Item $Iso).Length/1GB)

Say ""
Warn "이 디스크를 통째로 지운다:"
Say  "    디스크 $Disk  ($sizeGB GB, $($d.FriendlyName))"
Say  ""
Say  "  얹을 것:  $Iso  ($isoGB GB)"
Say  ""
$ans = Read-Host "  정말 지울까? 디스크 번호를 그대로 입력하라 ($Disk)"
if ($ans -ne "$Disk") { Die "취소했다." }

# ── Ventoy 찾기 ─────────────────────────────────────────────────────
$ventoy = $null
foreach ($p in @(".\ventoy\Ventoy2Disk.exe", ".\Ventoy2Disk.exe",
                 "$env:USERPROFILE\ventoy\Ventoy2Disk.exe",
                 "C:\ventoy\Ventoy2Disk.exe")) {
    if (Test-Path $p) { $ventoy = (Resolve-Path $p).Path; break }
}
if (-not $ventoy) {
    Die @"
Ventoy 를 못 찾았다.
  https://www.ventoy.net 에서 Windows 판을 받아 압축을 풀고,
  이 스크립트와 같은 폴더에 두거나 C:\ventoy 에 두어라.
"@
}

# ── 굽기 ────────────────────────────────────────────────────────────
Say ""
Say "1/3  Ventoy 설치"
Say "     ※ Ventoy 창이 뜨면 디스크 $Disk 를 골라 Install 을 누르고,"
Say "        Option > Partition Configuration 에서 보존 공간을 $ReserveMB MB 로 잡아라"
Say "        (영구 저장을 쓰려면 필요하다. 안 쓸 거면 0 이어도 된다)"
Say ""
Start-Process -FilePath $ventoy -Wait
Say ""
Read-Host "     Ventoy 설치가 끝났으면 엔터"

Say ""
Say "2/3  USB 찾기"
Start-Sleep -Seconds 3
$vol = Get-Partition -DiskNumber $Disk -ErrorAction SilentlyContinue |
       Where-Object { $_.DriveLetter } | Select-Object -First 1
if (-not $vol) { Die "USB 드라이브 문자를 못 찾았다. 탐색기에서 보이는지 확인하라." }
$dest = "$($vol.DriveLetter):\"
Say  "     $dest"

Say ""
Say "3/3  ISO 복사 (몇 분 걸린다)"
Copy-Item -Path $Iso -Destination $dest -Force
Say ""

Ok "끝났다."
Say ""
Say "  이 USB 로 부팅하면 Ventoy 메뉴에서 ISO 를 고를 수 있다."
Say ""
Say "  ★영구 저장을 쓰려면 (저장한 것이 재부팅에 남는다):"
Say "     뒤에 남긴 보존 공간에 ext4 저장 영역을 만들고 라벨을 AIOSDATA 로 준다."
Say "     Windows 는 ext4 를 못 만드니, 이 USB 로 한 번 부팅해 리눅스에서 만들면 된다."
Say "     자세한 것은 docs/persist.md"
Say ""
